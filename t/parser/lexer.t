# ABOUTME: Tests for Protobuf::Parser::Lexer — the .proto tokenizer (spec §4.4).
# Covers token kinds, string escapes, keyword vs identifier, punctuation,
# comment discarding, line/col positions, and unterminated-input errors.
use v5.38;
use strict;
use warnings;
use utf8;
use Test::More;

use Protobuf::Parser::Lexer;
use Protobuf::Exception;

# Helper: tokenize source and return the arrayref of token hashes. Each token is
# { type => ..., value => ..., line => ..., col => ... }.
sub lex ($src) {
    return Protobuf::Parser::Lexer->new( source => $src )->tokenize;
}

# Helper: tokens reduced to [type, value] pairs, dropping positions, for compact
# structural assertions.
sub pairs ($src) {
    return [ map { [ $_->{type}, $_->{value} ] } @{ lex($src) } ];
}

# --- 16.1 identifiers / fullIdent / int / float / bool --------------------

subtest 'identifiers and fullIdent' => sub {
    is_deeply pairs('foo'), [ [ 'ident', 'foo' ] ], 'bare identifier';
    is_deeply pairs('foo.bar.Baz'), [ [ 'fullident', 'foo.bar.Baz' ] ],
        'dotted name is a single fullIdent token';
    is_deeply pairs('_underscore99'), [ [ 'ident', '_underscore99' ] ],
        'identifier may start with underscore and contain digits';
};

subtest 'integer literals (dec, hex, oct)' => sub {
    is_deeply pairs('42'), [ [ 'int', 42 ] ], 'decimal int';
    is_deeply pairs('0'), [ [ 'int', 0 ] ], 'zero';
    is_deeply pairs('0x1F'), [ [ 'int', 31 ] ], 'hex int decoded to value';
    is_deeply pairs('0XefAB'), [ [ 'int', 0xefAB ] ], 'hex case-insensitive';
    is_deeply pairs('0755'), [ [ 'int', 493 ] ], 'octal int decoded to value';
    is_deeply pairs('07'), [ [ 'int', 7 ] ], 'small octal';
};

subtest 'float literals' => sub {
    is_deeply pairs('1.5'), [ [ 'float', 1.5 ] ], 'simple float';
    is_deeply pairs('0.0'), [ [ 'float', 0.0 ] ], 'zero float';
    is_deeply pairs('1e3'), [ [ 'float', 1000 ] ], 'exponent float';
    is_deeply pairs('2.5e-2'), [ [ 'float', 0.025 ] ], 'signed exponent';
    is_deeply pairs('.5'), [ [ 'float', 0.5 ] ], 'leading-dot float';
};

subtest 'bool literals' => sub {
    is_deeply pairs('true'), [ [ 'bool', 1 ] ], 'true';
    is_deeply pairs('false'), [ [ 'bool', 0 ] ], 'false';
};

# --- 16.2 string literals + escape decoding -------------------------------

subtest 'string literals and escapes' => sub {
    is_deeply pairs(q{"hello"}), [ [ 'string', 'hello' ] ],
        'double-quoted string';
    is_deeply pairs(q{'world'}), [ [ 'string', 'world' ] ],
        'single-quoted string';
    is_deeply pairs(q{"a\nb"}), [ [ 'string', "a\nb" ] ],
        'newline escape decoded';
    is_deeply pairs(q{"a\tb"}), [ [ 'string', "a\tb" ] ],
        'tab escape decoded';
    is_deeply pairs(q{"a\"b"}), [ [ 'string', q{a"b} ] ],
        'escaped double quote inside double-quoted string';
    # Proto source "a\\b" (backslash-backslash) decodes to a single backslash.
    is_deeply pairs(q{"a\\\\b"}), [ [ 'string', 'a\\b' ] ],
        'escaped backslash decoded';

    my $hex = lex(q{"\x41\x42"});
    is $hex->[0]{value}, 'AB', 'hex escape \xNN -> bytes';

    my $oct = lex(q{"\101\102"});
    is $oct->[0]{value}, 'AB', 'octal escape \NNN -> bytes';
};

# --- 16.3 keyword vs identifier -------------------------------------------

subtest 'keyword vs identifier' => sub {
    is_deeply pairs('message'), [ [ 'keyword', 'message' ] ],
        q{'message' is a keyword token};
    is_deeply pairs('messages'), [ [ 'ident', 'messages' ] ],
        q{'messages' is an identifier, not a keyword};
    is_deeply pairs('int32'), [ [ 'keyword', 'int32' ] ],
        'scalar type name is a keyword';
    is_deeply pairs('repeated'), [ [ 'keyword', 'repeated' ] ],
        'label is a keyword';
};

# --- 16.4 punctuation -----------------------------------------------------

subtest 'punctuation tokens' => sub {
    is_deeply pairs('{ } ( ) [ ] = , ; < > .'),
        [
        [ 'punct', '{' ], [ 'punct', '}' ],
        [ 'punct', '(' ], [ 'punct', ')' ],
        [ 'punct', '[' ], [ 'punct', ']' ],
        [ 'punct', '=' ], [ 'punct', ',' ],
        [ 'punct', ';' ], [ 'punct', '<' ],
        [ 'punct', '>' ], [ 'punct', '.' ],
        ],
        'each punctuation mark is its own token';
};

# --- 16.5 comments discarded ----------------------------------------------

subtest 'comments discarded' => sub {
    is_deeply pairs("foo // line comment\nbar"),
        [ [ 'ident', 'foo' ], [ 'ident', 'bar' ] ],
        'line comment dropped';
    is_deeply pairs('foo /* block comment */ bar'),
        [ [ 'ident', 'foo' ], [ 'ident', 'bar' ] ],
        'block comment dropped';
    is_deeply pairs("a /* multi\nline\nblock */ b"),
        [ [ 'ident', 'a' ], [ 'ident', 'b' ] ],
        'multi-line block comment dropped';
};

# --- 16.6 tokens carry line + col -----------------------------------------

subtest 'line and column positions' => sub {
    # Columns are 1-based; lines are 1-based.
    my $toks = lex("message Foo {\n  int32 x = 1;\n}");

    is $toks->[0]{line}, 1, 'message on line 1';
    is $toks->[0]{col},  1, 'message at col 1';

    is $toks->[1]{value}, 'Foo', 'second token is Foo';
    is $toks->[1]{col},   9,     'Foo at col 9';

    # The int32 keyword starts the second line at col 3 (two leading spaces).
    my ($int32) = grep { $_->{value} eq 'int32' } @{$toks};
    is $int32->{line}, 2, 'int32 on line 2';
    is $int32->{col},  3, 'int32 at col 3';
};

# --- 16.7 unterminated string / block comment -----------------------------

subtest 'unterminated string raises Parser with position' => sub {
    my $err;
    eval { lex(qq{"never closed}); 1 } or $err = $@;
    ok $err, 'died on unterminated string';
    isa_ok $err, 'Protobuf::Exception::Parser', 'typed parser error';
    is $err->line, 1, 'error carries line';
    ok defined $err->column, 'error carries column';
};

subtest 'unterminated block comment raises Parser with position' => sub {
    my $err;
    eval { lex("foo /* never closed"); 1 } or $err = $@;
    ok $err, 'died on unterminated block comment';
    isa_ok $err, 'Protobuf::Exception::Parser', 'typed parser error';
    is $err->line, 1, 'error carries line';
    ok defined $err->column, 'error carries column';
};

done_testing;
