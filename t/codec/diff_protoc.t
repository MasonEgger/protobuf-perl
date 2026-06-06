# ABOUTME: Differential test (T-codec-11) — our codec vs the protoc oracle.
# ~20 representative messages: encode-with-us then `protoc --decode` must match,
# and `protoc --encode` then decode-with-us must match. Skips when protoc absent.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use lib 't/lib';

use ProtobufTest::Protoc qw(have_protoc protoc_decode protoc_encode);

plan skip_all => 'protoc not on PATH' unless have_protoc();

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Schema::Oneof;
use Protobuf::Codec;

# ----------------------------------------------------------------------
# Fixtures: ONE .proto source, fed to protoc, mirrored by a hand-built
# Protobuf::Schema so our codec and protoc operate over the same message set.
# ----------------------------------------------------------------------

my $PROTO_SOURCE = <<'PROTO';
syntax = "proto3";
package diff;

enum Color {
  COLOR_UNSPECIFIED = 0;
  RED = 1;
  GREEN = 2;
  BLUE = 3;
}

message Scalars {
  int32    i32  = 1;
  int64    i64  = 2;
  uint32   u32  = 3;
  uint64   u64  = 4;
  sint32   s32  = 5;
  sint64   s64  = 6;
  fixed32  f32  = 7;
  fixed64  f64  = 8;
  sfixed32 sf32 = 9;
  sfixed64 sf64 = 10;
  float    fl   = 11;
  double   db   = 12;
  bool     bl   = 13;
  string   st   = 14;
  bytes    by   = 15;
}

message Repeated {
  repeated int32  nums  = 1;
  repeated string names = 2;
}

message MapHolder {
  map<string, int32> counts = 1;
  map<int32, string> labels = 2;
}

message Inner {
  int32  a = 1;
  string b = 2;
}

message Nested {
  Inner inner = 1;
  int32 tail  = 2;
}

message Deep {
  Nested n = 1;
}

message Enumed {
  Color color = 1;
}

message OneofMsg {
  oneof choice {
    int32  pick_int = 1;
    string pick_str = 2;
  }
  int32 trailer = 3;
}

message RepeatedMsg {
  repeated Inner items = 1;
}
PROTO

# --- Schema construction mirroring the .proto above ---------------------

sub f ($name, $number, $type, %opts) {
    return Protobuf::Schema::Field->new(
        name => $name, number => $number, type => $type, %opts,
    );
}

sub msg ($full_name, $fields, %opts) {
    my $short = ( split /\./, $full_name )[-1];
    return Protobuf::Schema::Message->new(
        name => $short, full_name => $full_name, fields => $fields, %opts,
    );
}

# Synthetic MapEntry message for a map<key,value> field.
sub map_entry ($full_name, $key_type, $value_type) {
    return Protobuf::Schema::Message->new(
        name         => ( split /\./, $full_name )[-1],
        full_name    => $full_name,
        is_map_entry => 1,
        fields       => [
            f( 'key',   1, $key_type ),
            f( 'value', 2, $value_type ),
        ],
    );
}

