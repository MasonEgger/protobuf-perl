# ABOUTME: Unit tests for Protobuf::Codec encode of singular scalar fields.
# Covers default-omit, optional explicit presence, per-type wire types, TypeMismatch.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Codec;

# --- helpers ------------------------------------------------------------

# Build a one-message schema with the given fields and return ($codec, $full).
# Each field spec is a hashref passed straight to Protobuf::Schema::Field->new,
# minus the implied name/number which the caller supplies.
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

# A single int32 field named 'f' at field number 1.
my sub int32_field (%overrides) {
    return {
        name   => 'f',
        number => 1,
        type   => 'int32',
        %overrides,
    };
}

# --- construction -------------------------------------------------------

{
    my ( $codec, $full ) = schema_with_message( int32_field() );
    isa_ok( $codec, 'Protobuf::Codec', 'new returns a Protobuf::Codec' );
}

# --- T-codec-1: empty message encodes to "" ----------------------------

{
    my ( $codec, $full ) = schema_with_message( int32_field() );
    is( $codec->encode( $full, {} ), '', 'T-codec-1: empty message -> ""' );
}

# --- T-codec-2: singular int32 = 0 default-omits -----------------------

{
    my ( $codec, $full ) = schema_with_message( int32_field() );
    is( $codec->encode( $full, { f => 0 } ),
        '', 'T-codec-2: int32=0 default-omitted -> ""' );
}

# --- T-codec-3: singular int32 = 42 -> tag + varint --------------------

{
    my ( $codec, $full ) = schema_with_message( int32_field() );
    is(
        $codec->encode( $full, { f => 42 } ),
        "\x08\x2a",
        'T-codec-3: int32=42 -> tag 0x08 + varint 0x2a'
    );
}

# --- T-codec-4: optional int32 = 0 IS serialized -----------------------

{
    my ( $codec, $full ) =
        schema_with_message( int32_field( label => 'optional' ) );
    is(
        $codec->encode( $full, { f => 0 } ),
        "\x08\x00",
        'T-codec-4: optional int32=0 (explicit presence) -> 2 bytes'
    );
}

# An unset optional field is still omitted (no value -> nothing on the wire).
{
    my ( $codec, $full ) =
        schema_with_message( int32_field( label => 'optional' ) );
    is(
        $codec->encode( $full, {} ),
        '',
        'optional int32 unset -> ""'
    );
}

# --- T-codec-5: one field per scalar type, correct wire type -----------

# Each row: proto3 type, a non-default value, the exact expected bytes for a
# field numbered 1 carrying that value.
my @scalar_cases = (
    [ 'int32',    1, "\x08\x01" ],                         # varint, fn1
    [ 'int64',    1, "\x08\x01" ],                         # varint
    [ 'uint32',   1, "\x08\x01" ],                         # varint
    [ 'uint64',   1, "\x08\x01" ],                         # varint
    [ 'bool',     1, "\x08\x01" ],                         # varint
    [ 'enum',     2, "\x08\x02" ],                         # varint
    [ 'sint32',  -1, "\x08\x01" ],                         # zigzag(-1)=1
    [ 'sint64',  -1, "\x08\x01" ],                         # zigzag(-1)=1
    [ 'fixed32',  1, "\x0d" . pack( 'V', 1 ) ],            # I32, fn1
    [ 'sfixed32', 1, "\x0d" . pack( 'V', 1 ) ],            # I32
    [ 'float',  1.0, "\x0d" . pack( 'f<', 1.0 ) ],         # I32
    [ 'fixed64',  1, "\x09" . pack( 'Q<', 1 ) ],           # I64, fn1
    [ 'sfixed64', 1, "\x09" . pack( 'Q<', 1 ) ],           # I64
    [ 'double', 1.0, "\x09" . pack( 'd<', 1.0 ) ],         # I64
    [ 'string', 'hi', "\x0a\x02hi" ],                      # LEN, fn1
    [ 'bytes', "\x00\xff", "\x0a\x02\x00\xff" ],           # LEN raw bytes
);

for my $case (@scalar_cases) {
    my ( $type, $value, $expected ) = @$case;
    my ( $codec, $full ) =
        schema_with_message( int32_field( type => $type ) );
    is(
        $codec->encode( $full, { f => $value } ),
        $expected,
        "T-codec-5: singular $type encodes to expected wire bytes"
    );
}

# sint32 zigzag: 1 -> zigzag(1)=2.
{
    my ( $codec, $full ) =
        schema_with_message( int32_field( type => 'sint32' ) );
    is(
        $codec->encode( $full, { f => 1 } ),
        "\x08\x02",
        'sint32=1 zigzag-encodes to varint 2'
    );
}

# bytes default (empty) is omitted; string default (empty) is omitted.
{
    my ( $codec, $full ) =
        schema_with_message( int32_field( type => 'string' ) );
    is( $codec->encode( $full, { f => '' } ),
        '', 'empty string default-omitted' );
}
{
    my ( $codec, $full ) =
        schema_with_message( int32_field( type => 'bytes' ) );
    is( $codec->encode( $full, { f => '' } ),
        '', 'empty bytes default-omitted' );
}

# --- field-number ordering ---------------------------------------------

# Two fields out of numeric order in the hash still encode in field-number
# order on the wire.
{
    my ( $codec, $full ) = schema_with_message(
        { name => 'a', number => 1, type => 'int32' },
        { name => 'b', number => 2, type => 'int32' },
    );
    is(
        $codec->encode( $full, { b => 2, a => 1 } ),
        "\x08\x01\x10\x02",
        'fields emitted in field-number order'
    );
}

# --- T-codec-6: unknown message type ------------------------------------

{
    my ( $codec, $full ) = schema_with_message( int32_field() );
    my $err;
    eval { $codec->encode( 'pkg.Nope', {} ); 1 } or $err = $@;
    ok( $err, 'encode of unknown type dies' );
    isa_ok( $err, 'Protobuf::Exception::Codec::UnknownType',
        'unknown type -> UnknownType' );
}

# --- T-codec-6: type mismatch -------------------------------------------

{
    my ( $codec, $full ) = schema_with_message( int32_field() );
    my $err;
    eval { $codec->encode( $full, { f => 'not-a-number' } ); 1 } or $err = $@;
    ok( $err, 'encode of wrong-type value dies' );
    isa_ok( $err, 'Protobuf::Exception::Codec::TypeMismatch',
        'wrong-type value -> TypeMismatch' );
    like( "$err", qr/\bf\b/,     'TypeMismatch names the field' );
    like( "$err", qr/int32/,     'TypeMismatch names the expected type' );
}

done_testing;
