# ABOUTME: proto2 extensions round-trip through JSON under their bracketed
# fully-qualified key, e.g. "[pkg.Message.extension_name]".
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::DescriptorSet;
use Proto3::Codec;
use Proto3::JSON;

my $fds = 'share/proto/conformance-v34.fds';
plan skip_all => "missing $fds" unless -f $fds;

my $schema = Proto3::DescriptorSet->load_file($fds);
my $codec  = Proto3::Codec->new( schema => $schema );
my $json   = Proto3::JSON->new( codec => $codec, schema => $schema );
my $T = 'protobuf_test_messages.proto2.TestAllTypesProto2';

# A bracketed extension key decodes and re-encodes verbatim.
{
    my $in = '{"[protobuf_test_messages.proto2.extension_int32]": 1}';
    my $decoded = $json->decode( $T, $in );
    ok( exists $decoded->{'__json_extensions__'},
        'extension key decodes into the sidecar' );
    is(
        $decoded->{'__json_extensions__'}
            {'[protobuf_test_messages.proto2.extension_int32]'},
        1,
        'extension value decoded',
    );
    my $out = $json->encode( $T, $decoded );
    like(
        $out,
        qr/\Q[protobuf_test_messages.proto2.extension_int32]\E/,
        're-encoded JSON carries the bracketed extension key',
    );
}

done_testing;
