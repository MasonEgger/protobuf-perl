# ABOUTME: Codec tests for proto2/editions semantics — explicit field presence,
# closed-enum unknown-value routing, and EXPANDED-by-default repeated encoding.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Enum;
use Proto3::Schema::Features;
use Proto3::Wire qw(encode_tag WIRE_VARINT WIRE_LEN);
use Proto3::Codec;

# --- helpers ------------------------------------------------------------

# Resolve a feature set for the given edition and install it on every field and
# enum, mirroring what Schema->resolve does for a fully-built schema. Building
# the FeatureSet by hand keeps the test independent of the FDS bootstrap.
my sub install_features ($edition, $fields, $enums = []) {
    my $features = Proto3::Schema::Features->for_edition($edition);
    $_->set_features($features) for @$fields;
    $_->set_features($features) for @$enums;
    return;
}

# Build a one-message schema from already-constructed field objects and return
# ($codec, $full_name). preserve_unknown_fields is forwarded so closed-enum
# routing can be observed as preserved bytes.
my sub codec_for ($fields, %opts) {
    my $message = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => $fields,
    );
    my $file = Proto3::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [$message],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file($file);

    my $codec = Proto3::Codec->new( schema => $schema, %opts );
    return ( $codec, 'pkg.M' );
}

# ----------------------------------------------------------------------
# 1. Explicit presence on ENCODE: a proto2 singular scalar at its zero value
#    IS emitted when set in the hashref, exactly like a proto3 `optional`.
# ----------------------------------------------------------------------
{
    my $f = Proto3::Schema::Field->new(
        name => 'f', number => 1, type => 'int32', label => 'singular',
    );
    install_features( 'proto2', [$f] );
    is( $f->presence, 'explicit', 'proto2 singular scalar has explicit presence' );

    my ( $codec, $full ) = codec_for( [$f] );
    is(
        $codec->encode( $full, { f => 0 } ),
        encode_tag( 1, WIRE_VARINT ) . "\x00",
        'proto2 explicit field set to zero IS emitted',
    );
    is(
        $codec->encode( $full, {} ),
        '',
        'proto2 explicit field absent from hashref is omitted',
    );
}

# Proto3 implicit-presence scalar at zero stays omitted (no regression).
{
    my $f = Proto3::Schema::Field->new(
        name => 'f', number => 1, type => 'int32', label => 'singular',
    );
    install_features( 'proto3', [$f] );
    is( $f->presence, 'implicit', 'proto3 singular scalar has implicit presence' );

    my ( $codec, $full ) = codec_for( [$f] );
    is(
        $codec->encode( $full, { f => 0 } ),
        '',
        'proto3 implicit field at zero is omitted',
    );
}

# ----------------------------------------------------------------------
# 2. Explicit presence on DECODE: an absent proto2 field stays ABSENT from the
#    result hashref (no implicit default-fill); a proto3 implicit field fills.
# ----------------------------------------------------------------------
{
    my $f = Proto3::Schema::Field->new(
        name => 'f', number => 1, type => 'int32', label => 'singular',
    );
    install_features( 'proto2', [$f] );

    my ( $codec, $full ) = codec_for( [$f] );
    is_deeply(
        $codec->decode( $full, '' ),
        {},
        'proto2 explicit field absent on the wire stays absent (no default-fill)',
    );
    is_deeply(
        $codec->decode( $full, encode_tag( 1, WIRE_VARINT ) . "\x00" ),
        { f => 0 },
        'proto2 explicit field present at zero decodes as set',
    );
}

{
    my $f = Proto3::Schema::Field->new(
        name => 'f', number => 1, type => 'int32', label => 'singular',
    );
    install_features( 'proto3', [$f] );

    my ( $codec, $full ) = codec_for( [$f] );
    is_deeply(
        $codec->decode( $full, '' ),
        { f => 0 },
        'proto3 implicit field absent on the wire fills its default',
    );
}

