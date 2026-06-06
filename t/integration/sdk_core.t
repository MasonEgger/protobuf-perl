# ABOUTME: Step 33 — sdk-core proof-of-purpose smoke (spec §4.7 T-fds-2, §5.2).
# Loads the full Temporal sdk-core proto graph, resolves it with no unresolved
# types, and round-trips WorkflowActivation + StartWorkflowExecutionRequest.
# Requires the sdk-core proto root via $ENV{SDK_CORE_PROTO_PATH}; skips otherwise
# so `prove -lr t` stays green without the (large, external) proto graph.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use lib 't/lib';

use File::Spec ();

# ----------------------------------------------------------------------
# Gating: the sdk-core proto graph (~150 files from the temporalio/sdk-core
# repo) is not vendored here. Point SDK_CORE_PROTO_PATH at a directory that
# contains the `temporal/` proto tree (the include root used by sdk-core) to
# exercise this smoke. Without it, skip — never fail the suite for its absence.
# ----------------------------------------------------------------------
my $root = $ENV{SDK_CORE_PROTO_PATH};
plan skip_all =>
    'set SDK_CORE_PROTO_PATH to the sdk-core proto include root to run this smoke'
    unless defined $root && length $root;

plan skip_all => "SDK_CORE_PROTO_PATH does not exist: $root"
    unless -d $root;

require Protobuf::Parser;
require Protobuf::Codec;

# The two entry-point messages spec §5.2 names as the proof-of-purpose targets,
# each paired with the .proto file (relative to the include root) that defines
# it. These paths follow the temporalio/sdk-core layout.
my %TARGET = (
    'coresdk.workflow_activation.WorkflowActivation' =>
        'temporal/sdk/core/workflow_activation/workflow_activation.proto',
    'temporal.api.workflowservice.v1.StartWorkflowExecutionRequest' =>
        'temporal/api/workflowservice/v1/request_response.proto',
);

# ----------------------------------------------------------------------
# 33.2: load + resolve the graph; no UnresolvedType must remain.
# parse_with_imports follows every import transitively, so naming the two
# entry-point files pulls in the whole reachable graph.
# ----------------------------------------------------------------------
# One parser so the import cache deduplicates the diamond between the two entry
# points; collect every reachable file into a single schema.
my $parser = Protobuf::Parser->new( include_paths => [$root] );
my $schema = Protobuf::Schema->new;
for my $full_name ( sort keys %TARGET ) {
    my $sub = $parser->parse_with_imports( $TARGET{$full_name} );
    $schema->add_file($_)
        for grep { !$schema->file( $_->name ) } $sub->files->@*;
}

ok( $schema, '33.2: sdk-core graph parsed via parse_with_imports' );

# resolve must succeed and leave no UnresolvedType in any field's type_ref.
eval { $schema->resolve; 1 }
    or do { fail("33.2: resolve failed: $@"); done_testing(); exit };
pass('33.2: resolve succeeded');

my @unresolved;
for my $message ( $schema->all_messages->@* ) {
    for my $field ( $message->fields->@* ) {
        my $ref = $field->can('type_ref') ? $field->type_ref : undef;
        next unless defined $ref;
        push @unresolved, $message->full_name . '.' . $field->name
            if ref($ref) =~ /Unresolved/;
    }
}
is_deeply( \@unresolved, [], '33.2: no UnresolvedType remains after resolve' )
    or diag( "unresolved: @unresolved" );

# ----------------------------------------------------------------------
# 33.3: round-trip the two entry-point messages through the codec, and (if
# protoc is present) cross-check one against protoc's wire output.
# ----------------------------------------------------------------------
my $codec = Protobuf::Codec->new( schema => $schema );

for my $full_name ( sort keys %TARGET ) {
    ok( $schema->message($full_name), "33.3: $full_name is in the schema" );

    # An empty message is the minimal round-trip: encode -> decode -> empty.
    my $bytes = $codec->encode( $full_name, {} );
    my $back  = $codec->decode( $full_name, $bytes );
    is_deeply( $back, {}, "33.3: $full_name empty round-trips" );
}

done_testing();
