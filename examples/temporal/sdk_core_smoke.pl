#!/usr/bin/env perl
# ABOUTME: examples/temporal — smoke the Temporal sdk-core proto graph end-to-end.
# Parses + resolves a couple of sdk-core entry-point protos and round-trips them
# on the wire. Guarded: needs the sdk-core proto tree via $SDK_CORE_PROTO_PATH;
# prints guidance and exits 0 when it is not set, so the example never errors out.
use v5.38;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/../../lib";

use Proto3::Parser;
use Proto3::Codec;

my $root = $ENV{SDK_CORE_PROTO_PATH};
unless ( defined $root && length $root && -d $root ) {
    say 'SDK_CORE_PROTO_PATH is not set (or does not exist).';
    say 'Clone temporalio/sdk-core and point SDK_CORE_PROTO_PATH at its proto';
    say 'include root (the directory containing the temporal/ tree), e.g.:';
    say '  SDK_CORE_PROTO_PATH=~/sdk-core/sdk-core-protos/protos/api_upstream \\';
    say '    perl -Ilib examples/temporal/sdk_core_smoke.pl';
    exit 0;
}

# The two proof-of-purpose entry points (spec §5.2), each with the file that
# defines it (paths follow the temporalio/sdk-core layout).
my %TARGET = (
    'coresdk.workflow_activation.WorkflowActivation' =>
        'temporal/sdk/core/workflow_activation/workflow_activation.proto',
    'temporal.api.workflowservice.v1.StartWorkflowExecutionRequest' =>
        'temporal/api/workflowservice/v1/request_response.proto',
);

# Collect the whole reachable graph into one schema (a shared parser lets the
# import cache deduplicate the diamond between the two entry points).
my $parser = Proto3::Parser->new( include_paths => [$root] );
my $schema = Proto3::Schema->new;
for my $full_name ( sort keys %TARGET ) {
    my $sub = $parser->parse_with_imports( $TARGET{$full_name} );
    $schema->add_file($_)
        for grep { !$schema->file( $_->name ) } $sub->files->@*;
}

$schema->resolve;
say 'Resolved sdk-core graph: ', scalar( $schema->all_messages->@* ),
    ' messages.';

my $codec = Proto3::Codec->new( schema => $schema );
for my $full_name ( sort keys %TARGET ) {
    my $bytes = $codec->encode( $full_name, {} );
    my $back  = $codec->decode( $full_name, $bytes );
    say "Round-tripped $full_name (empty message): ",
        ( keys %$back ? 'non-empty' : 'ok' );
}
