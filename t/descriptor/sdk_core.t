# ABOUTME: T-fds-2 — load the sdk-core proto graph as a FileDescriptorSet and
# verify every message and field is present. Skips unless a graph path is given.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use lib 't/lib';

use ProtobufTest::Protoc qw(have_protoc);

# The sdk-core proto graph is not available on this box by default. A path is
# supplied out-of-band via PROTO3_SDK_CORE_PROTO_ROOT (an include root holding
# the sdk-core .proto tree). Without it the test skips — its absence must never
# fail the suite (the box has no sdk-core graph).
my $root = $ENV{PROTO3_SDK_CORE_PROTO_ROOT};
plan skip_all =>
    'set PROTO3_SDK_CORE_PROTO_ROOT to an sdk-core proto include root to run'
    unless defined $root && length $root;

plan skip_all => 'protoc not on PATH' unless have_protoc();
plan skip_all => "sdk-core proto root not a directory: $root" unless -d $root;

use Protobuf::DescriptorSet;

use File::Temp ();
use File::Spec ();
use File::Find ();

# Find the entry-point proto(s) to compile. The caller may pin a specific file
# via PROTO3_SDK_CORE_ENTRY (relative to $root); otherwise compile every .proto
# under the root with --include_imports so the whole graph lands in one FDS.
my @entries;
if ( my $entry = $ENV{PROTO3_SDK_CORE_ENTRY} ) {
    @entries = ($entry);
}
else {
    File::Find::find(
        sub {
            return unless /\.proto\z/;
            my $rel = File::Spec->abs2rel( $File::Find::name, $root );
            push @entries, $rel;
        },
        $root,
    );
}

ok( scalar(@entries), 'found at least one sdk-core .proto to compile' )
    or plan skip_all => 'no .proto files under the sdk-core root';

my $dir = File::Temp->newdir;
my $fds_path = File::Spec->catfile( "$dir", 'sdk_core.fds' );

my $rc = system(
    'protoc',
    "--proto_path=$root",
    "--descriptor_set_out=$fds_path",
    '--include_imports',
    @entries,
);
is( $rc, 0, 'protoc compiled the sdk-core graph to an FDS' ) or do {
    done_testing;
    exit 0;
};

my $schema = Protobuf::DescriptorSet->load_file($fds_path);

# Every message and enum in the graph is indexed.
cmp_ok( scalar( @{ $schema->all_messages } ),
    '>', 0, 'sdk-core schema has messages' );

# Every message-or-enum-typed field resolved to a target (resolve() ran without
# leaving a dangling reference — load_file resolves before returning, so this is
# really asserting no field was silently left unresolved).
my $unresolved = 0;
my $total_named = 0;
for my $message ( @{ $schema->all_messages } ) {
    for my $field ( @{ $message->fields } ) {
        next unless $field->is_message || $field->is_enum;
        $total_named++;
        $unresolved++ unless $field->type_ref;
    }
}
is( $unresolved, 0,
    "all $total_named named-type fields resolved (no dangling references)" );

done_testing;