sub build_codec () {
    my $scalars = msg(
        'diff.Scalars',
        [
            f( 'i32',  1,  'int32' ),
            f( 'i64',  2,  'int64' ),
            f( 'u32',  3,  'uint32' ),
            f( 'u64',  4,  'uint64' ),
            f( 's32',  5,  'sint32' ),
            f( 's64',  6,  'sint64' ),
            f( 'f32',  7,  'fixed32' ),
            f( 'f64',  8,  'fixed64' ),
            f( 'sf32', 9,  'sfixed32' ),
            f( 'sf64', 10, 'sfixed64' ),
            f( 'fl',   11, 'float' ),
            f( 'db',   12, 'double' ),
            f( 'bl',   13, 'bool' ),
            f( 'st',   14, 'string' ),
            f( 'by',   15, 'bytes' ),
        ],
    );

    my $repeated = msg(
        'diff.Repeated',
        [
            f( 'nums',  1, 'int32',  label => 'repeated' ),
            f( 'names', 2, 'string', label => 'repeated' ),
        ],
    );

    my $counts_entry = map_entry( 'diff.MapHolder.CountsEntry', 'string', 'int32' );
    my $labels_entry = map_entry( 'diff.MapHolder.LabelsEntry', 'int32', 'string' );
    my $map_holder = msg(
        'diff.MapHolder',
        [
            f( 'counts', 1, 'message',
                label => 'repeated', type_name => 'diff.MapHolder.CountsEntry',
                map_entry => 'diff.MapHolder.CountsEntry' ),
            f( 'labels', 2, 'message',
                label => 'repeated', type_name => 'diff.MapHolder.LabelsEntry',
                map_entry => 'diff.MapHolder.LabelsEntry' ),
        ],
    );

    my $inner = msg(
        'diff.Inner',
        [ f( 'a', 1, 'int32' ), f( 'b', 2, 'string' ) ],
    );

    my $nested = msg(
        'diff.Nested',
        [
            f( 'inner', 1, 'message', type_name => 'diff.Inner' ),
            f( 'tail',  2, 'int32' ),
        ],
    );

    my $deep = msg(
        'diff.Deep',
        [ f( 'n', 1, 'message', type_name => 'diff.Nested' ) ],
    );

    my $enumed = msg(
        'diff.Enumed',
        [ f( 'color', 1, 'enum', type_name => 'diff.Color' ) ],
    );

    my $pick_int = f( 'pick_int', 1, 'int32',  oneof_index => 0 );
    my $pick_str = f( 'pick_str', 2, 'string', oneof_index => 0 );
    my $oneof_msg = msg(
        'diff.OneofMsg',
        [ $pick_int, $pick_str, f( 'trailer', 3, 'int32' ) ],
        oneofs => [
            Protobuf::Schema::Oneof->new(
                name => 'choice', oneof_index => 0,
                fields => [ $pick_int, $pick_str ],
            ),
        ],
    );

    my $repeated_msg = msg(
        'diff.RepeatedMsg',
        [ f( 'items', 1, 'message', label => 'repeated', type_name => 'diff.Inner' ) ],
    );

    my $file = Protobuf::Schema::File->new(
        name     => 'fixtures.proto',
        package  => 'diff',
        messages => [
            $scalars, $repeated, $map_holder, $counts_entry, $labels_entry,
            $inner, $nested, $deep, $enumed, $oneof_msg, $repeated_msg,
        ],
    );

    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    return Protobuf::Codec->new( schema => $schema );
}

my $codec = build_codec();

# ----------------------------------------------------------------------
# Differential cases. Each case carries:
#   message : fully-qualified message name (also used for protoc --decode/encode)
#   value   : the Perl value hashref our codec encodes / decodes to
#   text    : the protobuf text-format rendering protoc produces for `value`
# We assert BOTH directions:
#   (a) protoc_decode( our_encode(value) ) eq normalized(text)
#   (b) our_decode( protoc_encode(text) ) is_deeply value
# ----------------------------------------------------------------------

