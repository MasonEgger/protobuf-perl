# ABOUTME: Unit tests for Protobuf::Codec decode of singular scalar fields.
# Covers known-field decode, round-trip, defaults, unknown-field skip, last-wins, errors.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Wire qw(encode_tag WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32);
use Protobuf::Codec;

# --- helpers ------------------------------------------------------------

# Build a one-message schema with the given fields and return ($codec, $full).
my sub schema_with_message (@field_specs) {
    my @fields = map { Protobuf::Schema::Field->new(%$_) } @field_specs;

    my $message = Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => \@fields,
    );

    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [$message],
    );

    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    my $codec = Protobuf::Codec->new( schema => $schema );
    return ( $codec, 'pkg.M' );
}

# A single field named 'f' at field number 1 (int32 by default).
my sub field_f (%overrides) {
    return {
        name   => 'f',
        number => 1,
        type   => 'int32',
        %overrides,
    };
}

# --- 11.1: decode \x08\x2a -> {f=>42} -----------------------------------

{
    my ( $codec, $full ) = schema_with_message( field_f() );
    is_deeply(
        $codec->decode( $full, "\x08\x2a" ),
        { f => 42 },
        '11.1: decode tag 0x08 + varint 0x2a -> {f=>42}'
    );
}

# --- 11.2: round-trip each scalar type ----------------------------------

# Each row: proto3 type, a representative non-default value.
my @round_trip_cases = (
    [ 'int32',    42 ],
    [ 'int64',    123456 ],
    [ 'uint32',   42 ],
    [ 'uint64',   123456 ],
    [ 'bool',     1 ],
    [ 'enum',     7 ],
    [ 'sint32',   -5 ],
    [ 'sint64',   -123456 ],
    [ 'fixed32',  4294967295 ],
    [ 'sfixed32', 12345 ],
    [ 'fixed64',  1234567890 ],
    [ 'sfixed64', 987654321 ],
    [ 'string',   'hello' ],
    [ 'bytes',    "\x00\xff\x7f" ],
);

for my $case (@round_trip_cases) {
    my ( $type, $value ) = @$case;
    my ( $codec, $full ) = schema_with_message( field_f( type => $type ) );
    my $bytes   = $codec->encode( $full, { f => $value } );
    my $decoded = $codec->decode( $full, $bytes );
    is( $decoded->{f}, $value, "11.2: $type round-trips" );
}

# float / double round-trip (compare numerically with tolerance for floats).
{
    my ( $codec, $full ) = schema_with_message( field_f( type => 'float' ) );
    my $decoded = $codec->decode( $full, $codec->encode( $full, { f => 1.5 } ) );
    cmp_ok( abs( $decoded->{f} - 1.5 ), '<', 1e-6, '11.2: float round-trips' );
}
{
    my ( $codec, $full ) = schema_with_message( field_f( type => 'double' ) );
    my $decoded =
        $codec->decode( $full, $codec->encode( $full, { f => 3.14159 } ) );
    cmp_ok( abs( $decoded->{f} - 3.14159 ), '<', 1e-9, '11.2: double round-trips' );
}

# --- 11.3: omitted field decodes to proto3 default ----------------------

{
    my ( $codec, $full ) = schema_with_message( field_f( type => 'int32' ) );
    is_deeply(
        $codec->decode( $full, '' ),
        { f => 0 },
        '11.3: omitted int32 -> default 0'
    );
}
{
    my ( $codec, $full ) = schema_with_message( field_f( type => 'string' ) );
    is_deeply(
        $codec->decode( $full, '' ),
        { f => '' },
        '11.3: omitted string -> default ""'
    );
}
{
    my ( $codec, $full ) = schema_with_message( field_f( type => 'bool' ) );
    is_deeply(
        $codec->decode( $full, '' ),
        { f => 0 },
        '11.3: omitted bool -> default false (0)'
    );
}

# An explicit-presence (optional) field that is absent stays ABSENT.
{
    my ( $codec, $full ) =
        schema_with_message( field_f( label => 'optional' ) );
    is_deeply(
        $codec->decode( $full, '' ),
        {},
        '11.3: omitted optional int32 stays absent (no default applied)'
    );
}

# --- 11.4: unknown tag skipped by wire type, absent from result --------

