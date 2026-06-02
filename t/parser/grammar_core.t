# ABOUTME: Tests for Proto3::Parser::Grammar core — syntax/package/message and
# all scalar field types, json_name camelCase, labels, and required-syntax (§4.4).
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

# Helper: index a message's fields by name -> Schema::Field.
sub fields_by_name ($message) {
    return { map { $_->name => $_ } @{ $message->fields } };
}

# --- 17.1 syntax + package + one field per scalar type (T-parse-2) ---------

subtest 'syntax, package, message, and all scalar field types' => sub {
    my @scalars = qw(
        double float int32 int64 uint32 uint64
        sint32 sint64 fixed32 fixed64 sfixed32 sfixed64
        bool string bytes
    );
    my $body = '';
    my $n    = 1;
    $body .= "  $_ f_$_ = " . $n++ . ";\n" for @scalars;

    my $src = <<"PROTO";
syntax = "proto3";
package a.b.c;
message Thing {
$body}
PROTO

    my $file = parse($src);
    isa_ok $file, 'Proto3::Schema::File', 'parse returns a Schema::File';
    is $file->syntax,  'proto3', 'syntax is proto3';
    is $file->package, 'a.b.c',  'package captured';

    is scalar @{ $file->messages }, 1, 'one top-level message';
    my $msg = $file->messages->[0];
    isa_ok $msg, 'Proto3::Schema::Message', 'message is a Schema::Message';
    is $msg->name,      'Thing',       'message name';
    is $msg->full_name, 'a.b.c.Thing', 'message full_name includes package';

    my $by_name = fields_by_name($msg);
    is scalar( keys %$by_name ), scalar(@scalars), 'one field per scalar type';

    my $expect = 1;
    for my $type (@scalars) {
        my $field = $by_name->{"f_$type"};
        isa_ok $field, 'Proto3::Schema::Field', "field f_$type";
        is $field->type,   $type,      "f_$type has type $type";
        is $field->number, $expect++,  "f_$type has correct number";
        is $field->label,  'singular', "f_$type is singular";
    }
};

# --- 17.2 json_name camelCase default -------------------------------------

subtest 'json_name defaults to camelCase of the field name' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M {
  string data_blob = 1;
  int32 simple = 2;
  int32 a_b_c_d = 3;
}
PROTO
    my $msg     = parse($src)->messages->[0];
    my $by_name = fields_by_name($msg);
    is $by_name->{data_blob}->json_name, 'dataBlob', 'data_blob -> dataBlob';
    is $by_name->{simple}->json_name,    'simple',   'simple -> simple';
    is $by_name->{a_b_c_d}->json_name,   'aBCD',     'a_b_c_d -> aBCD';
};

# --- 17.3 missing `syntax = "proto3";` first statement raises -------------

subtest 'missing syntax declaration raises Parser error' => sub {
    my $src = <<'PROTO';
package a.b;
message M { int32 x = 1; }
PROTO
    my $err = exception_from(sub { parse($src) });
    isa_ok $err, 'Proto3::Exception::Parser',
        'missing syntax raises a Parser error';
    ok defined $err->line, 'error carries a line number';

    my $wrong = <<'PROTO';
message M { int32 x = 1; }
PROTO
    my $err2 = exception_from(sub { parse($wrong) });
    isa_ok $err2, 'Proto3::Exception::Parser',
        'a non-syntax first statement raises a Parser error';
};

# --- 17.4 field labels: singular / repeated / optional --------------------

subtest 'field labels singular, repeated, and optional' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M {
  int32 bare = 1;
  repeated int32 many = 2;
  optional int32 maybe = 3;
}
PROTO
    my $by_name = fields_by_name( parse($src)->messages->[0] );
    is $by_name->{bare}->label,  'singular', 'bare field is singular';
    is $by_name->{many}->label,  'repeated', 'repeated field is repeated';
    is $by_name->{maybe}->label, 'optional', 'optional field is optional';

    ok !$by_name->{bare}->is_repeated,  'singular field is not repeated';
    ok $by_name->{many}->is_repeated,   'repeated field reports is_repeated';
    ok !$by_name->{maybe}->is_repeated, 'optional field is not repeated';
};

# --- 17.5 field number + name captured; duplicate number delegates --------

subtest 'field number and name captured; duplicate number delegates to Schema'
    => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message M {
  string title = 7;
}
PROTO
    my $field = parse($src)->messages->[0]->fields->[0];
    is $field->name,   'title', 'field name captured';
    is $field->number, 7,       'field number captured';

    my $dup = <<'PROTO';
syntax = "proto3";
message M {
  int32 a = 1;
  int32 b = 1;
}
PROTO
    my $err = exception_from(sub { parse($dup) });
    isa_ok $err, 'Proto3::Exception::Schema::DuplicateField',
        'duplicate field number surfaces the Schema DuplicateField error';
};

# Helper: run $code and return the exception object it throws (or undef).
sub exception_from ($code) {
    my $err;
    {
        local $@;
        eval { $code->(); 1 } or $err = $@;
    }
    return $err;
}

done_testing;
