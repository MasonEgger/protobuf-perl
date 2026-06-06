# ABOUTME: the conformance testee codec must preserve unknown fields so a
# protobuf->protobuf round-trip re-emits an unknown field (e.g. UnknownVarint).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Conformance;

# The cached conformance codec must have unknown-field preservation enabled,
# otherwise an unknown wire field (conformance UnknownVarint) is silently
# dropped instead of echoed back.
my $codec = Protobuf::Conformance->codec;
ok(
    $codec->preserve_unknown_fields,
    'conformance codec preserves unknown fields'
);

done_testing;
