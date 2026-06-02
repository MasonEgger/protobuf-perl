# ABOUTME: Tests for Proto3::Parser::Grammar proto3 restrictions — rejecting
# proto2-only constructs (proto2 syntax, no syntax, required, group, scalar
# defaults) while accepting the proto3 `optional` keyword (spec §4.4).
use v5.38;
use strict;
use warnings;
use Test::More;

use Proto3::Parser::Grammar;
use Proto3::Exception;

# Helper: parse proto3 source into a Proto3::Schema::File.
sub parse ($src, $name = 'test.proto') {
    return Proto3::Parser::Grammar->new(
        source    => $src,
        file_name => $name,
    )->parse;
}

# Helper: run $code and return the exception it throws (or undef).
sub exception_from ($code) {
    my $err;
    {
        local $@;
        eval { $code->(); 1 } or $err = $@;
    }
    return $err;
}

# --- 21.1 syntax = "proto2"; -> UnsupportedSyntax (T-parse-12) -------------

subtest 'syntax = "proto2" raises UnsupportedSyntax' => sub {
    my $src = <<'PROTO';
syntax = "proto2";
message M { int32 x = 1; }
PROTO
    my $err = exception_from( sub { parse($src) } );
    ok $err, 'an exception was raised';
    isa_ok $err, 'Proto3::Exception::Parser::UnsupportedSyntax',
        'proto2 raises UnsupportedSyntax';
    like "$err", qr/proto2/, 'message names the offending syntax value';
    is $err->line, 1, 'line points at the syntax statement';
    ok defined $err->column, 'column is set';
};

# --- 21.2 no syntax declaration -> UnsupportedSyntax ----------------------

subtest 'missing syntax declaration raises UnsupportedSyntax' => sub {
    my $src = <<'PROTO';
message M { int32 x = 1; }
PROTO
    my $err = exception_from( sub { parse($src) } );
    ok $err, 'an exception was raised';
    isa_ok $err, 'Proto3::Exception::Parser::UnsupportedSyntax',
        'missing syntax raises UnsupportedSyntax';
    like "$err", qr/syntax/, 'message mentions the required syntax statement';
};

# --- 21.3 required -> Parser names the keyword (T-parse-13) ----------------

subtest 'required field raises Parser naming the keyword' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M { required string foo = 1; }
PROTO
    my $err = exception_from( sub { parse($src) } );
    ok $err, 'an exception was raised';
    isa_ok $err, 'Proto3::Exception::Parser',
        'required raises a Parser error';
    ok !$err->isa('Proto3::Exception::Parser::UnsupportedSyntax'),
        'required is a plain Parser error, not UnsupportedSyntax';
    like "$err", qr/\brequired\b/, 'message names the `required` keyword';
    is $err->line, 2, 'line points at the field';
    ok defined $err->column, 'column is set';
};

# --- 21.4 group -> Parser error -------------------------------------------

subtest 'group syntax raises Parser naming the keyword' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M {
  group G = 1 {
    int32 x = 2;
  }
}
PROTO
    my $err = exception_from( sub { parse($src) } );
    ok $err, 'an exception was raised';
    isa_ok $err, 'Proto3::Exception::Parser', 'group raises a Parser error';
    like "$err", qr/\bgroup\b/, 'message names the `group` keyword';
    is $err->line, 3, 'line points at the group declaration';
};

# --- 21.5 scalar default expression -> Parser error -----------------------

subtest 'scalar field default expression raises Parser' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M { int32 x = 1 [default = 5]; }
PROTO
    my $err = exception_from( sub { parse($src) } );
    ok $err, 'an exception was raised';
    isa_ok $err, 'Proto3::Exception::Parser',
        'a scalar default raises a Parser error';
    like "$err", qr/\bdefault\b/, 'message names the forbidden `default` option';
    is $err->line, 2, 'line points at the field';
};

# --- 21.6 optional keyword IS accepted (proto3 explicit presence) ----------

subtest 'optional keyword is accepted (explicit presence)' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M { optional int32 x = 1; }
PROTO
    my $err = exception_from( sub { parse($src) } );
    is $err, undef, 'optional does NOT raise';

    my $file  = parse($src);
    my $field = $file->messages->[0]->fields->[0];
    is $field->label, 'optional', 'optional field carries the optional label';
};

done_testing;
