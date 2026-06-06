# ABOUTME: Unit tests for Protobuf::Codec unknown-field preservation (Step 15).
# preserve_unknown_fields stores raw unknown-tag bytes under {__unknown_fields__}
# and re-emits them byte-for-byte after known fields; default drops them.
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
# Extra constructor args (e.g. preserve_unknown_fields => 1) pass through to the
# Protobuf::Codec constructor.
my sub schema_with_message ($field_specs, %codec_args) {
    my @fields = map { Protobuf::Schema::Field->new(%$_) } @$field_specs;

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

    my $codec = Protobuf::Codec->new( schema => $schema, %codec_args );
    return ( $codec, 'pkg.M' );
}

# A single int32 field named 'f' at field number 1.
my sub field_f (%overrides) {
    return { name => 'f', number => 1, type => 'int32', %overrides };
}

# --- 15.1 / T-codec-8b: preserve_unknown_fields stores + re-emits -------

{
    my ( $codec, $full ) =
        schema_with_message( [ field_f() ], preserve_unknown_fields => 1 );

    # Wire: known f=42, then three unknown fields spanning every wire type:
    #   field 2 VARINT (150), field 3 LEN ("abc"), field 4 I64 (8 bytes),
    #   field 5 I32 (4 bytes).
    my $unknown_varint = encode_tag( 2, WIRE_VARINT ) . "\x96\x01";
    my $unknown_len    = encode_tag( 3, WIRE_LEN ) . "\x03abc";
    my $unknown_i64    = encode_tag( 4, WIRE_I64 ) . ( "\x11" x 8 );
    my $unknown_i32    = encode_tag( 5, WIRE_I32 ) . ( "\x22" x 4 );
    my $unknown_all =
        $unknown_varint . $unknown_len . $unknown_i64 . $unknown_i32;

    my $bytes = "\x08\x2a" . $unknown_all;    # f=42 then the unknowns

    my $decoded = $codec->decode( $full, $bytes );

    is( $decoded->{f}, 42, '15.1: known field still decodes alongside unknowns' );
    ok(
        exists $decoded->{__unknown_fields__},
        '15.1: unknown bytes stored under __unknown_fields__'
    );
    is(
        $decoded->{__unknown_fields__},
        $unknown_all,
        '15.1: raw unknown-field bytes preserved exactly, in wire order'
    );

    # Re-encode: known fields first, then the preserved unknown bytes verbatim.
    my $reencoded = $codec->encode( $full, $decoded );
    is(
        $reencoded,
        "\x08\x2a" . $unknown_all,
        '15.1: re-encode reproduces unknown bytes byte-for-byte after known fields'
    );
}

# Preservation with NO known fields present: the whole buffer is unknown.
{
    my ( $codec, $full ) =
        schema_with_message( [ field_f( label => 'optional' ) ],
        preserve_unknown_fields => 1 );

    my $unknown = encode_tag( 7, WIRE_VARINT ) . "\x01";
    my $decoded = $codec->decode( $full, $unknown );
    is(
        $decoded->{__unknown_fields__},
        $unknown,
        '15.1: a buffer of only unknown fields is fully preserved'
    );
    is(
        $codec->encode( $full, $decoded ),
        $unknown,
        '15.1: re-encode of only-unknown buffer round-trips'
    );
}

# A decode with NO unknown fields leaves __unknown_fields__ absent even when
# preservation is on (no empty marker key).
{
    my ( $codec, $full ) =
        schema_with_message( [ field_f() ], preserve_unknown_fields => 1 );
    my $decoded = $codec->decode( $full, "\x08\x2a" );
    ok(
        !exists $decoded->{__unknown_fields__},
        '15.1: no unknowns -> __unknown_fields__ key is absent'
    );
}

# --- 15.2: default (flag off) drops unknown fields ----------------------

{
    my ( $codec, $full ) = schema_with_message( [ field_f() ] );    # flag off

    my $unknown = encode_tag( 2, WIRE_VARINT ) . "\x96\x01";
    my $decoded = $codec->decode( $full, "\x08\x2a" . $unknown );

    is( $decoded->{f}, 42, '15.2: known field decodes with flag off' );
    ok(
        !exists $decoded->{__unknown_fields__},
        '15.2: default drops unknown fields (no __unknown_fields__ key)'
    );

    # And re-encoding the result emits ONLY the known field — nothing preserved.
    is(
        $codec->encode( $full, $decoded ),
        "\x08\x2a",
        '15.2: re-encode with flag off does not resurrect unknown bytes'
    );
}

# With the flag off, an explicit __unknown_fields__ key in the value hashref is
# NOT treated as a magic field (it would be a TypeMismatch-free no-op): it is
# simply ignored on encode because it is not a declared field.
{
    my ( $codec, $full ) = schema_with_message( [ field_f() ] );
    is(
        $codec->encode( $full, { f => 1, __unknown_fields__ => "\xff\xff" } ),
        "\x08\x01",
        '15.2: __unknown_fields__ in value is ignored when preservation is off'
    );
}

done_testing;