# ----------------------------------------------------------------------
# 3. Closed enums: an UNKNOWN numeric value on the wire is routed OUT of the
#    field (the field reads as unset) and preserved as unknown bytes so it
#    round-trips on re-encode. Open enums keep the unknown value in-field.
# ----------------------------------------------------------------------
{
    my $enum = Proto3::Schema::Enum->new(
        name      => 'E',
        full_name => 'pkg.E',
        values    => [ { name => 'FOO', number => 0 }, { name => 'BAR', number => 1 } ],
    );
    my $f = Proto3::Schema::Field->new(
        name => 'e', number => 1, type => 'enum', label => 'singular',
        type_name => '.pkg.E',
    );
    $f->set_type_ref($enum);
    install_features( 'proto2', [$f], [$enum] );
    ok( $enum->closed, 'proto2 enum is closed' );

    my ( $codec, $full ) =
        codec_for( [$f], preserve_unknown_fields => 1 );

    # Unknown enum value 7 (not FOO/BAR) on the wire.
    my $wire = encode_tag( 1, WIRE_VARINT ) . "\x07";
    my $decoded = $codec->decode( $full, $wire );
    ok( !exists $decoded->{e}, 'closed-enum unknown value is not stored in the field' );
    is(
        $decoded->{'__unknown_fields__'}, $wire,
        'closed-enum unknown value is routed to the unknown-field set',
    );
    is(
        $codec->encode( $full, $decoded ), $wire,
        'closed-enum unknown value round-trips on re-encode',
    );

    # A KNOWN enum value is stored in-field as usual.
    my $known = encode_tag( 1, WIRE_VARINT ) . "\x01";
    is_deeply(
        $codec->decode( $full, $known ),
        { e => 1 },
        'closed-enum known value is stored in the field',
    );
}

{
    my $enum = Proto3::Schema::Enum->new(
        name      => 'E',
        full_name => 'pkg.E',
        values    => [ { name => 'FOO', number => 0 }, { name => 'BAR', number => 1 } ],
    );
    my $f = Proto3::Schema::Field->new(
        name => 'e', number => 1, type => 'enum', label => 'singular',
        type_name => '.pkg.E',
    );
    $f->set_type_ref($enum);
    install_features( 'proto3', [$f], [$enum] );
    ok( !$enum->closed, 'proto3 enum is open' );

    my ( $codec, $full ) = codec_for( [$f] );
    my $wire = encode_tag( 1, WIRE_VARINT ) . "\x07";
    is_deeply(
        $codec->decode( $full, $wire ),
        { e => 7 },
        'open-enum unknown value stays in the field',
    );
}

# ----------------------------------------------------------------------
# 4. Packed defaults on ENCODE: proto2 repeated scalar encodes EXPANDED (one
#    tag per element); proto3 repeated scalar encodes PACKED (one LEN block).
# ----------------------------------------------------------------------
{
    my $f = Proto3::Schema::Field->new(
        name => 'r', number => 1, type => 'int32', label => 'repeated',
    );
    install_features( 'proto2', [$f] );
    ok( !$f->is_packed, 'proto2 repeated scalar is not packed' );

    my ( $codec, $full ) = codec_for( [$f] );
    my $expanded =
          encode_tag( 1, WIRE_VARINT ) . "\x01"
        . encode_tag( 1, WIRE_VARINT ) . "\x02";
    is(
        $codec->encode( $full, { r => [ 1, 2 ] } ),
        $expanded,
        'proto2 repeated scalar encodes EXPANDED',
    );
    # Lenient decode still accepts the expanded form back.
    is_deeply(
        $codec->decode( $full, $expanded ),
        { r => [ 1, 2 ] },
        'proto2 expanded repeated decodes back',
    );
}

{
    my $f = Proto3::Schema::Field->new(
        name => 'r', number => 1, type => 'int32', label => 'repeated',
    );
    install_features( 'proto3', [$f] );
    ok( $f->is_packed, 'proto3 repeated scalar is packed' );

    my ( $codec, $full ) = codec_for( [$f] );
    my $packed =
          encode_tag( 1, WIRE_LEN )
        . Proto3::Wire::encode_varint(2)
        . "\x01\x02";
    is(
        $codec->encode( $full, { r => [ 1, 2 ] } ),
        $packed,
        'proto3 repeated scalar encodes PACKED',
    );
}

done_testing;
