# ABOUTME: Author test — public modules have full POD coverage (Step 33.4).
# Guarded: SKIPs cleanly when Test::Pod::Coverage is not installed so it never
# fails a run in a minimal environment. Author tests live under xt/ and are not
# part of the default `prove -lr t` gate.
use v5.38;
use warnings;
use Test::More;

eval { require Test::Pod::Coverage; Test::Pod::Coverage->import; 1 }
    or plan skip_all => 'Test::Pod::Coverage required for POD coverage testing';

# trustme: accept the documented-as-a-group accessor and adapter methods that
# the per-field code generator installs, plus the constructor `new` (which is
# documented under each class's SYNOPSIS/METHODS rather than as a named =head2).
# Everything in the public API surface must otherwise carry POD.
my %TRUSTME = (
    private => [ qr/^new$/ ],
);

all_pod_coverage_ok( { %TRUSTME, also_private => [] } );
