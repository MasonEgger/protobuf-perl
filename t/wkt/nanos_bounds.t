# ABOUTME: WKT Timestamp/Duration JSON output MUST reject an out-of-range nanos
# field (Timestamp 0..1e9-1; Duration |nanos|<=1e9-1 with sign matching seconds).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::WKT::Timestamp;
use Proto3::WKT::Duration;

# --- Timestamp: nanos must be 0 .. 999999999 ----------------------------

# A valid in-range nanos still serializes.
{
    my $json = Proto3::WKT::Timestamp->to_json_value(
        { seconds => 10000, nanos => 500_000_000 } );
    like( $json, qr/\.500Z\z/, 'Timestamp with valid nanos serializes' );
}

# A negative nanos (conformance TimestampProtoNegativeNanos) is rejected.
{
    my $ok = eval {
        Proto3::WKT::Timestamp->to_json_value(
            { seconds => 5000, nanos => -1 } );
        1;
    };
    ok( !$ok, 'Timestamp negative nanos is rejected' );
    isa_ok( $@, 'Proto3::Exception::JSON::WKT', 'throws JSON::WKT' );
}

# A nanos above 999999999 (conformance TimestampProtoNanoTooLarge) is rejected.
{
    my $ok = eval {
        Proto3::WKT::Timestamp->to_json_value(
            { seconds => 5000, nanos => 1_000_000_000 } );
        1;
    };
    ok( !$ok, 'Timestamp nanos too large is rejected' );
    isa_ok( $@, 'Proto3::Exception::JSON::WKT', 'throws JSON::WKT' );
}

# --- Duration: |nanos| <= 999999999 and sign matches seconds ------------

# A valid same-sign nanos still serializes.
{
    my $json = Proto3::WKT::Duration->to_json_value(
        { seconds => 1, nanos => 500_000_000 } );
    is( $json, '1.500s', 'Duration with valid nanos serializes' );
}

# nanos magnitude too large (conformance DurationProtoNanosTooLarge /
# DurationProtoNanosTooSmall).
{
    for my $case (
        [ { seconds => 1,  nanos => 1_000_000_000 },  'nanos too large' ],
        [ { seconds => -1, nanos => -1_000_000_000 }, 'nanos too small' ],
      )
    {
        my ( $value, $label ) = @$case;
        my $ok = eval { Proto3::WKT::Duration->to_json_value($value); 1 };
        ok( !$ok, "Duration $label is rejected" );
        isa_ok( $@, 'Proto3::Exception::JSON::WKT', "$label throws JSON::WKT" );
    }
}

# nanos sign disagrees with seconds sign (conformance DurationProtoNanosWrongSign
# / DurationProtoNanosWrongSignNegativeSecs).
{
    for my $case (
        [ { seconds => 1,  nanos => -1 }, 'positive secs, negative nanos' ],
        [ { seconds => -1, nanos => 1 },  'negative secs, positive nanos' ],
      )
    {
        my ( $value, $label ) = @$case;
        my $ok = eval { Proto3::WKT::Duration->to_json_value($value); 1 };
        ok( !$ok, "Duration $label is rejected" );
        isa_ok( $@, 'Proto3::Exception::JSON::WKT', "$label throws JSON::WKT" );
    }
}

# seconds == 0 allows nanos of either sign (no sign-mismatch error).
{
    my $json = Proto3::WKT::Duration->to_json_value(
        { seconds => 0, nanos => -500_000_000 } );
    is( $json, '-0.500s', 'Duration with zero seconds allows negative nanos' );
}

done_testing;
