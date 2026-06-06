# ABOUTME: WKT Struct/Value/ListValue/NullValue JSON <-> message-shape tests —
# the dynamic-value family must map codec message shapes to/from arbitrary JSON.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use JSON::PP ();

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Codec;
use Protobuf::WKT;
use Protobuf::WKT::Struct;

# A codec over the registered WKT schemas, for binary round-trips.
my sub wkt_codec {
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    $schema->resolve if $schema->can('resolve');
    return Protobuf::Codec->new( schema => $schema );
}

# --- Value: each JSON kind maps to the right oneof member ----------------

{
    # to_json_value takes the message shape (one oneof key) and yields raw JSON.
    is( Protobuf::WKT::Value->to_json_value( { number_value => 5 } ), 5,
        'Value number_value -> 5' );
    is( Protobuf::WKT::Value->to_json_value( { string_value => 'hi' } ), 'hi',
        'Value string_value -> "hi"' );
    is( Protobuf::WKT::Value->to_json_value( { null_value => 0 } ), undef,
        'Value null_value -> null' );

    my $b = Protobuf::WKT::Value->to_json_value( { bool_value => 1 } );
    ok( JSON::PP::is_bool($b) && $b, 'Value bool_value true -> JSON true' );
    my $bf = Protobuf::WKT::Value->to_json_value( { bool_value => 0 } );
    ok( JSON::PP::is_bool($bf) && !$bf, 'Value bool_value false -> JSON false' );

    is_deeply(
        Protobuf::WKT::Value->to_json_value(
            { struct_value => { fields => { a => { number_value => 1 } } } } ),
        { a => 1 },
        'Value struct_value -> JSON object',
    );
    is_deeply(
        Protobuf::WKT::Value->to_json_value(
            { list_value => { values => [ { number_value => 1 },
                        { string_value => 'x' } ] } } ),
        [ 1, 'x' ],
        'Value list_value -> JSON array',
    );
}

# --- Value: from_json_value classifies an arbitrary JSON value -----------

{
    is_deeply( Protobuf::WKT::Value->from_json_value(undef),
        { null_value => 0 }, 'null -> null_value' );
    is_deeply( Protobuf::WKT::Value->from_json_value(5),
        { number_value => 5 }, 'integer -> number_value' );
    is_deeply( Protobuf::WKT::Value->from_json_value(1.5),
        { number_value => 1.5 }, 'float -> number_value' );
    is_deeply( Protobuf::WKT::Value->from_json_value('hello'),
        { string_value => 'hello' }, 'string -> string_value' );
    is_deeply( Protobuf::WKT::Value->from_json_value( JSON::PP::true ),
        { bool_value => 1 }, 'true -> bool_value 1' );
    is_deeply( Protobuf::WKT::Value->from_json_value( JSON::PP::false ),
        { bool_value => 0 }, 'false -> bool_value 0' );
    is_deeply(
        Protobuf::WKT::Value->from_json_value( { foo => 1 } ),
        { struct_value => { fields => { foo => { number_value => 1 } } } },
        'object -> struct_value',
    );
    is_deeply(
        Protobuf::WKT::Value->from_json_value( [ 0, 'hello' ] ),
        { list_value => { values =>
                    [ { number_value => 0 }, { string_value => 'hello' } ] } },
        'array -> list_value',
    );
}

# --- Struct: message shape { fields => {...} } <-> JSON object ------------

