# ABOUTME: JSON int fields accept a quoted exponential/decimal-point string that
# denotes an EXACT integer ("1e5" -> 100000), but reject a non-integral one.
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

my sub codec_for {
    my ($message) = @_;
    my $file = Protobuf::Schema::File->new(
        name => 'm.proto', package => 'pkg', messages => [$message], enums => [],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    return Protobuf::Codec->new( schema => $schema );
}

my sub int32_codec {
    my $message = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'pkg.M',
        fields => [
            Protobuf::Schema::Field->new( name => 'f', number => 1, type => 'int32' ),
        ],
    );
    return codec_for($message);
}

# A quoted exponential string that is an exact integer is accepted
# (conformance JsonInput.Int32FieldQuotedExponentialValue: "1e5" -> 100000).
{
    my $codec = int32_codec();
    my $d = $codec->decode_json( 'pkg.M', '{"f": "1e5"}' );
    is( $d->{f}, 100000, 'quoted "1e5" decodes to 100000' );
}

# Uppercase exponent and decimal-point mantissa, still exact.
{
    my $codec = int32_codec();
    is( $codec->decode_json( 'pkg.M', '{"f": "1.5E1"}' )->{f}, 15,
        'quoted "1.5E1" decodes to 15' );
    is( $codec->decode_json( 'pkg.M', '{"f": "15.0"}' )->{f}, 15,
        'quoted "15.0" decodes to 15' );
    is( $codec->decode_json( 'pkg.M', '{"f": "-2e3"}' )->{f}, -2000,
        'quoted "-2e3" decodes to -2000' );
}

# A non-integral quoted exponential is rejected.
{
    my $codec = int32_codec();
    my $ok = eval { $codec->decode_json( 'pkg.M', '{"f": "1.5e0"}' ); 1 };
    ok( !$ok, 'quoted non-integral "1.5e0" is rejected' );
}

# A quoted exponential that resolves to an out-of-range int32 is rejected.
{
    my $codec = int32_codec();
    my $ok = eval { $codec->decode_json( 'pkg.M', '{"f": "1e30"}' ); 1 };
    ok( !$ok, 'quoted "1e30" out of int32 range is rejected' );
}

# A plain (non-exponential) quoted integer still works.
{
    my $codec = int32_codec();
    is( $codec->decode_json( 'pkg.M', '{"f": "42"}' )->{f}, 42,
        'quoted plain "42" still decodes' );
}

done_testing;
