# ABOUTME: field-number bounds (B-003) and single-package enforcement (B-005).
# proto3 field numbers are 1..536870911 excluding the reserved 19000..19999.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;

sub parses ($src) {
    return eval { Protobuf::Parser->new->parse_string( 't.proto', $src ); 1 };
}

# B-003: invalid field numbers are rejected at parse time.
for my $n ( 0, 19000, 19500, 19999, 536_870_912 ) {
    ok( !parses(qq{syntax = "proto3";\nmessage M { string f = $n; }\n}),
        "field number $n rejected" );
}

# Valid boundaries are accepted.
for my $n ( 1, 18999, 20000, 536_870_911 ) {
    ok( parses(qq{syntax = "proto3";\nmessage M { string f = $n; }\n}),
        "field number $n accepted" );
}

# The reserved range is also enforced for map fields.
ok( !parses(qq{syntax = "proto3";\nmessage M { map<string,string> m = 19000; }\n}),
    'map field number 19000 rejected' );

# B-005: a second package declaration is a parse error.
ok( !parses(qq{syntax = "proto3";\npackage a;\npackage b;\n}),
    'double package declaration rejected' );
ok( parses(qq{syntax = "proto3";\npackage a.b.c;\nmessage M { string x = 1; }\n}),
    'single package declaration accepted' );

done_testing;
