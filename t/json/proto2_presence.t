# ABOUTME: Protobuf::JSON encode tests for proto2/editions explicit presence — a
# proto2 singular scalar set to its type-zero MUST be emitted in JSON output,
# while a proto3 implicit-presence field at zero stays omitted (no regression).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use JSON::PP ();

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Schema::Features;
use Protobuf::Codec;

# --- helpers ------------------------------------------------------------

# Install an edition's resolved feature set on each field, mirroring what
# Schema->resolve does. A proto2 field becomes explicit-presence even without a
# literal `optional` label.
my sub install_features ($edition, $fields) {
    my $features = Protobuf::Schema::Features->for_edition($edition);
    $_->set_features($features) for @$fields;
    return;
}

# Build a one-message codec from already-constructed field objects.
my sub codec_for ($fields) {
    my $message = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'pkg.M', fields => $fields,
    );
    my $file = Protobuf::Schema::File->new(
        name => 'm.proto', package => 'pkg', messages => [$message],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    return Protobuf::Codec->new( schema => $schema );
}

my sub from_json ($string) { return JSON::PP->new->decode($string) }

# --- proto2 explicit-presence scalar at zero IS emitted -----------------

{
    my $int  = Protobuf::Schema::Field->new(
        name => 'n', number => 1, type => 'int32', label => 'singular',
    );
    my $str  = Protobuf::Schema::Field->new(
        name => 's', number => 2, type => 'string', label => 'singular',
    );
    my $bool = Protobuf::Schema::Field->new(
        name => 'b', number => 3, type => 'bool', label => 'singular',
    );
    install_features( 'proto2', [ $int, $str, $bool ] );
    is( $int->presence, 'explicit',
        'proto2 singular int32 resolves to explicit presence' );

    my $codec = codec_for( [ $int, $str, $bool ] );
    my $got =
        from_json( $codec->encode_json( 'pkg.M', { n => 0, s => '', b => 0 } ) );

    ok( exists $got->{n}, 'proto2 explicit int32 at zero IS emitted in JSON' );
    is( $got->{n}, 0, 'proto2 explicit int32 emits the value 0' );
    ok( exists $got->{s}, 'proto2 explicit string at "" IS emitted in JSON' );
    is( $got->{s}, '', 'proto2 explicit string emits the empty string' );
    ok( exists $got->{b}, 'proto2 explicit bool at false IS emitted in JSON' );
    is( $got->{b}, JSON::PP::false, 'proto2 explicit bool emits false' );
}

# --- proto3 implicit-presence scalar at zero stays OMITTED (no regression)

{
    my $int = Protobuf::Schema::Field->new(
        name => 'n', number => 1, type => 'int32', label => 'singular',
    );
    install_features( 'proto3', [$int] );
    is( $int->presence, 'implicit',
        'proto3 singular int32 resolves to implicit presence' );

    my $codec = codec_for( [$int] );
    my $got   = from_json( $codec->encode_json( 'pkg.M', { n => 0 } ) );
    ok( !exists $got->{n},
        'proto3 implicit int32 at zero stays omitted from JSON' );
}

done_testing;