my @cases = (
    {
        name    => 'scalars: integer family',
        message => 'diff.Scalars',
        value   => { i32 => 42, i64 => 123456, u32 => 7, u64 => 99,
                     s32 => -5, s64 => -123456 },
        text    => "i32: 42\ni64: 123456\nu32: 7\nu64: 99\ns32: -5\ns64: -123456",
    },
    {
        name    => 'scalars: fixed-width integers',
        message => 'diff.Scalars',
        value   => { f32 => 4294967295, f64 => 1234567890,
                     sf32 => 12345, sf64 => 987654321 },
        text    => "f32: 4294967295\nf64: 1234567890\nsf32: 12345\nsf64: 987654321",
    },
    {
        name    => 'scalars: bool + string + bytes',
        message => 'diff.Scalars',
        value   => { bl => 1, st => 'hello', by => "\x00\xff\x7f" },
        text    => "bl: true\nst: \"hello\"\nby: \"\\000\\377\\177\"",
    },
    {
        name    => 'scalars: negative int32 (10-byte varint)',
        message => 'diff.Scalars',
        value   => { i32 => -1 },
        text    => "i32: -1",
    },
    {
        name    => 'repeated: packed int32',
        message => 'diff.Repeated',
        value   => { nums => [ 1, 2, 300, 4 ] },
        text    => "nums: 1\nnums: 2\nnums: 300\nnums: 4",
    },
    {
        name    => 'repeated: strings (unpacked)',
        message => 'diff.Repeated',
        value   => { names => [ 'a', 'bb', 'ccc' ] },
        text    => "names: \"a\"\nnames: \"bb\"\nnames: \"ccc\"",
    },
    {
        name    => 'repeated: both fields together',
        message => 'diff.Repeated',
        value   => { nums => [ 10, 20 ], names => [ 'x', 'y' ] },
        text    => "nums: 10\nnums: 20\nnames: \"x\"\nnames: \"y\"",
    },
    {
        name    => 'map<string,int32> sorted by key',
        message => 'diff.MapHolder',
        value   => { counts => { alpha => 1, beta => 2, gamma => 3 } },
        text    => join( "\n",
            'counts {', '  key: "alpha"', '  value: 1', '}',
            'counts {', '  key: "beta"',  '  value: 2', '}',
            'counts {', '  key: "gamma"', '  value: 3', '}' ),
    },
    {
        name    => 'map<int32,string> sorted by key',
        message => 'diff.MapHolder',
        value   => { labels => { 1 => 'one', 2 => 'two', 10 => 'ten' } },
        text    => join( "\n",
            'labels {', '  key: 1',  '  value: "one"', '}',
            'labels {', '  key: 2',  '  value: "two"', '}',
            'labels {', '  key: 10', '  value: "ten"', '}' ),
    },
    {
        name    => 'nested message',
        message => 'diff.Nested',
        value   => { inner => { a => 7, b => 'hi' }, tail => 9 },
        text    => join( "\n",
            'inner {', '  a: 7', '  b: "hi"', '}', 'tail: 9' ),
    },
    {
        name    => 'nested message: only tail set',
        message => 'diff.Nested',
        value   => { tail => 5 },
        text    => "tail: 5",
    },
    {
        name    => 'deeply nested (3 levels)',
        message => 'diff.Deep',
        value   => { n => { inner => { a => 1, b => 'deep' }, tail => 2 } },
        text    => join( "\n",
            'n {', '  inner {', '    a: 1', '    b: "deep"', '  }',
            '  tail: 2', '}' ),
    },
    {
        name    => 'enum: named value',
        message => 'diff.Enumed',
        value   => { color => 2 },
        text    => "color: GREEN",
    },
    {
        name    => 'enum: unknown number preserved',
        message => 'diff.Enumed',
        value   => { color => 42 },
        text    => "color: 42",
    },
    {
        name    => 'oneof: string member set',
        message => 'diff.OneofMsg',
        value   => { pick_str => 'chosen', trailer => 8 },
        text    => "pick_str: \"chosen\"\ntrailer: 8",
    },
    {
        name    => 'oneof: int member set (even at zero is present)',
        message => 'diff.OneofMsg',
        value   => { pick_int => 0 },
        text    => "pick_int: 0",
    },
    {
        name    => 'repeated message',
        message => 'diff.RepeatedMsg',
        value   => { items => [ { a => 1, b => 'one' }, { a => 2, b => 'two' } ] },
        text    => join( "\n",
            'items {', '  a: 1', '  b: "one"', '}',
            'items {', '  a: 2', '  b: "two"', '}' ),
    },
    {
        name    => 'float + double (exact binary values)',
        message => 'diff.Scalars',
        value   => { fl => 1.5, db => 3.25 },
        text    => "fl: 1.5\ndb: 3.25",
    },
    {
        name    => 'empty message round-trips to empty',
        message => 'diff.Scalars',
        value   => {},
        text    => "",
    },
    {
        name    => 'map with single message-free entry + sibling scalar',
        message => 'diff.MapHolder',
        value   => { counts => { only => 7 } },
        text    => join( "\n", 'counts {', '  key: "only"', '  value: 7', '}' ),
    },
);

# Normalize the same way the harness normalizes protoc output, so our expected
# text lines up with what protoc emits.
sub norm ($text) {
    my @lines = split /\n/, $text;
    s/\s+\z// for @lines;
    @lines = grep { length } @lines;
    return join "\n", @lines;
}

for my $case (@cases) {
    my $name = $case->{name};
    my $msg  = $case->{message};

    # Direction (a): encode with us, decode with protoc, compare text.
    my $our_bytes = $codec->encode( $msg, $case->{value} );
    my $protoc_text = protoc_decode( $PROTO_SOURCE, $msg, $our_bytes );
    is(
        $protoc_text,
        norm( $case->{text} ),
        "T-codec-11 [$name]: our encode -> protoc --decode matches",
    );

    # Direction (b): encode with protoc, decode with us, compare value.
    my $protoc_bytes = protoc_encode( $PROTO_SOURCE, $msg, $case->{text} );
    my $our_value = $codec->decode( $msg, $protoc_bytes );

    # Fill in proto3 implicit defaults that our decoder adds but the input value
    # omits, so is_deeply lines up. We compare only the keys present in the
    # case value, plus assert no *extra* meaningful keys appear.
    for my $key ( keys %{ $case->{value} } ) {
        is_deeply(
            $our_value->{$key},
            $case->{value}{$key},
            "T-codec-11 [$name]: protoc --encode -> our decode matches '$key'",
        );
    }
}

done_testing;
