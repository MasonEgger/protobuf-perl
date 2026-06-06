# ABOUTME: JSON differential test (T-json-7) — our JSON encode/decode bridged
# through the protoc binary oracle. protoc 3.21.12 has no JSON CLI, so protoc's
# binary wire format is the ground truth: a message authored by protoc, taken
# through our encode_json/decode_json round-trip, must re-encode to bytes protoc
# reads back to the identical canonical text. Skips when protoc is absent.
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
use Protobuf::Schema::Enum;
use Protobuf::Schema::Oneof;
use Protobuf::Codec;

# ----------------------------------------------------------------------
# ONE .proto source fed to protoc, mirrored by a hand-built Protobuf::Schema
# so our codec and protoc operate over the same message set. (Mirrors the
# codec differential's fixture set; representative of the JSON mapping.)
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

sub map_entry ($full_name, $key_type, $value_type) {
    return Protobuf::Schema::Message->new(
        name         => ( split /\./, $full_name )[-1],
        full_name    => $full_name,
        is_map_entry => 1,
        fields       => [ f( 'key', 1, $key_type ), f( 'value', 2, $value_type ) ],
    );
}

sub build_codec () {
    my $scalars = msg(
        'diff.Scalars',
        [
            f( 'i32',  1,  'int32' ),   f( 'i64',  2,  'int64' ),
            f( 'u32',  3,  'uint32' ),  f( 'u64',  4,  'uint64' ),
            f( 's32',  5,  'sint32' ),  f( 's64',  6,  'sint64' ),
            f( 'f32',  7,  'fixed32' ), f( 'f64',  8,  'fixed64' ),
            f( 'sf32', 9,  'sfixed32' ),f( 'sf64', 10, 'sfixed64' ),
            f( 'fl',   11, 'float' ),   f( 'db',   12, 'double' ),
            f( 'bl',   13, 'bool' ),    f( 'st',   14, 'string' ),
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
    my $inner = msg( 'diff.Inner', [ f( 'a', 1, 'int32' ), f( 'b', 2, 'string' ) ] );
    my $nested = msg(
        'diff.Nested',
        [ f( 'inner', 1, 'message', type_name => 'diff.Inner' ), f( 'tail', 2, 'int32' ) ],
    );
    my $enumed = msg( 'diff.Enumed', [ f( 'color', 1, 'enum', type_name => 'diff.Color' ) ] );
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

    my $color = Protobuf::Schema::Enum->new(
        name      => 'Color',
        full_name => 'diff.Color',
        values    => [
            { name => 'COLOR_UNSPECIFIED', number => 0 },
            { name => 'RED',   number => 1 },
            { name => 'GREEN', number => 2 },
            { name => 'BLUE',  number => 3 },
        ],
    );

    my $file = Protobuf::Schema::File->new(
        name     => 'fixtures.proto',
        package  => 'diff',
        messages => [
            $scalars, $repeated, $map_holder, $counts_entry, $labels_entry,
            $inner, $nested, $enumed, $oneof_msg, $repeated_msg,
        ],
        enums => [$color],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    return Protobuf::Codec->new( schema => $schema );
}

my $codec = build_codec();

# ----------------------------------------------------------------------
# Differential cases. protoc authors the canonical wire bytes from text;
# we run those bytes through our full JSON round-trip and back to wire,
# then ask protoc to render the result. Agreement on the canonical text
# proves our JSON encode AND decode preserve the message faithfully.
# ----------------------------------------------------------------------

my @cases = (
    {
        name    => 'scalars: integer family (incl. 64-bit-as-string)',
        message => 'diff.Scalars',
        text    => "i32: 42\ni64: 123456\nu32: 7\nu64: 99\ns32: -5\ns64: -123456",
    },
    {
        name    => 'scalars: fixed-width integers',
        message => 'diff.Scalars',
        text    => "f32: 4294967295\nf64: 1234567890\nsf32: 12345\nsf64: 987654321",
    },
    {
        name    => 'scalars: bool + string + bytes',
        message => 'diff.Scalars',
        text    => "bl: true\nst: \"hello\"\nby: \"\\000\\377\\177\"",
    },
    {
        name    => 'scalars: negative int32',
        message => 'diff.Scalars',
        text    => "i32: -1",
    },
    {
        name    => 'scalars: float + double',
        message => 'diff.Scalars',
        text    => "fl: 1.5\ndb: 3.25",
    },
    {
        name    => 'repeated: packed int32',
        message => 'diff.Repeated',
        text    => "nums: 1\nnums: 2\nnums: 300\nnums: 4",
    },
    {
        name    => 'repeated: strings',
        message => 'diff.Repeated',
        text    => "names: \"a\"\nnames: \"bb\"\nnames: \"ccc\"",
    },
    {
        name    => 'map<string,int32>',
        message => 'diff.MapHolder',
        text    => join( "\n",
            'counts {', '  key: "alpha"', '  value: 1', '}',
            'counts {', '  key: "beta"',  '  value: 2', '}',
            'counts {', '  key: "gamma"', '  value: 3', '}' ),
    },
    {
        name    => 'map<int32,string>',
        message => 'diff.MapHolder',
        text    => join( "\n",
            'labels {', '  key: 1',  '  value: "one"', '}',
            'labels {', '  key: 2',  '  value: "two"', '}',
            'labels {', '  key: 10', '  value: "ten"', '}' ),
    },
    {
        name    => 'nested message',
        message => 'diff.Nested',
        text    => join( "\n", 'inner {', '  a: 7', '  b: "hi"', '}', 'tail: 9' ),
    },
    {
        name    => 'enum: named value',
        message => 'diff.Enumed',
        text    => "color: GREEN",
    },
    {
        name    => 'oneof: string member set',
        message => 'diff.OneofMsg',
        text    => "pick_str: \"chosen\"\ntrailer: 8",
    },
    {
        name    => 'repeated message',
        message => 'diff.RepeatedMsg',
        text    => join( "\n",
            'items {', '  a: 1', '  b: "one"', '}',
            'items {', '  a: 2', '  b: "two"', '}' ),
    },
);

sub norm ($text) {
    my @lines = split /\n/, $text;
    s/\s+\z// for @lines;
    @lines = grep { length } @lines;
    return join "\n", @lines;
}

for my $case (@cases) {
    my $name = $case->{name};
    my $msg  = $case->{message};

    # protoc authors the canonical wire bytes for this message.
    my $protoc_bytes = protoc_encode( $PROTO_SOURCE, $msg, $case->{text} );

    # Our codec reads them, we emit JSON, then read our JSON back, then
    # re-encode to wire — exercising encode_json AND decode_json end to end.
    my $value     = $codec->decode( $msg, $protoc_bytes );
    my $json      = $codec->encode_json( $msg, $value );
    my $reparsed  = $codec->decode_json( $msg, $json );
    my $our_bytes = $codec->encode( $msg, $reparsed );

    # protoc renders the round-tripped bytes; it must match the original text.
    my $protoc_text = protoc_decode( $PROTO_SOURCE, $msg, $our_bytes );
    is(
        $protoc_text,
        norm( $case->{text} ),
        "T-json-7 [$name]: protoc -> our JSON round-trip -> protoc agrees",
    );
}

done_testing;
