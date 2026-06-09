# ABOUTME: lexer escape/number/BOM hardening — \u/\U escapes (B-004), unknown
# escape is an error (B-016), malformed float is an error (B-010), BOM (B-006).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;

sub opt_value ($literal) {
    my $src  = qq{syntax = "proto3"; option a = $literal;};
    my $file = Protobuf::Parser->new->parse_string( 't.proto', $src );
    return $file->options->{a};
}

sub lex_fails ($src) {
    return !eval { Protobuf::Parser->new->parse_string( 't.proto', $src ); 1 };
}

# B-004: \u (4 hex) and \U (8 hex) decode to UTF-8 bytes.
is( unpack( 'H*', opt_value(q{"A"}) ),     '41',   'A -> "A"' );
is( unpack( 'H*', opt_value(q{"é"}) ),     'c3a9', 'é -> c3 a9' );
is( unpack( 'H*', opt_value(q{"\U00000041"}) ), '41',   '\U00000041 -> "A"' );
is( unpack( q{H*}, opt_value(q{"\u0041"}) ), q{41},   q{\u0041 -> "A"} );
is( unpack( q{H*}, opt_value(q{"\u00e9"}) ), q{c3a9}, q{\u00e9 -> c3 a9} );
is( unpack( 'H*', opt_value(q{"\U000000e9"}) ), 'c3a9', '\U000000e9 -> c3 a9' );

# Existing escapes still work.
is( opt_value(q{"a\tb"}),                 "a\tb", '\t still decodes' );
is( unpack( 'H*', opt_value(q{"\x41"}) ), '41',   '\x41 still decodes' );

# B-016: an unknown escape is a parse error (no silent backslash drop).
ok( lex_fails(q{syntax = "proto3"; option a = "\z";}),
    'unknown escape \z is rejected' );

# B-010: a malformed float literal is a parse error.
ok( lex_fails(q{syntax = "proto3"; option a = 1e;}),   '1e rejected' );
ok( lex_fails(q{syntax = "proto3"; option a = 1e+;}),  '1e+ rejected' );
ok( lex_fails(q{syntax = "proto3"; option a = 1.5e;}), '1.5e rejected' );

# A well-formed float still lexes.
ok( !lex_fails(q{syntax = "proto3"; option a = 1.5e3;}), '1.5e3 accepted' );

# B-006: a UTF-8 BOM at file start is stripped, not a parse error.
{
    my $src = "\xef\xbb\xbf"
        . qq{syntax = "proto3";\nmessage M { string x = 1; }\n};
    ok( eval { Protobuf::Parser->new->parse_string( 't.proto', $src ); 1 },
        'BOM-prefixed source parses' )
        or diag $@;
}

done_testing;
