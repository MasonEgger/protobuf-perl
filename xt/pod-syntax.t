# ABOUTME: Author test — every module's POD is syntactically valid (Step 33.4).
# Guarded: SKIPs cleanly when Test::Pod is not installed so it never fails a run
# in a minimal environment. Author tests live under xt/ and are not part of the
# default `prove -lr t` gate.
use v5.38;
use warnings;
use Test::More;

eval { require Test::Pod; Test::Pod->import; 1 }
    or plan skip_all => 'Test::Pod required for POD syntax checking';

all_pod_files_ok( all_pod_files('lib', 'bin') );
