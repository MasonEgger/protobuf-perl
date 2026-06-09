# ABOUTME: Author test — public modules have full POD coverage (Step 33.4).
# Guarded: SKIPs cleanly when Test::Pod::Coverage is not installed so it never
# fails a run in a minimal environment. Author tests live under xt/ and are not
# part of the default `prove -lr t` gate.
use v5.38;
use warnings;
use Test::More;

eval { require Test::Pod::Coverage; Test::Pod::Coverage->import; 1 }
    or plan skip_all => 'Test::Pod::Coverage required for POD coverage testing';

# `new` is documented under each class's SYNOPSIS/METHODS rather than as a named
# =head2, so accept it. Use also_private (which ADDS to Pod::Coverage's defaults)
# rather than private (which REPLACES them): replacing the defaults drops the
# built-in "underscore-prefixed subs are private" rule and wrongly counts every
# internal helper as undocumented. Everything else public must carry POD.
all_pod_coverage_ok( { also_private => [ qr/^new$/ ] } );
