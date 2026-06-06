# ABOUTME: Tests for Protobuf::Parser::Grammar extended body constructs — nested
# messages, enums (allow_alias), oneof, map desugaring, reserved, comments (§4.4).
use v5.38;
use strict;
use warnings;
use Test::More;

use Protobuf::Parser::Grammar;
use Protobuf::Exception;

# Helper: parse proto3 source into a Protobuf::Schema::File.
sub parse ($src, $name = 'test.proto') {
    return Protobuf::Parser::Grammar->new(
        source    => $src,
        file_name => $name,
    )->parse;
}

# Helper: index a message's fields by name -> Schema::Field.
sub fields_by_name ($message) {
    return { map { $_->name => $_ } @{ $message->fields } };
}

# Helper: index a list of messages by simple name.
sub messages_by_name ($list) {
    return { map { $_->name => $_ } @$list };
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

# --- 18.1 nested messages get correct dotted full_name (T-parse-3) ---------

subtest 'nested messages have correct dotted full_name' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package a.b;
message Outer {
  int32 x = 1;
  message Inner {
    int32 y = 1;
    message Deepest {
      int32 z = 1;
    }
  }
}
PROTO
    my $file  = parse($src);
    my $outer = $file->messages->[0];
    is $outer->full_name, 'a.b.Outer', 'outer full_name includes package';

    my $nested = messages_by_name( $outer->nested_messages );
    my $inner  = $nested->{Inner};
    isa_ok $inner, 'Protobuf::Schema::Message', 'Inner is a Schema::Message';
    is $inner->name,      'Inner',         'inner name';
    is $inner->full_name, 'a.b.Outer.Inner', 'inner full_name nests under outer';

    my $deepest =
        messages_by_name( $inner->nested_messages )->{Deepest};
    is $deepest->full_name, 'a.b.Outer.Inner.Deepest',
        'deepest full_name nests three levels';
};

# --- 18.2 enum allow_alias accepts/rejects duplicate numbers (T-parse-4) ---

subtest 'enum allow_alias accepts duplicates; otherwise raises' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package e;
enum Color {
  option allow_alias = true;
  UNKNOWN = 0;
  RED = 1;
  CRIMSON = 1;
}
PROTO
    my $file = parse($src);
    my $enum = $file->enums->[0];
    isa_ok $enum, 'Protobuf::Schema::Enum', 'top-level enum parsed';
    is $enum->name,        'Color',  'enum name';
    is $enum->full_name,   'e.Color', 'enum full_name includes package';
    ok $enum->allow_alias, 'allow_alias captured as true';
    is scalar @{ $enum->values }, 3, 'three enum values';
    is $enum->values->[2]{name},   'CRIMSON', 'alias value name';
    is $enum->values->[2]{number}, 1,         'alias shares number 1';

    my $dup = <<'PROTO';
syntax = "proto3";
enum Bad {
  ZERO = 0;
  A = 1;
  B = 1;
}
PROTO
    my $err = exception_from( sub { parse($dup) } );
    isa_ok $err, 'Protobuf::Exception::Schema',
        'duplicate enum number without allow_alias raises';
};

subtest 'nested enum has dotted full_name' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package p;
message Holder {
  enum State {
    OFF = 0;
    ON = 1;
  }
  State state = 1;
}
PROTO
    my $holder = parse($src)->messages->[0];
    my $enum   = $holder->nested_enums->[0];
    isa_ok $enum, 'Protobuf::Schema::Enum', 'nested enum parsed';
    is $enum->full_name, 'p.Holder.State', 'nested enum full_name';
};

# --- 18.3 oneof members get oneof_index; Schema::Oneof recorded (T-parse-5) -

