# ABOUTME: serialize must escape control chars in string option values so its
# output re-parses (N-008) — newlines, tabs, CR, and other control bytes.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;

# A string option value carrying a newline (decoded from \n at parse time) must
# round-trip: serialize -> parse must not die, and the value must be preserved.
{
    my $src = qq{syntax = "proto3";\noption foo = "line1\\nline2\\ttab";\n};
    my $f1  = Protobuf::Parser->new->parse_string( 't.proto', $src );
    is( $f1->options->{foo}, "line1\nline2\ttab", 'parsed value has real ctrl chars' );

    my $out = Protobuf::Parser->serialize($f1);
    my $f2  = eval { Protobuf::Parser->new->parse_string( 't.proto', $out ) };
    ok( $f2, 'serialized output with control chars re-parses' ) or diag $@;
    is( $f2->options->{foo}, "line1\nline2\ttab",
        'control-char string value survives the round-trip' )
        if $f2;
}

# Embedded quotes/backslashes still round-trip too.
{
    my $src = qq{syntax = "proto3";\noption bar = "a\\"b\\\\c";\n};
    my $f1  = Protobuf::Parser->new->parse_string( 't.proto', $src );
    my $out = Protobuf::Parser->serialize($f1);
    my $f2  = Protobuf::Parser->new->parse_string( 't.proto', $out );
    is( $f2->options->{bar}, $f1->options->{bar},
        'quote/backslash string value survives the round-trip' );
}


# A numeric-LOOKING string option value stays a quoted string and round-trips
# stably (it must not collapse to a number on re-serialize).
{
    my $src = qq{syntax = "proto3";\noption ver = { v: "1.0" e: "1e3" z: "007" };\n};
    my $f1  = Protobuf::Parser->new->parse_string( q{t.proto}, $src );
    my $out = Protobuf::Parser->serialize($f1);
    my $f2  = Protobuf::Parser->new->parse_string( q{t.proto}, $out );
    is( $f2->options->{ver}{v}, q{1.0}, q{numeric-looking string "1.0" preserved} );
    is( $f2->options->{ver}{e}, q{1e3}, q{numeric-looking string "1e3" preserved} );
    is( Protobuf::Parser->serialize($f2), $out, q{serialize is idempotent for numeric strings} );
}

done_testing;
