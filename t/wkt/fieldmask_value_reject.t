# ABOUTME: WKT regression tests — FieldMask paths that do not round-trip to
# camelCase are rejected on serialize, invalid characters on parse; and a
# google.protobuf.Value cannot hold NaN/Inf in JSON.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::WKT::FieldMask;
use Proto3::WKT::Struct;

# --- FieldMask serialize: paths that do not round-trip are rejected ----------
{
    # FieldMaskPathsDontRoundTrip: a path already carrying an uppercase letter.
    my $ok1 = eval {
        Proto3::WKT::FieldMask->to_json_value( { paths => ['fooBar'] } ); 1;
    };
    ok( !$ok1, 'FieldMask serialize rejects an uppercase path (PathsDontRoundTrip)' );

    # FieldMaskNumbersDontRoundTrip: a digit segment after an underscore.
    my $ok2 = eval {
        Proto3::WKT::FieldMask->to_json_value( { paths => ['foo_3_bar'] } ); 1;
    };
    ok( !$ok2, 'FieldMask serialize rejects a numbered path (NumbersDontRoundTrip)' );

    # FieldMaskTooManyUnderscore: a doubled underscore.
    my $ok3 = eval {
        Proto3::WKT::FieldMask->to_json_value( { paths => ['foo__bar'] } ); 1;
    };
    ok( !$ok3, 'FieldMask serialize rejects a doubled underscore (TooManyUnderscore)' );

    isa_ok( $@, 'Proto3::Exception::JSON::WKT',
        'serialize rejection raises a JSON::WKT exception' );

    # A clean snake_case path still round-trips.
    is( Proto3::WKT::FieldMask->to_json_value( { paths => [ 'foo_bar', 'a.b' ] } ),
        'fooBar,a.b', 'a well-formed FieldMask serializes to camelCase' );
}

# --- FieldMask parse: an invalid character is rejected -----------------------
{
    # FieldMaskInvalidCharacter: a camelCase input path containing an underscore.
    my $ok = eval {
        Proto3::WKT::FieldMask->from_json_value('foo,bar_bar'); 1;
    };
    ok( !$ok, 'FieldMask parse rejects an underscore in a camelCase path' );
    isa_ok( $@, 'Proto3::Exception::JSON::WKT',
        'parse rejection raises a JSON::WKT exception' );

    # A clean camelCase string still parses.
    my $back = Proto3::WKT::FieldMask->from_json_value('fooBar,baz');
    is_deeply( $back->{paths}, [ 'foo_bar', 'baz' ],
        'a well-formed FieldMask string parses to snake_case paths' );
}

# --- Value: NaN / Inf number_value cannot be serialized ----------------------
{
    my $nan = 9**9**9 - 9**9**9;    # NaN
    my $inf = 9**9**9;              # +Inf

    my $ok_nan = eval {
        Proto3::WKT::Value->to_json_value( { number_value => $nan } ); 1;
    };
    ok( !$ok_nan, 'Value rejects a NaN number_value (ValueRejectNanNumberValue)' );

    my $ok_inf = eval {
        Proto3::WKT::Value->to_json_value( { number_value => $inf } ); 1;
    };
    ok( !$ok_inf, 'Value rejects an Inf number_value (ValueRejectInfNumberValue)' );

    my $ok_ninf = eval {
        Proto3::WKT::Value->to_json_value( { number_value => -$inf } ); 1;
    };
    ok( !$ok_ninf, 'Value rejects a -Inf number_value' );

    # A finite number_value still serializes.
    is( Proto3::WKT::Value->to_json_value( { number_value => 1.5 } ),
        1.5, 'a finite Value number_value serializes' );
}

done_testing;