subtest 'oneof members get oneof_index and a Schema::Oneof is recorded' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package o;
message M {
  int32 id = 1;
  oneof choice {
    string name = 2;
    int32 number = 3;
  }
}
PROTO
    my $msg = parse($src)->messages->[0];

    is scalar @{ $msg->oneofs }, 1, 'one oneof recorded';
    my $oneof = $msg->oneofs->[0];
    isa_ok $oneof, 'Protobuf::Schema::Oneof', 'oneof is a Schema::Oneof';
    is $oneof->name,        'choice', 'oneof name';
    is $oneof->oneof_index, 0,        'oneof_index is 0';

    my $by_name = fields_by_name($msg);
    is $by_name->{id}->oneof_index, undef,
        'non-oneof field has no oneof_index';
    is $by_name->{name}->oneof_index,   0, 'name member has oneof_index 0';
    is $by_name->{number}->oneof_index, 0, 'number member has oneof_index 0';

    is scalar @{ $oneof->fields }, 2, 'oneof records its two member fields';
};

# --- 18.4 map desugars to synthetic MapEntry key=1/value=2 (T-parse-6) -----

subtest 'map desugars to a repeated synthetic MapEntry field' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package m;
message Payload {
  int32 v = 1;
}
message Holder {
  map<string, Payload> attrs = 1;
}
PROTO
    my $file   = parse($src);
    my $holder = messages_by_name( $file->messages )->{Holder};

    # The map field is modeled as a repeated message field.
    my $field = $holder->fields->[0];
    is $field->name,   'attrs', 'map field name';
    is $field->number, 1,       'map field number';
    is $field->label,  'repeated', 'map field is repeated';
    is $field->type,   'message',  'map field type is message';
    ok $field->is_map, 'field reports is_map';

    # The synthetic MapEntry message is nested under Holder.
    my $entry_name = 'm.Holder.AttrsEntry';
    is $field->map_entry, $entry_name, 'map field points at MapEntry full_name';
    is $field->type_name, $entry_name, 'map field type_name is MapEntry';

    my $entry = messages_by_name( $holder->nested_messages )->{AttrsEntry};
    isa_ok $entry, 'Protobuf::Schema::Message', 'AttrsEntry synthesized';
    is $entry->full_name, $entry_name, 'AttrsEntry full_name';
    ok $entry->is_map_entry, 'AttrsEntry flagged is_map_entry';

    my $entry_fields = fields_by_name($entry);
    is $entry_fields->{key}->number,   1,        'key is field 1';
    is $entry_fields->{key}->type,     'string', 'key type is string';
    is $entry_fields->{value}->number, 2,        'value is field 2';
    is $entry_fields->{value}->type,   'message', 'value type is message';
    is $entry_fields->{value}->type_name, 'Payload',
        'value type_name is the map value type';
};

# --- 18.5 reserved numbers (ranges incl. max) + names (T-parse-7) ----------

subtest 'reserved numbers, ranges (incl. max), and names' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
message R {
  reserved 5, 10 to 15, 20 to max;
  reserved "foo", "bar";
  int32 ok = 1;
}
PROTO
    my $msg = parse($src)->messages->[0];

    my $numbers = $msg->reserved_numbers;
    is_deeply $numbers->[0], [ 5,  5 ],         'single number 5 -> [5,5]';
    is_deeply $numbers->[1], [ 10, 15 ],        'range 10 to 15';
    is $numbers->[2][0], 20, 'range 20 lower bound';
    cmp_ok $numbers->[2][1], '>=', 536_870_911,
        'max upper bound is the proto field-number max';

    is_deeply $msg->reserved_names, [ 'foo', 'bar' ],
        'reserved names captured';

    # The real field still parses alongside reserved declarations.
    is $msg->fields->[0]->name, 'ok', 'non-reserved field still present';
};

# --- 18.6 interleaved comments don't break parsing (T-parse-10) ------------

subtest 'comments interleaved inside message and field bodies parse cleanly'
    => sub {
    my $src = <<'PROTO';
syntax = "proto3";
// leading file comment
package c;
message M {
  // a leading field comment
  int32 a = 1; // trailing comment
  /* block
     comment spanning lines */
  string b = 2;
  oneof pick {
    // inside oneof
    int32 c = 3;
  }
}
PROTO
    my $msg     = parse($src)->messages->[0];
    my $by_name = fields_by_name($msg);
    is scalar( keys %$by_name ), 3, 'all three fields parsed past comments';
    is $by_name->{a}->number, 1, 'field a number';
    is $by_name->{b}->number, 2, 'field b number';
    is $by_name->{c}->oneof_index, 0, 'oneof member parsed past comment';
};

done_testing;
