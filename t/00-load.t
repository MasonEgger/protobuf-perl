# ABOUTME: Smoke test that Proto3 loads and exposes a non-empty $VERSION.
# Guards the build foundation before any application logic exists.
use strict;
use warnings;
use Test::More;

use_ok('Proto3') or BAIL_OUT('Proto3 failed to load');

ok( defined $Proto3::VERSION, '$Proto3::VERSION is defined' );
ok( length "$Proto3::VERSION", '$Proto3::VERSION is non-empty' );

done_testing;
