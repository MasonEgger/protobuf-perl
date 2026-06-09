# ABOUTME: a Duration whose nanos sign disagrees with seconds raises a TYPED
# Protobuf::Exception::JSON::WKT, catchable by class (B-017).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use Scalar::Util qw(blessed);

use Protobuf::DescriptorSet;
use Protobuf::Codec;
use Protobuf::Exception;

my $schema = Protobuf::DescriptorSet->load_file('share/proto/conformance.fds');
my $codec  = Protobuf::Codec->new( schema => $schema );

my $err = do {
    local $@;
    eval {
        $codec->encode_json( 'google.protobuf.Duration',
            { seconds => 5, nanos => -500_000_000 } );
        1;
    };
    $@;
};

ok( blessed($err), 'Duration sign mismatch raises an object, not a plain string' );
isa_ok( $err, 'Protobuf::Exception::JSON::WKT',
    'Duration sign mismatch is a typed JSON::WKT exception' );

done_testing;
