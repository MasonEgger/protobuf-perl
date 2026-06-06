# ABOUTME: Any JSON edge cases — an empty object {} is a valid empty Any (round
# trips to {}), and an Any wrapping google.protobuf.Empty inlines (no "value":{}).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Codec;
use Protobuf::JSON;
use Protobuf::WKT;
use Protobuf::WKT::Any;

my sub wkt_jc {
    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);
    $schema->resolve;
    my $codec = Protobuf::Codec->new( schema => $schema );
    my $jc = Protobuf::JSON->new( codec => $codec, schema => $schema );
    return ( $codec, $jc );
}

# An empty JSON object {} is a VALID empty Any (conformance AnyWithNoType): it
# decodes to an Any with no type_url and no value bytes.
{
    my ( $codec, $jc ) = wkt_jc();
    my $any = Protobuf::WKT::Any->from_json_value( {}, $codec, $jc );
    is( $any->{type_url}, '', 'empty Any has empty type_url' );
    is( $any->{value},    '', 'empty Any has empty value bytes' );
}

# An empty Any serializes back to {} (round-trip partner of the above).
{
    my ( $codec, $jc ) = wkt_jc();
    my $json = Protobuf::WKT::Any->to_json_value(
        { type_url => '', value => '' }, $codec, $jc );
    is_deeply( $json, {}, 'empty Any serializes to {}' );
}

# A non-empty object still requires "@type".
{
    my ( $codec, $jc ) = wkt_jc();
    my $ok = eval {
        Protobuf::WKT::Any->from_json_value( { foo => 1 }, $codec, $jc );
        1;
    };
    ok( !$ok, 'non-empty Any object without @type is rejected' );
    isa_ok( $@, 'Protobuf::Exception::JSON::WKT', 'throws JSON::WKT' );
}

# An Any wrapping google.protobuf.Empty inlines: its JSON has "@type" and NO
# "value" key, because Empty's JSON form is the plain object {} rather than a
# special value form (conformance AnyEmpty).
{
    my ( $codec, $jc ) = wkt_jc();
    my $any = {
        type_url => 'type.googleapis.com/google.protobuf.Empty',
        value    => '',
    };
    my $json = Protobuf::WKT::Any->to_json_value( $any, $codec, $jc );
    is( $json->{'@type'}, 'type.googleapis.com/google.protobuf.Empty',
        'Any-of-Empty carries @type' );
    ok( !exists $json->{value},
        'Any-of-Empty does NOT carry a "value" wrapper' );
}

done_testing;