{
    my $shape = {
        fields => {
            greeting => { string_value => 'hi' },
            n        => { number_value => 3 },
            flag     => { bool_value => 1 },
            nada     => { null_value => 0 },
            nested   => { struct_value => { fields =>
                        { k => { string_value => 'v' } } } },
        },
    };

    my $json = Protobuf::WKT::Struct->to_json_value($shape);
    is( $json->{greeting}, 'hi', 'Struct field string' );
    is( $json->{n},        3,    'Struct field number' );
    ok( JSON::PP::is_bool( $json->{flag} ) && $json->{flag},
        'Struct field bool' );
    is( $json->{nada}, undef, 'Struct field null' );
    is_deeply( $json->{nested}, { k => 'v' }, 'Struct nested object' );

    my $back = Protobuf::WKT::Struct->from_json_value(
        { greeting => 'hi', n => 3, nested => { k => 'v' } } );
    is_deeply(
        $back,
        { fields => {
                greeting => { string_value => 'hi' },
                n        => { number_value => 3 },
                nested   => { struct_value => { fields =>
                            { k => { string_value => 'v' } } } },
            } },
        'Struct from JSON object builds field map',
    );

    # Empty object <-> empty Struct.
    is_deeply( Protobuf::WKT::Struct->to_json_value( { fields => {} } ), {},
        'empty Struct -> {}' );
    is_deeply( Protobuf::WKT::Struct->from_json_value( {} ), { fields => {} },
        '{} -> empty Struct' );
}

# --- StructWithEmptyListValue regression --------------------------------

{
    # {"listValue": []} -> a Struct whose "listValue" key is an empty ListValue.
    my $back = Protobuf::WKT::Struct->from_json_value( { listValue => [] } );
    is_deeply(
        $back,
        { fields => { listValue => { list_value => { values => [] } } } },
        'Struct with empty array value -> empty ListValue',
    );
}

# --- ListValue: { values => [...] } <-> JSON array -----------------------

{
    my $shape = { values =>
            [ { number_value => 1 }, { string_value => 'x' },
            { null_value => 0 } ] };
    is_deeply( Protobuf::WKT::ListValue->to_json_value($shape),
        [ 1, 'x', undef ], 'ListValue -> JSON array' );

    is_deeply(
        Protobuf::WKT::ListValue->from_json_value( [ 1, 'x', undef ] ),
        { values =>
                [ { number_value => 1 }, { string_value => 'x' },
                { null_value => 0 } ] },
        'JSON array -> ListValue',
    );

    # Empty array <-> empty ListValue.
    is_deeply( Protobuf::WKT::ListValue->to_json_value( { values => [] } ), [],
        'empty ListValue -> []' );
    is_deeply( Protobuf::WKT::ListValue->from_json_value( [] ), { values => [] },
        '[] -> empty ListValue' );
}

# --- NullValue stays an enum number 0 <-> null ---------------------------

{
    is( Protobuf::WKT::NullValue->to_json_value(0), undef, 'NullValue -> null' );
    is( Protobuf::WKT::NullValue->from_json_value(undef), 0, 'null -> NullValue' );
}

# --- Full binary round-trip through the codec (proves shape contract) ----

{
    my $codec = wkt_codec();

    # JSON {"value": 1} for a top-level Value, binary-encoded then decoded,
    # must survive and re-encode to the same JSON.
    for my $kind (
        [ 'number', 7,            { number_value => 7 } ],
        [ 'string', 'hello',      { string_value => 'hello' } ],
        [ 'object', { a => 1 },   undef ],
        [ 'array',  [ 1, 2 ],     undef ],
        )
    {
        my ( $label, $json, undef ) = @$kind;
        my $shape = Protobuf::WKT::Value->from_json_value($json);
        my $bytes = $codec->encode( 'google.protobuf.Value', $shape );
        my $back  = $codec->decode( 'google.protobuf.Value', $bytes );
        is_deeply( Protobuf::WKT::Value->to_json_value($back), $json,
            "Value $label survives binary round-trip" );
    }
}

# --- The facade still registers the family -------------------------------

{
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    is( Protobuf::WKT->json_handler('google.protobuf.Struct'),
        'Protobuf::WKT::Struct', 'Struct handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.Value'),
        'Protobuf::WKT::Value', 'Value handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.ListValue'),
        'Protobuf::WKT::ListValue', 'ListValue handler registered' );
    is( Protobuf::WKT->json_handler('google.protobuf.NullValue'),
        'Protobuf::WKT::NullValue', 'NullValue handler registered' );
}

done_testing;
