# ABOUTME: Protobuf::JSON encode tests (Step 28) — proto3 JSON output mapping:
# scalars, 64-bit-as-string, enum-as-name, camelCase, base64 bytes, default-omit,
# emit_defaults, WKT delegation, and maps-as-objects (spec §4.9, T-json-2..6).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use JSON::PP ();

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Schema::Enum;
use Protobuf::Codec;
use Protobuf::WKT;

# --- helpers ------------------------------------------------------------

# Build a codec over a one-file schema holding the given Schema elements.
my sub codec_for {
    my (%args) = @_;
    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => $args{messages} // [],
        enums    => $args{enums}    // [],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    return Protobuf::Codec->new( schema => $schema );
}

# Decode a JSON string back to a Perl structure for order-independent asserts.
my sub from_json ($string) {
    return JSON::PP->new->decode($string);
}

my sub scalar_field ( $name, $number, $type, %extra ) {
    return Protobuf::Schema::Field->new(
        name => $name, number => $number, type => $type, %extra,
    );
}

# --- 28.1: all scalar types serialize -----------------------------------

{
    my $message = Protobuf::Schema::Message->new(
        name      => 'Scalars',
        full_name => 'pkg.Scalars',
        fields    => [
            scalar_field( 'i32', 1, 'int32' ),
            scalar_field( 'u32', 2, 'uint32' ),
            scalar_field( 's32', 3, 'sint32' ),
            scalar_field( 'f32', 4, 'fixed32' ),
            scalar_field( 'b',   5, 'bool' ),
            scalar_field( 'fl',  6, 'float' ),
            scalar_field( 'dbl', 7, 'double' ),
            scalar_field( 'str', 8, 'string' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my $json = $codec->encode_json(
        'pkg.Scalars',
        {
            i32 => 42,
            u32 => 7,
            s32 => -3,
            f32 => 100,
            b   => 1,
            fl  => 1.5,
            dbl => 2.25,
            str => 'hi',
        },
    );
    my $got = from_json($json);

    is( $got->{i32}, 42,   '28.1: int32 serializes' );
    is( $got->{u32}, 7,    '28.1: uint32 serializes' );
    is( $got->{s32}, -3,   '28.1: sint32 serializes' );
    is( $got->{f32}, 100,  '28.1: fixed32 serializes' );
    is( $got->{b},   JSON::PP::true, '28.1: bool serializes as JSON true' );
    is( $got->{fl},  1.5,  '28.1: float serializes' );
    is( $got->{dbl}, 2.25, '28.1: double serializes' );
    is( $got->{str}, 'hi', '28.1: string serializes' );
}

# --- 28.2: 64-bit integers emit as JSON STRINGS (T-json-2 encode) -------

{
    my $message = Protobuf::Schema::Message->new(
        name      => 'Wide',
        full_name => 'pkg.Wide',
        fields    => [
            scalar_field( 'i64',  1, 'int64' ),
            scalar_field( 'u64',  2, 'uint64' ),
            scalar_field( 'fx64', 3, 'fixed64' ),
            scalar_field( 'sf64', 4, 'sfixed64' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my $json = $codec->encode_json(
        'pkg.Wide',
        { i64 => 123, u64 => 456, fx64 => 789, sf64 => -5 },
    );

    # The raw JSON text must quote every 64-bit value.
    like( $json, qr/"i64"\s*:\s*"123"/,  '28.2: int64 is a JSON string' );
    like( $json, qr/"u64"\s*:\s*"456"/,  '28.2: uint64 is a JSON string' );
    like( $json, qr/"fx64"\s*:\s*"789"/, '28.2: fixed64 is a JSON string' );
    like( $json, qr/"sf64"\s*:\s*"-5"/,  '28.2: sfixed64 is a JSON string' );

    my $got = from_json($json);
    is( $got->{i64}, '123', '28.2: int64 round-trips to the string value' );
}

# --- 28.3: enum as name by default; enums_as_ints emits the number ------

{
    my $enum = Protobuf::Schema::Enum->new(
        name      => 'Color',
        full_name => 'pkg.Color',
        values    => [
            { name => 'RED',   number => 0 },
            { name => 'GREEN', number => 1 },
            { name => 'BLUE',  number => 2 },
        ],
    );
    my $message = Protobuf::Schema::Message->new(
        name      => 'Painted',
        full_name => 'pkg.Painted',
        fields    => [
            Protobuf::Schema::Field->new(
                name      => 'color',
                number    => 1,
                type      => 'enum',
                type_name => 'pkg.Color',
            ),
        ],
    );
    my $codec = codec_for( messages => [$message], enums => [$enum] );

    my $json = $codec->encode_json( 'pkg.Painted', { color => 2 } );
    is( from_json($json)->{color}, 'BLUE',
        '28.3: enum emits its value NAME by default' );

    # An unknown enumerator number has no name; it falls back to the integer.
    my $json_unknown = $codec->encode_json( 'pkg.Painted', { color => 99 } );
    is( from_json($json_unknown)->{color}, 99,
        '28.3: unknown enum number falls back to the integer' );

    my $json_ints =
        $codec->encode_json( 'pkg.Painted', { color => 2 },
        enums_as_ints => 1 );
    is( from_json($json_ints)->{color}, 2,
        '28.3: enums_as_ints emits the numeric value' );
}

# --- 28.4: camelCase field names by default; preserve_field_names -------

{
    my $message = Protobuf::Schema::Message->new(
        name      => 'Named',
        full_name => 'pkg.Named',
        fields    => [
            scalar_field( 'user_id',   1, 'int32' ),
            scalar_field( 'data_blob', 2, 'string' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my $json = $codec->encode_json(
        'pkg.Named',
        { user_id => 5, data_blob => 'x' },
    );
    my $got = from_json($json);
    ok( exists $got->{userId},   '28.4: snake_case field becomes camelCase' );
    ok( exists $got->{dataBlob}, '28.4: data_blob becomes dataBlob' );
    ok( !exists $got->{user_id}, '28.4: proto name absent by default' );

    my $json_preserve = $codec->encode_json(
        'pkg.Named',
        { user_id => 5, data_blob => 'x' },
        preserve_field_names => 1,
    );
    my $got_preserve = from_json($json_preserve);
    ok( exists $got_preserve->{user_id},
        '28.4: preserve_field_names keeps the proto name' );
    ok( !exists $got_preserve->{userId},
        '28.4: preserve_field_names omits the camelCase name' );
}

# --- 28.5: bytes emit as base64 -----------------------------------------

{
    my $message = Protobuf::Schema::Message->new(
        name      => 'Blob',
        full_name => 'pkg.Blob',
        fields    => [ scalar_field( 'data', 1, 'bytes' ) ],
    );
    my $codec = codec_for( messages => [$message] );

    # "hello" in base64 is "aGVsbG8=".
    my $json = $codec->encode_json( 'pkg.Blob', { data => 'hello' } );
    is( from_json($json)->{data}, 'aGVsbG8=',
        '28.5: bytes serialize as base64' );
}

# --- 28.6: default-valued singular omitted; emit_defaults includes it ----

{
    my $message = Protobuf::Schema::Message->new(
        name      => 'Defaulted',
        full_name => 'pkg.Defaulted',
        fields    => [
            scalar_field( 'n', 1, 'int32' ),
            scalar_field( 's', 2, 'string' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my $json = $codec->encode_json( 'pkg.Defaulted', { n => 0, s => '' } );
    my $got  = from_json($json);
    ok( !exists $got->{n}, '28.6: default int32 omitted by default' );
    ok( !exists $got->{s}, '28.6: default string omitted by default' );

    my $json_defaults = $codec->encode_json(
        'pkg.Defaulted', { n => 0, s => '' }, emit_defaults => 1 );
    my $got_defaults = from_json($json_defaults);
    is( $got_defaults->{n}, 0,  '28.6: emit_defaults includes default int' );
    is( $got_defaults->{s}, '', '28.6: emit_defaults includes default string' );
}

# --- 28.7a: WKT fields use their special forms (T-json-6 encode) ---------

{
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    my $codec = Protobuf::Codec->new( schema => $schema );

    # Timestamp -> RFC3339 string (special form, not a { seconds, nanos } object).
    my $ts_json = $codec->encode_json(
        'google.protobuf.Timestamp',
        { seconds => 1_700_000_000, nanos => 789_000_000 },
    );
    is( $ts_json, '"2023-11-14T22:13:20.789Z"',
        '28.7: Timestamp encodes via its WKT JSON form' );

    # Int32Value -> the bare inner value, not { "value": 42 }.
    my $w_json =
        $codec->encode_json( 'google.protobuf.Int32Value', { value => 42 } );
    is( $w_json, '42', '28.7: wrapper encodes as its bare inner value' );
}

# --- 28.7b: a WKT-typed field on a normal message delegates -------------

{
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    my $outer = Protobuf::Schema::File->new(
        name     => 'outer.proto',
        package  => 'pkg',
        messages => [
            Protobuf::Schema::Message->new(
                name      => 'Event',
                full_name => 'pkg.Event',
                fields    => [
                    Protobuf::Schema::Field->new(
                        name      => 'at',
                        number    => 1,
                        type      => 'message',
                        type_name => 'google.protobuf.Timestamp',
                    ),
                ],
            ),
        ],
    );
    $schema->add_file($outer);
    $schema->resolve;
    my $codec = Protobuf::Codec->new( schema => $schema );

    my $json = $codec->encode_json(
        'pkg.Event',
        { at => { seconds => 1_700_000_000, nanos => 789_000_000 } },
    );
    is( from_json($json)->{at}, '2023-11-14T22:13:20.789Z',
        '28.7: a Timestamp-typed field delegates to its WKT JSON form' );
}

# --- 28.7c: maps emit as JSON objects -----------------------------------

{
    # map<string,int32> attrs = 1;  modeled as repeated synthetic MapEntry.
    my $entry = Protobuf::Schema::Message->new(
        name         => 'AttrsEntry',
        full_name    => 'pkg.Mapped.AttrsEntry',
        is_map_entry => 1,
        fields       => [
            scalar_field( 'key',   1, 'string' ),
            scalar_field( 'value', 2, 'int32' ),
        ],
    );
    my $message = Protobuf::Schema::Message->new(
        name      => 'Mapped',
        full_name => 'pkg.Mapped',
        fields    => [
            Protobuf::Schema::Field->new(
                name      => 'attrs',
                number    => 1,
                type      => 'message',
                label     => 'repeated',
                type_name => 'pkg.Mapped.AttrsEntry',
                map_entry => 'pkg.Mapped.AttrsEntry',
            ),
        ],
    );
    my $codec = codec_for( messages => [ $message, $entry ] );

    my $json = $codec->encode_json(
        'pkg.Mapped',
        { attrs => { a => 1, b => 2 } },
    );
    my $got = from_json($json);
    is_deeply( $got->{attrs}, { a => 1, b => 2 },
        '28.7: map encodes as a JSON object keyed by map key' );
}

# --- 28.7d: a bool map key emits as "true"/"false", not "1"/"0" ----------
{
    # map<bool,int32> flags = 1;  proto3 JSON spells bool keys true/false.
    my $entry = Protobuf::Schema::Message->new(
        name         => 'FlagsEntry',
        full_name    => 'pkg.BoolMapped.FlagsEntry',
        is_map_entry => 1,
        fields       => [
            scalar_field( 'key',   1, 'bool' ),
            scalar_field( 'value', 2, 'int32' ),
        ],
    );
    my $message = Protobuf::Schema::Message->new(
        name      => 'BoolMapped',
        full_name => 'pkg.BoolMapped',
        fields    => [
            Protobuf::Schema::Field->new(
                name      => 'flags',
                number    => 1,
                type      => 'message',
                label     => 'repeated',
                type_name => 'pkg.BoolMapped.FlagsEntry',
                map_entry => 'pkg.BoolMapped.FlagsEntry',
            ),
        ],
    );
    my $codec = codec_for( messages => [ $message, $entry ] );

    my $json = $codec->encode_json( 'pkg.BoolMapped', { flags => { 1 => 7, 0 => 9 } } );
    my $got  = from_json($json);
    is_deeply( $got->{flags}, { 'true' => 7, 'false' => 9 },
        '28.7d: bool map keys emit as "true"/"false"' );
}

done_testing;
