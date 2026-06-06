# ABOUTME: Regression tests for proto3-JSON conformance fixes — Timestamp zone
# offsets + range bounds, Duration range bounds, wrapper bool/bytes coercion,
# and bool map keys (§4.8/§4.9, matches protoc behavior).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use JSON::PP ();
use MIME::Base64 ();

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Codec;
use Protobuf::WKT;
use Protobuf::WKT::Timestamp;
use Protobuf::WKT::Duration;
use Protobuf::WKT::Wrappers;

# --- Timestamp: RFC3339 numeric zone offsets normalize to UTC -----------

{
    # "1970-01-01T08:00:01+08:00" is 1 second after the epoch in UTC.
    my $pos = Protobuf::WKT::Timestamp->from_json_value('1970-01-01T08:00:01+08:00');
    is( $pos->{seconds}, 1, 'positive offset normalizes to UTC seconds' );
    is( $pos->{nanos},   0, 'positive offset nanos' );

    # "1969-12-31T16:00:01-08:00" is also 1 second after the epoch in UTC.
    my $neg = Protobuf::WKT::Timestamp->from_json_value('1969-12-31T16:00:01-08:00');
    is( $neg->{seconds}, 1, 'negative offset normalizes to UTC seconds' );
    is( $neg->{nanos},   0, 'negative offset nanos' );

    # An offset with fractional seconds keeps the fraction.
    my $frac = Protobuf::WKT::Timestamp->from_json_value('1970-01-01T08:00:01.5+08:00');
    is( $frac->{seconds}, 1,           'offset + fraction seconds' );
    is( $frac->{nanos},   500_000_000, 'offset + fraction nanos' );

    # '+00:00' is equivalent to 'Z'.
    my $zero = Protobuf::WKT::Timestamp->from_json_value('1970-01-01T00:00:01+00:00');
    is( $zero->{seconds}, 1, '+00:00 equals Z' );
}

# --- Timestamp: range bounds (years 0001..9999) -------------------------

{
    # Smallest in-range instant: 0001-01-01T00:00:00Z = -62135596800.
    my $min = Protobuf::WKT::Timestamp->from_json_value('0001-01-01T00:00:00Z');
    is( $min->{seconds}, -62_135_596_800, 'minimum in-range Timestamp accepted' );

    # Largest in-range instant: 9999-12-31T23:59:59Z = 253402300799.
    my $max = Protobuf::WKT::Timestamp->from_json_value('9999-12-31T23:59:59Z');
    is( $max->{seconds}, 253_402_300_799, 'maximum in-range Timestamp accepted' );

    # Year 0000 is out of range and must be rejected on JSON input.
    eval { Protobuf::WKT::Timestamp->from_json_value('0000-01-01T00:00:00Z'); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'year 0000 Timestamp rejected' );

    # Below the minimum seconds is rejected on output (protobuf -> JSON).
    eval { Protobuf::WKT::Timestamp->to_json_value( { seconds => -62_135_596_801, nanos => 0 } ); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'too-small Timestamp rejected on output' );

    # Above the maximum seconds is rejected on output.
    eval { Protobuf::WKT::Timestamp->to_json_value( { seconds => 253_402_300_800, nanos => 0 } ); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'too-large Timestamp rejected on output' );

    # In-range bounds still serialize.
    is(
        Protobuf::WKT::Timestamp->to_json_value( { seconds => -62_135_596_800, nanos => 0 } ),
        '0001-01-01T00:00:00Z', 'minimum Timestamp serializes'
    );
}

# --- Duration: range bounds (+/- 315576000000 seconds) ------------------

{
    # Just outside the lower bound is rejected.
    eval { Protobuf::WKT::Duration->from_json_value('-315576000001s'); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'too-small Duration rejected' );

    # Just outside the upper bound is rejected.
    eval { Protobuf::WKT::Duration->from_json_value('315576000001s'); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'too-large Duration rejected' );

    # The bounds themselves are accepted.
    my $lo = Protobuf::WKT::Duration->from_json_value('-315576000000s');
    is( $lo->{seconds}, -315_576_000_000, 'lower-bound Duration accepted' );
    my $hi = Protobuf::WKT::Duration->from_json_value('315576000000s');
    is( $hi->{seconds}, 315_576_000_000, 'upper-bound Duration accepted' );

    # An out-of-range Duration arriving from the binary form must also be
    # rejected on JSON serialization (protobuf-input -> JSON-output).
    eval { Protobuf::WKT::Duration->to_json_value( { seconds => 315_576_000_001, nanos => 0 } ); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'too-large Duration rejected on output' );
    eval { Protobuf::WKT::Duration->to_json_value( { seconds => -315_576_000_001, nanos => 0 } ); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'too-small Duration rejected on output' );

    # In-range bounds still serialize.
    is(
        Protobuf::WKT::Duration->to_json_value( { seconds => 315_576_000_000, nanos => 0 } ),
        '315576000000s', 'upper-bound Duration serializes'
    );
}

# --- Wrappers: bool and bytes coercion ----------------------------------

