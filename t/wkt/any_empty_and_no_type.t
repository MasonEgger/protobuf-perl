# ABOUTME: Any JSON edge cases — an empty object {} is a valid empty Any (round
# trips to {}), and an Any wrapping google.protobuf.Empty inlines (no "value":{}).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Codec;
use Proto3::JSON;
use Proto3::WKT;
use Proto3::WKT::Any;

my sub wkt_jc {
    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);
    $schema->resolve;
    my $codec = Proto3::Codec->new( schema => $schema );
    my $jc = Proto3::JSON->new( codec => $codec, schema => $schema );
    return ( $codec, $jc );
}

# An empty JSON object {} is a VALID empty Any (conformance AnyWithNoType): it
# decodes to an Any with no type_url and no value bytes.
{
    my ( $codec, $jc ) = wkt_jc();
    my $any = Proto3::WKT::Any->from_json_value( {}, $codec, $jc );
    is( $any->{type_url}, '', 'empty Any has empty type_url' );
    is( $any->{value},    '', 'empty Any has empty value bytes' );
}

# An empty Any serializes back to {} (round-trip partner of the above).
{
    my ( $codec, $jc ) = wkt_jc();
    my $json = Proto3::WKT::Any->to_json_value(
        { type_url => '', value => '' }, $codec, $jc );
    is_deeply( $json, {}, 'empty Any serializes to {}' );
}

# A non-empty object still requires "@type".
{
    my ( $codec, $jc ) = wkt_jc();
    my $ok = eval {
        Proto3::WKT::Any->from_json_value( { foo => 1 }, $codec, $jc );
        1;
    };
    ok( !$ok, 'non-empty Any object without @type is rejected' );
    isa_ok( $@, 'Proto3::Exception::JSON::WKT', 'throws JSON::WKT' );
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
    my $json = Proto3::WKT::Any->to_json_value( $any, $codec, $jc );
    is( $json->{'@type'}, 'type.googleapis.com/google.protobuf.Empty',
        'Any-of-Empty carries @type' );
    ok( !exists $json->{value},
        'Any-of-Empty does NOT carry a "value" wrapper' );
}

done_testing;
