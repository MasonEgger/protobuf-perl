# ABOUTME: Step 31 — the conformance suite harness (spec §4.11, T-conf-1/2/3).
# Unit-tests the runner-output verdict logic always; runs the live Google
# conformance_test_runner against bin/proto3-conformance only when one is found
# (env CONFORMANCE_TEST_RUNNER or on PATH), else skips so the suite stays green.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Conformance;

# ----------------------------------------------------------------------
# Verdict logic (always runs — this is OUR code, not the external runner).
# parse_runner_output turns the runner's text into the required/recommended
# split the harness FAILs / reports on. The conformance bar is: zero required
# proto3 failures (T-conf-1); recommended failures are reported, not fatal
# (T-conf-2/3).
# ----------------------------------------------------------------------

# A clean run: a PASSED summary and no failure lines -> nothing to fail on.
{
    my $output = <<'END';
CONFORMANCE SUITE PASSED: 1234 successes, 5 skipped, 6 expected failures, 0 unexpected failures.
END
    my $v = Proto3::Conformance::parse_runner_output($output);
    is_deeply( $v->{required_failures}, [], 'clean run: no required failures' );
    is_deeply( $v->{recommended_failures}, [], 'clean run: no recommended failures' );
    ok( $v->{parsed_summary}, 'clean run: summary line parsed' );
    like( $v->{summary}, qr/PASSED/, 'clean run: summary captured' );
}

# A run with a required proto3 failure -> harness must treat it as fatal.
{
    my $output = <<'END';
ERROR, test=Required.Proto3.ProtobufInput.ValidDataScalar.INT32: roundtrip mismatch
CONFORMANCE SUITE FAILED: 1200 successes, 0 skipped, 6 expected failures, 1 unexpected failures.
END
    my $v = Proto3::Conformance::parse_runner_output($output);
    is_deeply(
        $v->{required_failures},
        ['Required.Proto3.ProtobufInput.ValidDataScalar.INT32'],
        'required failure captured (T-conf-1: this fails the build)',
    );
    ok( @{ $v->{required_failures} } > 0, 'required failure is non-empty -> fatal' );
}

# A run with only a recommended proto3 failure -> reported, NOT fatal.
{
    my $output = <<'END';
ERROR, test=Recommended.Proto3.JsonInput.FieldNameInLowerCamel: optional formatting
CONFORMANCE SUITE PASSED: 1233 successes, 5 skipped, 7 expected failures, 0 unexpected failures.
END
    my $v = Proto3::Conformance::parse_runner_output($output);
    is_deeply( $v->{required_failures}, [],
        'recommended-only run: no required failures -> not fatal' );
    is_deeply(
        $v->{recommended_failures},
        ['Recommended.Proto3.JsonInput.FieldNameInLowerCamel'],
        'recommended failure captured for reporting (T-conf-2/3)',
    );
}

# Mixed failures: required and recommended are split correctly.
{
    my $output = <<'END';
ERROR, test=Required.Proto3.A: boom
ERROR, test=Recommended.Proto3.B: meh
ERROR, test=Required.Proto3.C: boom
CONFORMANCE SUITE FAILED: 10 successes, 0 skipped, 0 expected failures, 2 unexpected failures.
END
    my $v = Proto3::Conformance::parse_runner_output($output);
    is_deeply(
        [ sort @{ $v->{required_failures} } ],
        [ 'Required.Proto3.A', 'Required.Proto3.C' ],
        'mixed: both required failures captured',
    );
    is_deeply(
        $v->{recommended_failures},
        ['Recommended.Proto3.B'],
        'mixed: recommended failure split out',
    );
}

# find_runner returns undef when nothing is on PATH and the env var is unset.
{
    local $ENV{CONFORMANCE_TEST_RUNNER};
    delete $ENV{CONFORMANCE_TEST_RUNNER};
    local $ENV{PATH} = '';
    is( Proto3::Conformance::find_runner(), undef,
        'find_runner: undef when no runner present' );
}

# find_runner honors an explicit executable path via the env var.
{
    local $ENV{CONFORMANCE_TEST_RUNNER} = $^X;    # the perl binary is executable
    is( Proto3::Conformance::find_runner(), $^X,
        'find_runner: honors CONFORMANCE_TEST_RUNNER when executable' );
}

# ----------------------------------------------------------------------
# Live integration (T-conf-1/2): drive the real Google runner against
# bin/proto3-conformance. Skipped on this box (no runner installed); CI sets
# CONFORMANCE_TEST_RUNNER so this stage actually exercises the suite.
# ----------------------------------------------------------------------
my $runner = Proto3::Conformance::find_runner();
SKIP: {
    skip 'conformance_test_runner not available (set CONFORMANCE_TEST_RUNNER to run)', 2
        unless defined $runner;

    my $testee = 'bin/proto3-conformance';
    ok( -x $testee, "testee $testee is executable" );

    # Run the suite with recommended tests enforced so the output reports the
    # recommended count too. Capture combined stdout+stderr for parsing.
    my $cmd = sprintf(
        '%s --enforce_recommended %s 2>&1',
        $runner, $testee,
    );
    my $output = `$cmd`;
    diag($output);

    my $v = Proto3::Conformance::parse_runner_output($output);

    my $rec = scalar @{ $v->{recommended_failures} };
    diag("recommended proto3 failures: $rec (non-blocking)");

    is_deeply( $v->{required_failures}, [],
        'live run: zero required proto3 failures (T-conf-1)' )
        or diag( 'required failures: ' . join( ', ', @{ $v->{required_failures} } ) );
}

done_testing;
