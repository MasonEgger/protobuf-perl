# ABOUTME: WKT Timestamp/Duration tests — binary + JSON RFC3339/fractional
# round-trips, from_epoch, and malformed-string -> JSON::WKT (§4.8, T-wkt-1/2).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Codec;
use Proto3::WKT;
use Proto3::WKT::Timestamp;
use Proto3::WKT::Duration;

# A codec over the registered WKT schemas, for binary round-trips.
my sub wkt_codec {
    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);
    return Proto3::Codec->new( schema => $schema );
}

# --- 26.2: from_epoch convenience constructor ---------------------------

{
    my $ts = Proto3::WKT::Timestamp->from_epoch(1_700_000_000);
    is( $ts->{seconds}, 1_700_000_000, 'from_epoch sets seconds' );
    is( $ts->{nanos},   0,             'from_epoch defaults nanos to 0' );

    my $ts2 = Proto3::WKT::Timestamp->from_epoch( 1_700_000_000, 500_000_000 );
    is( $ts2->{nanos}, 500_000_000, 'from_epoch accepts explicit nanos' );
}

# --- 26.1: Timestamp binary round-trip (seconds/nanos) ------------------

{
    my $codec = wkt_codec();
    my $value = { seconds => 1_700_000_000, nanos => 789_000_000 };
    my $bytes = $codec->encode( 'google.protobuf.Timestamp', $value );
    my $back  = $codec->decode( 'google.protobuf.Timestamp', $bytes );
    is( $back->{seconds}, 1_700_000_000, 'binary round-trip seconds' );
    is( $back->{nanos},   789_000_000,   'binary round-trip nanos' );
}

# --- 26.1: Timestamp JSON RFC3339 round-trip ----------------------------

{
    my $value = { seconds => 1_700_000_000, nanos => 789_000_000 };
    my $json  = Proto3::WKT::Timestamp->to_json_value($value);
    is( $json, '2023-11-14T22:13:20.789Z', 'Timestamp -> RFC3339 with millis' );

    my $back = Proto3::WKT::Timestamp->from_json_value($json);
    is( $back->{seconds}, 1_700_000_000, 'RFC3339 -> seconds' );
    is( $back->{nanos},   789_000_000,   'RFC3339 -> nanos' );

    # Whole-second timestamp has no fractional part.
    my $whole = Proto3::WKT::Timestamp->to_json_value(
        { seconds => 1_700_000_000, nanos => 0 } );
    is( $whole, '2023-11-14T22:13:20Z', 'whole second has no fraction' );
    my $rt = Proto3::WKT::Timestamp->from_json_value($whole);
    is( $rt->{seconds}, 1_700_000_000, 'whole-second RFC3339 -> seconds' );
    is( $rt->{nanos},   0,             'whole-second RFC3339 -> nanos 0' );
}

# --- 26.3: Duration fractional + negative round-trip --------------------

{
    my $codec = wkt_codec();
    my $value = { seconds => 1, nanos => 500_000_000 };
    my $bytes = $codec->encode( 'google.protobuf.Duration', $value );
    my $back  = $codec->decode( 'google.protobuf.Duration', $bytes );
    is( $back->{seconds}, 1,           'Duration binary round-trip seconds' );
    is( $back->{nanos},   500_000_000, 'Duration binary round-trip nanos' );
}

{
    my $json = Proto3::WKT::Duration->to_json_value(
        { seconds => 1, nanos => 500_000_000 } );
    is( $json, '1.500s', 'Duration 1s500ms -> "1.500s"' );

    my $back = Proto3::WKT::Duration->from_json_value('1.500s');
    is( $back->{seconds}, 1,           '"1.500s" -> seconds 1' );
    is( $back->{nanos},   500_000_000, '"1.500s" -> nanos 500e6' );

    # Whole-second duration.
    is(
        Proto3::WKT::Duration->to_json_value( { seconds => 60, nanos => 0 } ),
        '60s', 'whole-second Duration -> "60s"'
    );
    my $whole = Proto3::WKT::Duration->from_json_value('60s');
    is( $whole->{seconds}, 60, '"60s" -> seconds 60' );
    is( $whole->{nanos},   0,  '"60s" -> nanos 0' );
}

# Negative durations: both seconds and nanos carry the sign (proto3 spec).

{
    my $json = Proto3::WKT::Duration->to_json_value(
        { seconds => -1, nanos => -500_000_000 } );
    is( $json, '-1.500s', 'negative Duration -> "-1.500s"' );

    my $back = Proto3::WKT::Duration->from_json_value('-1.500s');
    is( $back->{seconds}, -1,           '"-1.500s" -> seconds -1' );
    is( $back->{nanos},   -500_000_000, '"-1.500s" -> nanos -500e6' );

    # Sub-second negative: seconds 0, nanos negative.
    my $sub = Proto3::WKT::Duration->from_json_value('-0.250s');
    is( $sub->{seconds}, 0,            '"-0.250s" -> seconds 0' );
    is( $sub->{nanos},   -250_000_000, '"-0.250s" -> nanos -250e6' );
    is(
        Proto3::WKT::Duration->to_json_value( { seconds => 0, nanos => -250_000_000 } ),
        '-0.250s', 'negative sub-second Duration -> "-0.250s"'
    );
}

# --- 26.4: malformed RFC3339 / duration -> JSON::WKT --------------------

{
    my $err = eval { Proto3::WKT::Timestamp->from_json_value('not-a-timestamp'); 1 };
    ok( !$err, 'malformed RFC3339 dies' );
    isa_ok( $@, 'Proto3::Exception::JSON::WKT', 'malformed RFC3339 exception' );
}

{
    eval { Proto3::WKT::Duration->from_json_value('1.5'); 1 };
    isa_ok( $@, 'Proto3::Exception::JSON::WKT',
        'duration without trailing s -> JSON::WKT' );
}

{
    eval { Proto3::WKT::Duration->from_json_value('abcs'); 1 };
    isa_ok( $@, 'Proto3::Exception::JSON::WKT',
        'non-numeric duration -> JSON::WKT' );
}

# --- facade registers both WKT messages ---------------------------------

{
    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);
    ok( $schema->message('google.protobuf.Timestamp'),
        'facade registers Timestamp' );
    ok( $schema->message('google.protobuf.Duration'),
        'facade registers Duration' );
}

done_testing;
