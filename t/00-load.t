# ABOUTME: Smoke test that Proto3 loads and exposes a non-empty $VERSION.
# Guards the build foundation before any application logic exists.
use strict;
use warnings;
use Test::More;

use_ok('Protobuf') or BAIL_OUT('Protobuf failed to load');

ok( defined $Protobuf::VERSION, '$Protobuf::VERSION is defined' );
ok( length "$Protobuf::VERSION", '$Protobuf::VERSION is non-empty' );

done_testing;