# Unknown VARINT field (number 2) before known field 1.
{
    my ( $codec, $full ) = schema_with_message( field_f() );
    my $bytes = encode_tag( 2, WIRE_VARINT ) . "\x96\x01"   # unknown varint 150
        . "\x08\x2a";                                        # known f=42
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => 42 },
        '11.4a: unknown VARINT field skipped, known field decoded'
    );
}

# Unknown LEN field skips its byte payload.
{
    my ( $codec, $full ) = schema_with_message( field_f() );
    my $bytes = encode_tag( 3, WIRE_LEN ) . "\x03abc"        # unknown 3-byte LEN
        . "\x08\x2a";                                        # known f=42
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => 42 },
        '11.4b: unknown LEN field skipped, known field decoded'
    );
}

# Unknown I64 field skips 8 bytes.
{
    my ( $codec, $full ) = schema_with_message( field_f() );
    my $bytes = encode_tag( 4, WIRE_I64 ) . ( "\x00" x 8 )
        . "\x08\x2a";
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => 42 },
        '11.4c: unknown I64 field skipped, known field decoded'
    );
}

# Unknown I32 field skips 4 bytes.
{
    my ( $codec, $full ) = schema_with_message( field_f() );
    my $bytes = encode_tag( 5, WIRE_I32 ) . ( "\x00" x 4 )
        . "\x08\x2a";
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => 42 },
        '11.4d: unknown I32 field skipped, known field decoded'
    );
}

# An unknown field with no known fields present -> empty hashref (default
# only applied if the message declares the field; unknown stays absent).
{
    my ( $codec, $full ) = schema_with_message( field_f( label => 'optional' ) );
    my $bytes = encode_tag( 9, WIRE_VARINT ) . "\x01";
    is_deeply(
        $codec->decode( $full, $bytes ),
        {},
        '11.4e: unknown field is absent from result'
    );
}

# --- 11.5: duplicate singular field -> last value wins ------------------

{
    my ( $codec, $full ) = schema_with_message( field_f() );
    my $bytes = "\x08\x01" . "\x08\x02" . "\x08\x03";   # f=1, f=2, f=3
    is_deeply(
        $codec->decode( $full, $bytes ),
        { f => 3 },
        '11.5: duplicate singular int32 -> last wins'
    );
}

# --- 11.6: an unterminated unknown group raises -------------------------
# Group wire types are now first-class (proto2 groups / editions DELIMITED), so
# an unknown group field is skipped to its matching EGROUP rather than rejected
# outright. A bare group-start with no closing EGROUP is malformed and must die
# as a Wire error (the group is never closed).
{
    my ( $codec, $full ) = schema_with_message( field_f() );
    # Tag for field 2 (unknown; the known field 'f' is number 1), wire type 3
    # (group start): (2<<3)|3 = 0x13, with no EGROUP following. An UNKNOWN group
    # field is skipped to its matching EGROUP; a bare unterminated one is a Wire
    # error. (Using a KNOWN field number here would instead be a wire-type
    # mismatch — see t/codec/range_and_wire_type.t for that case, B-008.)
    my $err;
    eval { $codec->decode( $full, "\x13" ); 1 } or $err = $@;
    ok( $err, '11.6: unterminated group dies' );
    isa_ok( $err, 'Protobuf::Exception::Wire',
        '11.6: unterminated group -> Wire error' );
}

# --- 11.7: truncated input propagates Wire::Truncated -------------------

{
    my ( $codec, $full ) = schema_with_message( field_f( type => 'fixed32' ) );
    # Tag says I32 (4 bytes) but only 2 payload bytes follow.
    my $bytes = encode_tag( 1, WIRE_I32 ) . "\x01\x02";
    my $err;
    eval { $codec->decode( $full, $bytes ); 1 } or $err = $@;
    ok( $err, '11.7: truncated input dies' );
    isa_ok( $err, 'Protobuf::Exception::Wire::Truncated',
        '11.7: truncated -> Wire::Truncated propagates' );
}

# --- unknown message type on decode -------------------------------------

{
    my ( $codec, $full ) = schema_with_message( field_f() );
    my $err;
    eval { $codec->decode( 'pkg.Nope', '' ); 1 } or $err = $@;
    ok( $err, 'decode of unknown type dies' );
    isa_ok( $err, 'Protobuf::Exception::Codec::UnknownType',
        'unknown type on decode -> UnknownType' );
}

done_testing;
