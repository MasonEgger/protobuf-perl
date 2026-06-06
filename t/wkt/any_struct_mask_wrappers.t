# ABOUTME: Step 27 WKT tests — Empty, Any (@type + inner fields), FieldMask
# camelCase paths, parametric Wrappers bare-value JSON, and Struct/Value/
# ListValue/NullValue round-trips (§4.8, T-wkt-3..6).
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
use Protobuf::JSON;
use Protobuf::WKT;
use Protobuf::WKT::Empty;
use Protobuf::WKT::Any;
use Protobuf::WKT::FieldMask;
use Protobuf::WKT::Wrappers;
use Protobuf::WKT::Struct;

# --- 27.1: Empty <-> {} -------------------------------------------------

{
    is_deeply( Protobuf::WKT::Empty->to_json_value( {} ), {},
        'Empty -> {}' );
    is_deeply( Protobuf::WKT::Empty->from_json_value( {} ), {},
        'Empty <- {}' );

    # The facade registers Empty's schema.
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    ok( $schema->message('google.protobuf.Empty'),
        'facade registers Empty' );
}

# --- 27.2: Any with @type + inner fields (T-wkt-3) ----------------------

{
    # A schema with the WKTs plus a real inner message to wrap.
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    $schema->add_file(
        Protobuf::Schema::File->new(
            name     => 'inner.proto',
            package  => 'demo',
            messages => [
                Protobuf::Schema::Message->new(
                    name      => 'Point',
                    full_name => 'demo.Point',
                    fields    => [
                        Protobuf::Schema::Field->new(
                            name => 'x', number => 1, type => 'int32' ),
                        Protobuf::Schema::Field->new(
                            name => 'y', number => 2, type => 'int32' ),
                    ],
                ),
            ],
        )
    );
    $schema->resolve;
    my $codec = Protobuf::Codec->new( schema => $schema );
    my $jc = Protobuf::JSON->new( codec => $codec, schema => $schema );

    # The Any value carries the inner type's bytes.
    my $inner  = { x => 3, y => 4 };
    my $packed = $codec->encode( 'demo.Point', $inner );
    my $any    = {
        type_url => 'type.googleapis.com/demo.Point',
        value    => $packed,
    };

    # to_json_value now uses the JSON encoder to render the inner message, so the
    # inlined keys are camelCase JSON names (here x/y are unchanged).
    my $json = Protobuf::WKT::Any->to_json_value( $any, $codec, $jc );
    is( $json->{'@type'}, 'type.googleapis.com/demo.Point',
        'Any JSON carries @type' );
    is( $json->{x}, 3, 'Any JSON inlines inner field x' );
    is( $json->{y}, 4, 'Any JSON inlines inner field y' );

    my $back = Protobuf::WKT::Any->from_json_value( $json, $codec, $jc );
    is( $back->{type_url}, 'type.googleapis.com/demo.Point',
        'Any decode restores type_url' );
    my $decoded = $codec->decode( 'demo.Point', $back->{value} );
    is_deeply( $decoded, { x => 3, y => 4 },
        'Any decode restores inner bytes' );

    # Missing @type on decode -> JSON::WKT.
    eval { Protobuf::WKT::Any->from_json_value( { x => 1 }, $codec, $jc ); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT',
        'Any without @type -> JSON::WKT' );
}

# --- 27.3: FieldMask "a.b,c.d" camelCase (T-wkt-4) ----------------------

{
    my $mask = { paths => [ 'foo_bar.baz', 'a.b' ] };
    my $json = Protobuf::WKT::FieldMask->to_json_value($mask);
    is( $json, 'fooBar.baz,a.b', 'FieldMask -> camelCase comma string' );

    my $back = Protobuf::WKT::FieldMask->from_json_value('fooBar.baz,a.b');
    is_deeply( $back, { paths => [ 'foo_bar.baz', 'a.b' ] },
        'FieldMask <- camelCase string (snake_case round-trip)' );

    # Empty mask <-> empty string.
    is( Protobuf::WKT::FieldMask->to_json_value( { paths => [] } ), '',
        'empty FieldMask -> ""' );
    is_deeply( Protobuf::WKT::FieldMask->from_json_value(''), { paths => [] },
        'empty string -> empty FieldMask' );

    eval { Protobuf::WKT::FieldMask->from_json_value( {} ); 1 };
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT',
        'FieldMask non-string -> JSON::WKT' );
}

# --- 27.4: Wrappers bare-value JSON (T-wkt-5) ---------------------------

