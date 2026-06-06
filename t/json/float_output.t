# ABOUTME: proto3 JSON float/double output — full round-trip precision for finite
# values, and the "Infinity"/"-Infinity"/"NaN" string forms for non-finite ones.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Codec;
use Protobuf::JSON;

sub json_for ($type) {
    my $f = Protobuf::Schema::Field->new(
        name => 'd', json_name => 'd', number => 1,
        label => 'singular', type => $type,
    );
    my $r = Protobuf::Schema::Field->new(
        name => 'r', json_name => 'r', number => 2,
        label => 'repeated', type => $type,
    );
    my $m = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'M', fields => [ $f, $r ],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file(
        Protobuf::Schema::File->new(
            name => 'x.proto', package => '',
            messages => [$m], enums => [], services => [], imports => [],
        )
    );
    $schema->resolve;
    my $codec = Protobuf::Codec->new( schema => $schema );
    return Protobuf::JSON->new( codec => $codec, schema => $schema );
}

my $INF  = 9**9**9;
my $NINF = -9**9**9;
my $NAN  = $INF / $INF;

# double: smallest normal positive needs full 17-significant-digit precision.
{
    my $j = json_for('double');
    is(
        $j->encode( 'M', { d => 2.2250738585072014e-308 } ),
        '{"d":2.2250738585072014e-308}',
        'double keeps full round-trip precision',
    );
    is( $j->encode( 'M', { d => 1.5 } ), '{"d":1.5}', 'simple double unchanged' );
}

# Non-finite values use the quoted string forms.
{
    my $j = json_for('double');
    is( $j->encode( 'M', { d => $INF } ),  '{"d":"Infinity"}',  'double +inf -> "Infinity"' );
    is( $j->encode( 'M', { d => $NINF } ), '{"d":"-Infinity"}', 'double -inf -> "-Infinity"' );
    is( $j->encode( 'M', { d => $NAN } ),  '{"d":"NaN"}',       'double NaN -> "NaN"' );
}

# Repeated floats mix finite and non-finite correctly.
{
    my $j = json_for('double');
    is(
        $j->encode( 'M', { r => [ 1.5, $INF, $NINF ] } ),
        '{"r":[1.5,"Infinity","-Infinity"]}',
        'repeated double formats each element',
    );
}

# float type uses the same forms.
{
    my $j = json_for('float');
    is( $j->encode( 'M', { d => $INF } ), '{"d":"Infinity"}', 'float +inf -> "Infinity"' );
    is( $j->encode( 'M', { d => 0.5 } ),  '{"d":0.5}',        'simple float unchanged' );
}

done_testing;
