# ABOUTME: Unit tests for Protobuf::Codec encode/decode of repeated fields.
# Covers packed-by-default scalars, one-entry-per-element messages, empty-omit,
# and lenient decode of BOTH packed and unpacked forms (T-codec-5).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Wire qw(encode_tag WIRE_VARINT WIRE_LEN);
use Protobuf::Codec;

# --- helpers ------------------------------------------------------------

# Build a schema from a list of Schema::Message instances and return the codec.
my sub codec_for (@messages) {
    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [@messages],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    return Protobuf::Codec->new( schema => $schema );
}

# A one-message schema with the given fields; returns ($codec, $full_name).
my sub schema_with_message (@field_specs) {
    my @fields = map { Protobuf::Schema::Field->new(%$_) } @field_specs;
    my $message = Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => \@fields,
    );
    return ( codec_for($message), 'pkg.M' );
}

# A single repeated field named 'f' at field number 1.
my sub repeated_field (%overrides) {
    return {
        name   => 'f',
        number => 1,
        type   => 'int32',
        label  => 'repeated',
        %overrides,
    };
}

# --- 12.1 / T-codec-5: repeated int32 [1,2,3] -> packed 5 bytes ---------

{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    is(
        $codec->encode( $full, { f => [ 1, 2, 3 ] } ),
        "\x0a\x03\x01\x02\x03",
        'T-codec-5: repeated int32 [1,2,3] -> packed LEN (tag 0x0a, len 3, payload)'
    );
}

# --- 12.2: decode the packed block back to [1,2,3] ---------------------

{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    is_deeply(
        $codec->decode( $full, "\x0a\x03\x01\x02\x03" ),
        { f => [ 1, 2, 3 ] },
        '12.2: decode packed int32 block -> [1,2,3]'
    );
}

# --- 12.3: decode the UNPACKED form for a scalar repeated field --------

# Each element written as its own VARINT-tagged occurrence (field 1).
{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    my $bytes = "\x08\x01" . "\x08\x02" . "\x08\x03";    # f=1, f=2, f=3 unpacked
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => [ 1, 2, 3 ] },
        '12.3: decode unpacked scalar repeated -> [1,2,3]'
    );
}

# Round-trip: packed encode then decode gives the original list.
{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    my $bytes = $codec->encode( $full, { f => [ 10, 20, 300 ] } );
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => [ 10, 20, 300 ] },
        '12.3: repeated int32 round-trips through packed encoding'
    );
}

# A repeated string is NOT packable: one LEN-tagged entry per element.
{
    my ( $codec, $full ) =
        schema_with_message( repeated_field( type => 'string' ) );
    is(
        $codec->encode( $full, { f => [ 'ab', 'cd' ] } ),
        "\x0a\x02ab" . "\x0a\x02cd",
        '12.3: repeated string -> one tag-prefixed entry per element'
    );
    is_deeply(
        $codec->decode( $full, "\x0a\x02ab" . "\x0a\x02cd" ),
        { f => [ 'ab', 'cd' ] },
        '12.3: repeated string round-trips one-entry-per-element'
    );
}

# --- 12.4: repeated message -> one entry per element, round-trip -------

{
    # Inner message: int32 v = 1.
    my $inner = Protobuf::Schema::Message->new(
        name      => 'Inner',
        full_name => 'pkg.Inner',
        fields    => [
            Protobuf::Schema::Field->new(
                name => 'v', number => 1, type => 'int32',
            ),
        ],
    );
    # Outer message: repeated Inner f = 1.
    my $outer = Protobuf::Schema::Message->new(
        name      => 'Outer',
        full_name => 'pkg.Outer',
        fields    => [
            Protobuf::Schema::Field->new(
                name      => 'f',
                number    => 1,
                type      => 'message',
                label     => 'repeated',
                type_name => 'pkg.Inner',
            ),
        ],
    );
    my $codec = codec_for( $inner, $outer );

    my $value = { f => [ { v => 1 }, { v => 2 } ] };
    my $bytes = $codec->encode( 'pkg.Outer', $value );

    # Each element: tag(1,LEN) + len + inner-bytes. Inner {v=>1} = \x08\x01.
    is(
        $bytes,
        "\x0a\x02\x08\x01" . "\x0a\x02\x08\x02",
        '12.4: repeated message -> one tag-prefixed LEN entry per element'
    );
    is_deeply(
        $codec->decode( 'pkg.Outer', $bytes ),
        $value,
        '12.4: repeated message round-trips'
    );
}

# --- 12.5: empty repeated field is omitted entirely -------------------

{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    is(
        $codec->encode( $full, { f => [] } ),
        '',
        '12.5: empty repeated scalar -> omitted'
    );
}
{
    my ( $codec, $full ) =
        schema_with_message( repeated_field( type => 'string' ) );
    is(
        $codec->encode( $full, { f => [] } ),
        '',
        '12.5: empty repeated string -> omitted'
    );
}

# An absent repeated field decodes to the empty list.
{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    is_deeply(
        $codec->decode( $full, '' ),
        { f => [] },
        '12.5: omitted repeated decodes to empty arrayref'
    );
}

# --- 12.6: mixed packed + unpacked occurrences concatenate in order ----

{
    my ( $codec, $full ) = schema_with_message( repeated_field() );
    # packed [1,2] then unpacked 3 then packed [4,5].
    my $bytes =
        "\x0a\x02\x01\x02"      # packed 1,2
        . "\x08\x03"            # unpacked 3
        . "\x0a\x02\x04\x05";   # packed 4,5
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => [ 1, 2, 3, 4, 5 ] },
        '12.6: mixed packed+unpacked occurrences concatenate in wire order'
    );
}

done_testing;