{
    # BoolValue JSON form is a JSON true/false; the codec form is a native 1/0.
    my $true = Protobuf::WKT::Wrappers->from_json_value(
        'google.protobuf.BoolValue', JSON::PP::true );
    is( $true->{value}, 1, 'BoolValue true -> 1' );
    ok( !ref $true->{value}, 'BoolValue codec form is a plain scalar, not a JSON::PP::Boolean' );

    my $false = Protobuf::WKT::Wrappers->from_json_value(
        'google.protobuf.BoolValue', JSON::PP::false );
    is( $false->{value}, 0, 'BoolValue false -> 0' );

    # to_json_value emits a JSON boolean.
    my $out = Protobuf::WKT::Wrappers->to_json_value(
        'google.protobuf.BoolValue', { value => 1 } );
    isa_ok( $out, 'JSON::PP::Boolean', 'BoolValue 1 -> JSON boolean' );
    ok( $out, 'BoolValue 1 is truthy' );

    # BytesValue JSON form is base64; the codec form is raw bytes.
    my $raw = "\001\002";
    my $b64 = MIME::Base64::encode_base64( $raw, '' );
    my $dec = Protobuf::WKT::Wrappers->from_json_value(
        'google.protobuf.BytesValue', $b64 );
    is( $dec->{value}, $raw, 'BytesValue base64 -> raw bytes' );

    my $enc = Protobuf::WKT::Wrappers->to_json_value(
        'google.protobuf.BytesValue', { value => $raw } );
    is( $enc, $b64, 'BytesValue raw bytes -> base64' );

    # Non-bool, non-bytes wrappers still pass through unchanged.
    is(
        Protobuf::WKT::Wrappers->to_json_value(
            'google.protobuf.Int32Value', { value => 42 } ),
        42, 'Int32Value still passes through'
    );
    is_deeply(
        Protobuf::WKT::Wrappers->from_json_value(
            'google.protobuf.StringValue', 'hi' ),
        { value => 'hi' }, 'StringValue still passes through'
    );
}

# --- End-to-end: wrapper round-trip through the codec -------------------

{
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    my $codec = Protobuf::Codec->new( schema => $schema );

    # A BoolValue decoded from JSON must binary-encode without choking on a
    # JSON::PP::Boolean (the conformance OptionalBoolWrapper failure).
    my $values = $codec->decode_json( 'google.protobuf.BoolValue', 'false' );
    is( $values->{value}, 0, 'BoolValue false decodes to 0 through the codec' );
    my $bytes = $codec->encode( 'google.protobuf.BoolValue', $values );
    is( $bytes, '', 'BoolValue 0 encodes to empty (default-omitted) bytes' );

    my $tvals = $codec->decode_json( 'google.protobuf.BoolValue', 'true' );
    is( $tvals->{value}, 1, 'BoolValue true decodes to 1 through the codec' );
    my $tbytes = $codec->encode( 'google.protobuf.BoolValue', $tvals );
    is( $tbytes, "\x08\x01", 'BoolValue 1 encodes to field 1 = 1' );

    # A BytesValue decoded from base64 JSON must store raw bytes for the binary
    # form (the RepeatedBytesWrapper failure).
    my $bvals = $codec->decode_json( 'google.protobuf.BytesValue', '"AQI="' );
    is( $bvals->{value}, "\001\002", 'BytesValue base64 decodes to raw bytes through codec' );
}

# --- Bool map keys: "true"/"false" coerce to the bool key type ----------

{
    require Protobuf::Schema::File;
    require Protobuf::Schema::Message;
    require Protobuf::Schema::Field;

    # A map<bool, bool> field on a small test message.
    my $entry = Protobuf::Schema::Message->new(
        name         => 'BoolBoolEntry',
        full_name    => 'test.M.BoolBoolEntry',
        is_map_entry => 1,
        fields       => [
            Protobuf::Schema::Field->new( name => 'key',   number => 1, type => 'bool' ),
            Protobuf::Schema::Field->new( name => 'value', number => 2, type => 'bool' ),
        ],
    );
    my $msg = Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'test.M',
        fields    => [
            Protobuf::Schema::Field->new(
                name      => 'map_bool_bool',
                number    => 1,
                type      => 'message',
                label     => 'repeated',
                type_name => 'test.M.BoolBoolEntry',
                map_entry => 'test.M.BoolBoolEntry',
            ),
        ],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'test.proto', package => 'test', messages => [ $msg, $entry ],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;

    my $codec = Protobuf::Codec->new( schema => $schema );
    my $vals  = $codec->decode_json( 'test.M',
        '{"mapBoolBool": {"true": true, "false": false}}' );

    my %got = %{ $vals->{map_bool_bool} };
    ok( exists $got{1}, 'JSON bool key "true" coerces to map key 1' );
    ok( exists $got{0}, 'JSON bool key "false" coerces to map key 0' );
    is( $got{1}, 1, '"true" value true -> 1' );
    is( $got{0}, 0, '"false" value false -> 0' );
}

done_testing;
