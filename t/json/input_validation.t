# ABOUTME: Proto3::JSON strict input-validation tests — malformed JSON that
# protoc rejects must throw on decode: out-of-range / non-integral integers,
# non-string for a string field, wrong repeated element types, top-level null,
# duplicate oneof members, and out-of-range float/double literals.
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
use Proto3::Codec;

# --- helpers ------------------------------------------------------------

my sub codec_for {
    my (%args) = @_;
    my $file = Proto3::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => $args{messages} // [],
        enums    => $args{enums}    // [],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    return Proto3::Codec->new( schema => $schema );
}

my sub scalar_field ( $name, $number, $type, %extra ) {
    return Proto3::Schema::Field->new(
        name => $name, number => $number, type => $type, %extra,
    );
}

# A message with one scalar field of the given type, decoded from $json. Returns
# the thrown exception ($@), or undef if no exception was thrown.
my sub decode_err {
    my ( $type, $json, %extra ) = @_;
    my $message = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [ scalar_field( 'f', 1, $type, %extra ) ],
    );
    my $codec = codec_for( messages => [$message] );
    eval { $codec->decode_json( 'pkg.M', $json ); 1 };
    return $@;
}

# A message with one repeated scalar field of the given type, decoded from $json.
my sub decode_repeated_err {
    my ( $type, $json ) = @_;
    my $message = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [ scalar_field( 'f', 1, $type, label => 'repeated' ) ],
    );
    my $codec = codec_for( messages => [$message] );
    eval { $codec->decode_json( 'pkg.M', $json ); 1 };
    return $@;
}

# --- integer fields: out-of-range, fractional, junk reject --------------

# int32 range is [-2^31, 2^31-1].
ok( decode_err( 'int32', '{"f": 2147483648}' ),
    'int32 above 2^31-1 rejected (Int32FieldTooLarge)' );
ok( decode_err( 'int32', '{"f": -2147483649}' ),
    'int32 below -2^31 rejected (Int32FieldTooSmall)' );
ok( decode_err( 'int32', '{"f": 0.5}' ),
    'int32 fractional number rejected (Int32FieldNotInteger)' );
ok( decode_err( 'int32', '{"f": " 1"}' ),
    'int32 string with leading space rejected (Int32FieldLeadingSpace)' );
ok( decode_err( 'int32', '{"f": "1 "}' ),
    'int32 string with trailing space rejected (Int32FieldTrailingSpace)' );
ok( decode_err( 'int32', '{"f": "1e5"}' ),
    'int32 non-integral exponent string rejected' );
ok( decode_err( 'int32', '{"f": ""}' ),
    'int32 empty string rejected' );

# uint32 range is [0, 2^32-1].
ok( decode_err( 'uint32', '{"f": 4294967296}' ),
    'uint32 above 2^32-1 rejected (Uint32FieldTooLarge)' );
ok( decode_err( 'uint32', '{"f": -1}' ),
    'uint32 negative rejected' );
ok( decode_err( 'uint32', '{"f": 0.5}' ),
    'uint32 fractional rejected (Uint32FieldNotInteger)' );

# int64 range is [-2^63, 2^63-1]; accepted from string OR number.
ok( decode_err( 'int64', '{"f": "9223372036854775808"}' ),
    'int64 above 2^63-1 rejected (Int64FieldTooLarge)' );
ok( decode_err( 'int64', '{"f": "-9223372036854775809"}' ),
    'int64 below -2^63 rejected (Int64FieldTooSmall)' );
ok( decode_err( 'int64', '{"f": "0.5"}' ),
    'int64 fractional string rejected (Int64FieldNotInteger)' );

# uint64 range is [0, 2^64-1].
ok( decode_err( 'uint64', '{"f": "18446744073709551616"}' ),
    'uint64 above 2^64-1 rejected (Uint64FieldTooLarge)' );
ok( decode_err( 'uint64', '{"f": "0.5"}' ),
    'uint64 fractional string rejected (Uint64FieldNotInteger)' );

# --- string field: a non-string JSON value is rejected ------------------

ok( decode_err( 'string', '{"f": 12345}' ),
    'string field given a number rejected (StringFieldNotAString)' );
ok( decode_err( 'string', '{"f": true}' ),
    'string field given a bool rejected' );

# --- repeated field wrong element types ---------------------------------

ok( decode_repeated_err( 'int32', '{"f": [1, false, 3, 4]}' ),
    'repeated int32 with a bool element rejected (ExpectingIntegersGotBool)' );
ok( decode_repeated_err( 'string', '{"f": ["1", "2", false, "4"]}' ),
    'repeated string with a bool element rejected (ExpectingStringsGotBool)' );
ok( decode_repeated_err( 'string', '{"f": ["1", 2, "3", "4"]}' ),
    'repeated string with an int element rejected (ExpectingStringsGotInt)' );
ok( decode_repeated_err( 'string', '{"f": ["1", 2, "3", {"a": 4}]}' ),
    'repeated string with a message element rejected (ExpectingStringsGotMessage)' );

# --- top-level null is not a valid message ------------------------------

ok( decode_err( 'int32', 'null' ),
    'top-level JSON null rejected (RejectTopLevelNull)' );

# --- duplicate oneof members --------------------------------------------

{
    my $message = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [
            scalar_field( 'oneof_uint32', 1, 'uint32', oneof_index => 0 ),
            scalar_field( 'oneof_string', 2, 'string', oneof_index => 0 ),
        ],
    );
    my $codec = codec_for( messages => [$message] );
    eval {
        $codec->decode_json( 'pkg.M',
            '{"oneofUint32": 1, "oneofString": "test"}' );
        1;
    };
    ok( $@, 'two members of the same oneof rejected (OneofFieldDuplicate)' );
}

# --- float / double out of representable range --------------------------

ok( decode_err( 'float', '{"f": 3.502823e+38}' ),
    'float above max finite rejected (FloatFieldTooLarge)' );
ok( decode_err( 'float', '{"f": -3.502823e+38}' ),
    'float below min finite rejected (FloatFieldTooSmall)' );
ok( decode_err( 'double', '{"f": -1.89769e+308}' ),
    'double below min finite rejected (DoubleFieldTooSmall)' );

# --- valid forms STILL accepted (must not over-reject) ------------------

{
    my $message = Proto3::Schema::Message->new(
        name      => 'Valid',
        full_name => 'pkg.Valid',
        fields    => [
            scalar_field( 'i64', 1, 'int64' ),
            scalar_field( 'u64', 2, 'uint64' ),
            scalar_field( 'i32', 3, 'int32' ),
            scalar_field( 'str', 4, 'string' ),
            scalar_field( 'fl',  5, 'float' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    # int64 from BOTH string and number; uint64 max value from string.
    my $d1 = $codec->decode_json( 'pkg.Valid',
        '{"i64": "123", "u64": "18446744073709551615", "i32": 5, "str": "ok", "fl": 1.5}' );
    is( "$d1->{i64}", '123', 'int64 from string still accepted' );
    is( "$d1->{u64}", '18446744073709551615', 'uint64 max value accepted' );

    my $d2 = $codec->decode_json( 'pkg.Valid', '{"i64": 456}' );
    is( "$d2->{i64}", '456', 'int64 from number still accepted' );

    # Integer-valued JSON number for an int field is fine, including a value
    # with an exponent that is integral (1e2 == 100).
    my $d3 = $codec->decode_json( 'pkg.Valid', '{"i32": -2147483648}' );
    is( $d3->{i32}, -2147483648, 'int32 minimum still accepted' );
}

done_testing;
