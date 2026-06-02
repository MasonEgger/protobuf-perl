# ABOUTME: T-res-7 — resolver differential against protoc. Every cross-file field
# type our resolver links must match protoc's FileDescriptorSet type_name.
# This is the test that proves we lack GPB::Dynamic's relative-resolution bug.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use lib 't/lib';

use Proto3Test::Protoc qw(have_protoc);

plan skip_all => 'protoc not on PATH' unless have_protoc();

use Proto3::Parser;
use Proto3::DescriptorSet;

use File::Temp ();
use File::Spec ();
use File::Path ();

# ----------------------------------------------------------------------
# A self-contained multi-file proto graph that exercises innermost-first
# cross-file scoping — the exact shape of the sdk-core bug GPB::Dynamic
# fails on. The reference `common.WorkerDeploymentVersion` inside package
# `coresdk.workflow_activation` must resolve OUTWARD to
# `coresdk.common.WorkerDeploymentVersion` (defined in a different file),
# NOT to a root-level `common.WorkerDeploymentVersion` that also exists.
# ----------------------------------------------------------------------
my %FILES = (

    # Root-scope decoy: a type named common.WorkerDeploymentVersion sitting at
    # the top-level package `common`. Innermost-first scoping must NOT pick this
    # one for a reference made inside coresdk.workflow_activation.
    'root_common.proto' => <<'PROTO',
syntax = "proto3";
package common;

message WorkerDeploymentVersion {
  string root_marker = 1;
}
PROTO

    # The intended target: coresdk.common.WorkerDeploymentVersion. A reference to
    # `common.WorkerDeploymentVersion` from coresdk.workflow_activation resolves
    # here (coresdk.common.X), the second candidate in the search chain.
    'coresdk_common.proto' => <<'PROTO',
syntax = "proto3";
package coresdk.common;

message WorkerDeploymentVersion {
  string build_id = 1;
}

message Payload {
  bytes data = 1;
}
PROTO

    # The consumer: package coresdk.workflow_activation makes relative
    # cross-file references that must walk outward one scope at a time.
    'workflow_activation.proto' => <<'PROTO',
syntax = "proto3";
package coresdk.workflow_activation;

import "root_common.proto";
import "coresdk_common.proto";

message WorkflowActivation {
  // Relative ref: must resolve to coresdk.common.WorkerDeploymentVersion,
  // not the root-level common.WorkerDeploymentVersion.
  common.WorkerDeploymentVersion deployment_version = 1;

  // Relative ref into the same sibling package.
  common.Payload payload = 2;

  // A nested message making its own cross-file relative reference.
  message Job {
    common.Payload arg = 1;
  }
  repeated Job jobs = 3;
}
PROTO
);

# Write the graph to a temp include root.
my $root = File::Temp->newdir;
for my $name ( keys %FILES ) {
    my $path = File::Spec->catfile( "$root", $name );
    open my $fh, '>', $path or die "write $path: $!";
    print {$fh} $FILES{$name};
    close $fh;
}

# Compile the whole graph to one FileDescriptorSet (with imports) via protoc.
my $fds_path = File::Spec->catfile( "$root", 'graph.fds' );
system(
    'protoc',
    "--proto_path=$root",
    "--descriptor_set_out=$fds_path",
    '--include_imports',
    'workflow_activation.proto',
) == 0 or die 'protoc failed to compile the graph';

# protoc's view: load the FDS and read each field's resolved type_name directly.
my $protoc_schema = Proto3::DescriptorSet->load_file($fds_path);

# Our view: parse the graph and resolve with our own resolver.
my $parser = Proto3::Parser->new( include_paths => ["$root"] );
my $our_schema = $parser->parse_with_imports('workflow_activation.proto');
$our_schema->resolve;

# For every message-or-enum-typed field across the graph, the fully-qualified
# target our resolver linked must equal the one protoc recorded. Build a
# name -> target map for each side and compare.
sub cross_file_targets ($schema) {
    my %targets;
    for my $message ( @{ $schema->all_messages } ) {
        for my $field ( @{ $message->fields } ) {
            next unless $field->is_message || $field->is_enum;
            next unless $field->type_ref;
            my $key = $message->full_name . '.' . $field->name;
            $targets{$key} = $field->type_ref->full_name;
        }
    }
    return \%targets;
}

my $protoc_targets = cross_file_targets($protoc_schema);
my $our_targets    = cross_file_targets($our_schema);

# Sanity: the differential must actually exercise the innermost-first decision —
# the deployment_version field must resolve to the coresdk.common type, proving
# we did not pick the root-level decoy (the GPB::Dynamic failure mode).
is(
    $our_targets->{
        'coresdk.workflow_activation.WorkflowActivation.deployment_version'},
    'coresdk.common.WorkerDeploymentVersion',
    'relative ref resolves innermost-first to coresdk.common, not root common',
);

is_deeply(
    $our_targets,
    $protoc_targets,
    'every cross-file field target matches protoc (T-res-7)',
);

# And there is genuinely more than one cross-file reference under test.
cmp_ok( scalar( keys %$our_targets ), '>=', 3,
    'multiple cross-file references exercised' );

done_testing;