{
    # Int32Value(42) encodes as 42, NOT { value => 42 }.
    my $json = Protobuf::WKT::Wrappers->to_json_value(
        'google.protobuf.Int32Value', { value => 42 } );
    is( $json, 42, 'Int32Value -> bare 42' );
    ok( !ref $json, 'Int32Value JSON is a scalar, not a hashref' );

    my $back = Protobuf::WKT::Wrappers->from_json_value(
        'google.protobuf.Int32Value', 42 );
    is_deeply( $back, { value => 42 }, '42 -> { value => 42 }' );

    # The same parametric path for every pass-through wrapper type. bool and
    # bytes have a type-specific JSON form (JSON boolean / base64) and are
    # covered in t/wkt/wkt_json_conformance.t, so they are excluded here.
    my %sample = (
        'google.protobuf.Int32Value'  => -7,
        'google.protobuf.Int64Value'  => 9_000_000_000,
        'google.protobuf.UInt32Value' => 5,
        'google.protobuf.UInt64Value' => 12345,
        'google.protobuf.FloatValue'  => 1.5,
        'google.protobuf.DoubleValue' => 2.25,
        'google.protobuf.StringValue' => 'hello',
    );
    for my $full_name ( sort keys %sample ) {
        my $v   = $sample{$full_name};
        my $enc = Protobuf::WKT::Wrappers->to_json_value( $full_name,
            { value => $v } );
        is( $enc, $v, "$full_name -> bare value" );
        my $dec = Protobuf::WKT::Wrappers->from_json_value( $full_name, $v );
        is_deeply( $dec, { value => $v }, "$full_name <- bare value" );
    }

    # Wrappers register into the facade and resolve a handler each.
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    for my $name (qw(Int32Value BoolValue StringValue BytesValue
        DoubleValue FloatValue Int64Value UInt64Value UInt32Value)) {
        ok( $schema->message("google.protobuf.$name"),
            "facade registers $name" );
        is( Protobuf::WKT->json_handler("google.protobuf.$name"),
            'Protobuf::WKT::Wrappers', "$name handler is Wrappers" );
    }
}

# --- 27.5: Struct / Value / ListValue / NullValue (T-wkt-6) -------------

{
    # The Struct/Value/ListValue handlers bridge the codec message shape (oneof
    # members, field maps, value lists) and arbitrary JSON; the detailed kind-by-
    # kind coverage lives in t/wkt/struct_value_json.t. Here we assert the basic
    # contract and the round-trip through from->to.
    my $obj_json  = { name => 'Ada', nested => { k => 'v' } };
    my $obj_shape = Protobuf::WKT::Struct->from_json_value($obj_json);
    is_deeply(
        $obj_shape,
        { fields => {
                name   => { string_value => 'Ada' },
                nested => { struct_value => { fields =>
                            { k => { string_value => 'v' } } } },
            } },
        'Struct JSON object -> field map of Value shapes',
    );
    is_deeply( Protobuf::WKT::Struct->to_json_value($obj_shape), $obj_json,
        'Struct field map -> JSON object (round-trip)' );

    # NullValue maps to JSON null both ways.
    is( Protobuf::WKT::NullValue->to_json_value(0), undef,
        'NullValue -> null' );
    is( Protobuf::WKT::NullValue->from_json_value(undef), 0,
        'null -> NullValue 0' );

    # ListValue <-> JSON array via Value-shaped elements.
    my $list_json  = [ 1, 'two', undef ];
    my $list_shape = Protobuf::WKT::ListValue->from_json_value($list_json);
    is_deeply(
        $list_shape,
        { values =>
                [ { number_value => 1 }, { string_value => 'two' },
                { null_value => 0 } ] },
        'ListValue JSON array -> values list of Value shapes',
    );
    is_deeply( Protobuf::WKT::ListValue->to_json_value($list_shape), $list_json,
        'ListValue values list -> JSON array (round-trip)' );

    # Value covers each scalar kind, mapping JSON to the matching oneof member.
    is_deeply( Protobuf::WKT::Value->from_json_value(undef),
        { null_value => 0 }, 'Value null -> null_value' );
    is_deeply( Protobuf::WKT::Value->from_json_value(3.5),
        { number_value => 3.5 }, 'Value number -> number_value' );
    is_deeply( Protobuf::WKT::Value->from_json_value('x'),
        { string_value => 'x' }, 'Value string -> string_value' );
    is( Protobuf::WKT::Value->to_json_value( { number_value => 3.5 } ), 3.5,
        'Value number_value -> bare number' );

    # The facade registers the Struct family.
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    ok( $schema->message('google.protobuf.Struct'),
        'facade registers Struct' );
    ok( $schema->message('google.protobuf.Value'),
        'facade registers Value' );
    ok( $schema->message('google.protobuf.ListValue'),
        'facade registers ListValue' );
}

# --- facade also registers Any / FieldMask ------------------------------

{
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    ok( $schema->message('google.protobuf.Any'),
        'facade registers Any' );
    ok( $schema->message('google.protobuf.FieldMask'),
        'facade registers FieldMask' );

    is( Protobuf::WKT->json_handler('google.protobuf.Empty'),
        'Protobuf::WKT::Empty', 'Empty handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.Any'),
        'Protobuf::WKT::Any', 'Any handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.FieldMask'),
        'Protobuf::WKT::FieldMask', 'FieldMask handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.Struct'),
        'Protobuf::WKT::Struct', 'Struct handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.NullValue'),
        'Protobuf::WKT::NullValue', 'NullValue handler registered' );
}

done_testing;
