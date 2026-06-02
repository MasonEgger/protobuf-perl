# ABOUTME: Proto3::JSON decode tests (Step 29) — lenient proto3 JSON input:
# scalar round-trip, 64-bit from string AND number, enum from name AND number,
# camelCase + snake_case keys, unknown-field skip/reject, error types, WKT
# delegation (spec §4.9, T-json-1/2/3).
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
use Proto3::WKT;

# --- helpers ------------------------------------------------------------

# Build a codec over a one-file schema holding the given Schema elements.
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

# --- 29.1: all scalar types round-trip (T-json-1) -----------------------

{
    my $message = Proto3::Schema::Message->new(
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
            scalar_field( 'by',  9, 'bytes' ),
            scalar_field( 'i64', 10, 'int64' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my %original = (
        i32 => 42,
        u32 => 7,
        s32 => -3,
        f32 => 100,
        b   => 1,
        fl  => 1.5,
        dbl => 2.25,
        str => 'hi',
        by  => 'hello',
        i64 => 123,
    );

    my $json    = $codec->encode_json( 'pkg.Scalars', \%original );
    my $decoded = $codec->decode_json( 'pkg.Scalars', $json );

    is( $decoded->{i32}, 42,      '29.1: int32 round-trips' );
    is( $decoded->{u32}, 7,       '29.1: uint32 round-trips' );
    is( $decoded->{s32}, -3,      '29.1: sint32 round-trips' );
    is( $decoded->{f32}, 100,     '29.1: fixed32 round-trips' );
    is( $decoded->{b},   1,       '29.1: bool round-trips' );
    is( $decoded->{fl},  1.5,     '29.1: float round-trips' );
    is( $decoded->{dbl}, 2.25,    '29.1: double round-trips' );
    is( $decoded->{str}, 'hi',    '29.1: string round-trips' );
    is( $decoded->{by},  'hello', '29.1: bytes round-trip from base64' );
    is( $decoded->{i64}, 123,     '29.1: int64 round-trips' );
}

# --- 29.2: int64 decodes from BOTH a string AND a number (T-json-2 dec) --

{
    my $message = Proto3::Schema::Message->new(
        name      => 'Wide',
        full_name => 'pkg.Wide',
        fields    => [ scalar_field( 'i64', 1, 'int64' ) ],
    );
    my $codec = codec_for( messages => [$message] );

    my $from_string = $codec->decode_json( 'pkg.Wide', '{"i64":"123"}' );
    is( $from_string->{i64}, 123, '29.2: int64 decodes from a JSON string' );

    my $from_number = $codec->decode_json( 'pkg.Wide', '{"i64":123}' );
    is( $from_number->{i64}, 123, '29.2: int64 decodes from a JSON number' );
}

# --- 29.3: enum decodes from BOTH a name AND a number (T-json-3 dec) -----

{
    my $enum = Proto3::Schema::Enum->new(
        name      => 'Color',
        full_name => 'pkg.Color',
        values    => [
            { name => 'RED',   number => 0 },
            { name => 'GREEN', number => 1 },
            { name => 'BLUE',  number => 2 },
        ],
    );
    my $message = Proto3::Schema::Message->new(
        name      => 'Painted',
        full_name => 'pkg.Painted',
        fields    => [
            Proto3::Schema::Field->new(
                name => 'color', number => 1, type => 'enum',
                type_name => 'pkg.Color',
            ),
        ],
    );
    my $codec = codec_for( messages => [$message], enums => [$enum] );

    my $from_name = $codec->decode_json( 'pkg.Painted', '{"color":"BLUE"}' );
    is( $from_name->{color}, 2, '29.3: enum decodes from its symbolic name' );

    my $from_number = $codec->decode_json( 'pkg.Painted', '{"color":2}' );
    is( $from_number->{color}, 2, '29.3: enum decodes from its number' );

    # An unknown enum number is preserved as the integer.
    my $unknown = $codec->decode_json( 'pkg.Painted', '{"color":99}' );
    is( $unknown->{color}, 99, '29.3: unknown enum number preserved' );
}

# --- 29.4: accept BOTH camelCase AND snake_case field names --------------

{
    my $message = Proto3::Schema::Message->new(
        name      => 'Named',
        full_name => 'pkg.Named',
        fields    => [
            scalar_field( 'user_id',   1, 'int32' ),
            scalar_field( 'data_blob', 2, 'string' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my $camel =
        $codec->decode_json( 'pkg.Named', '{"userId":5,"dataBlob":"x"}' );
    is( $camel->{user_id},   5,   '29.4: camelCase key decodes' );
    is( $camel->{data_blob}, 'x', '29.4: camelCase data_blob decodes' );

    my $snake =
        $codec->decode_json( 'pkg.Named', '{"user_id":9,"data_blob":"y"}' );
    is( $snake->{user_id},   9,   '29.4: snake_case key decodes' );
    is( $snake->{data_blob}, 'y', '29.4: snake_case data_blob decodes' );
}

# --- 29.5: unknown field skipped by default; reject_unknown_fields raises -

{
    my $message = Proto3::Schema::Message->new(
        name      => 'Small',
        full_name => 'pkg.Small',
        fields    => [ scalar_field( 'n', 1, 'int32' ) ],
    );
    my $codec = codec_for( messages => [$message] );

    my $skipped =
        $codec->decode_json( 'pkg.Small', '{"n":1,"mystery":42}' );
    is( $skipped->{n}, 1, '29.5: known field decodes alongside unknown' );
    ok( !exists $skipped->{mystery},
        '29.5: unknown field silently skipped by default' );

    my $err;
    eval {
        $codec->decode_json(
            'pkg.Small', '{"n":1,"mystery":42}',
            reject_unknown_fields => 1,
        );
        1;
    } or $err = $@;
    ok( $err, '29.5: reject_unknown_fields raises on an unknown field' );
}

# --- 29.6: error types ---------------------------------------------------

{
    my $message = Proto3::Schema::Message->new(
        name      => 'Small',
        full_name => 'pkg.Small',
        fields    => [ scalar_field( 'n', 1, 'int32' ) ],
    );
    my $codec = codec_for( messages => [$message] );

    # Invalid JSON text -> JSON::Parse.
    my $parse_err;
    eval { $codec->decode_json( 'pkg.Small', '{not valid json' ); 1 }
        or $parse_err = $@;
    isa_ok( $parse_err, 'Proto3::Exception::JSON::Parse',
        '29.6: malformed JSON raises JSON::Parse' );

    # A string in an int field -> TypeMismatch.
    my $tm_err;
    eval { $codec->decode_json( 'pkg.Small', '{"n":"notanumber"}' ); 1 }
        or $tm_err = $@;
    isa_ok( $tm_err, 'Proto3::Exception::Codec::TypeMismatch',
        '29.6: string in an int field raises TypeMismatch' );
}

# --- 29.6b: malformed WKT string form -> JSON::WKT ----------------------

{
    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);
    my $codec = Proto3::Codec->new( schema => $schema );

    my $wkt_err;
    eval {
        $codec->decode_json( 'google.protobuf.Timestamp', '"not-a-timestamp"' );
        1;
    } or $wkt_err = $@;
    isa_ok( $wkt_err, 'Proto3::Exception::JSON::WKT',
        '29.6: malformed RFC3339 raises JSON::WKT' );
}

# --- 29.8: WKT from_json_value delegation round-trips -------------------

{
    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);
    my $codec = Proto3::Codec->new( schema => $schema );

    # Timestamp from its RFC3339 special form -> { seconds, nanos }.
    my $ts = $codec->decode_json(
        'google.protobuf.Timestamp', '"2023-11-14T22:13:20.789Z"' );
    is( $ts->{seconds}, 1_700_000_000, '29.8: Timestamp seconds decode' );
    is( $ts->{nanos},   789_000_000,   '29.8: Timestamp nanos decode' );

    # Int32Value from its bare value -> { value => 42 }.
    my $w =
        $codec->decode_json( 'google.protobuf.Int32Value', '42' );
    is( $w->{value}, 42, '29.8: wrapper decodes from its bare inner value' );
}

# --- 29.8b: a WKT-typed field on a normal message delegates -------------

{
    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);
    my $outer = Proto3::Schema::File->new(
        name     => 'outer.proto',
        package  => 'pkg',
        messages => [
            Proto3::Schema::Message->new(
                name      => 'Event',
                full_name => 'pkg.Event',
                fields    => [
                    Proto3::Schema::Field->new(
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
    my $codec = Proto3::Codec->new( schema => $schema );

    my $decoded = $codec->decode_json(
        'pkg.Event', '{"at":"2023-11-14T22:13:20.789Z"}' );
    is( $decoded->{at}{seconds}, 1_700_000_000,
        '29.8: a Timestamp-typed field delegates to its WKT JSON decode' );
}

# --- 29.8c: maps decode from JSON objects -------------------------------

{
    my $entry = Proto3::Schema::Message->new(
        name         => 'AttrsEntry',
        full_name    => 'pkg.Mapped.AttrsEntry',
        is_map_entry => 1,
        fields       => [
            scalar_field( 'key',   1, 'string' ),
            scalar_field( 'value', 2, 'int32' ),
        ],
    );
    my $message = Proto3::Schema::Message->new(
        name      => 'Mapped',
        full_name => 'pkg.Mapped',
        fields    => [
            Proto3::Schema::Field->new(
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

    my $decoded =
        $codec->decode_json( 'pkg.Mapped', '{"attrs":{"a":1,"b":2}}' );
    is_deeply( $decoded->{attrs}, { a => 1, b => 2 },
        '29.8: map decodes from a JSON object' );
}

# --- 29.8d: repeated fields decode from JSON arrays ---------------------

{
    my $message = Proto3::Schema::Message->new(
        name      => 'Listy',
        full_name => 'pkg.Listy',
        fields    => [
            scalar_field( 'nums', 1, 'int32', label => 'repeated' ),
        ],
    );
    my $codec = codec_for( messages => [$message] );

    my $decoded = $codec->decode_json( 'pkg.Listy', '{"nums":[1,2,3]}' );
    is_deeply( $decoded->{nums}, [ 1, 2, 3 ],
        '29.8: repeated field decodes from a JSON array' );
}

done_testing;
