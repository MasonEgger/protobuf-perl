# ABOUTME: T-parse-1 — the complete serializer round-trips a non-trivial proto
# (enums, services, oneofs, maps, options, reserved, nested, extend) (B-015/B-018).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;
use Protobuf::Schema;

my $src = <<'PROTO';
syntax = "proto3";
package demo;
import "google/protobuf/descriptor.proto";
option java_package = "com.demo";
enum Color { UNKNOWN = 0; RED = 1; }
message Outer {
  option deprecated = true;
  int32 id = 1 [json_name = "ID"];
  repeated string tags = 2;
  Color color = 3;
  map<string, int32> counts = 4;
  oneof choice { string name = 5; int32 num = 6; }
  reserved 7, 9 to 11;
  reserved "old_field";
  message Inner { int32 x = 1; }
  enum Status { OK = 0; }
}
service Svc { rpc Do (Outer) returns (Outer); }
extend google.protobuf.MessageOptions { string my_opt = 50000; }
PROTO

my $parser = Protobuf::Parser->new;

my $file1 = $parser->parse_string( 'demo.proto', $src );
my $text1 = Protobuf::Parser->serialize($file1);

my $file2 = $parser->parse_string( 'demo.proto', $text1 );
my $text2 = Protobuf::Parser->serialize($file2);

# Idempotence: serialize(parse(serialize(x))) == serialize(x). Proves the
# serializer emits everything the parser captures (nothing is dropped on the
# second cycle).
is( $text2, $text1, 'serialize is idempotent across a parse cycle' );

# Completeness: the re-parsed schema still carries every construct.
my $schema = Protobuf::Schema->new;
$schema->add_file($file2);

ok( $schema->enum('demo.Color'), 'file-level enum survives round-trip' );
my $outer = $schema->message('demo.Outer');
ok( $outer, 'message survives round-trip' );

my ($counts) = grep { $_->name eq 'counts' } @{ $outer->fields };
ok( $counts && $counts->is_map, 'map field survives as a map' );

is( scalar @{ $outer->oneofs },          1, 'oneof survives' );
is( scalar @{ $outer->oneofs->[0]->fields }, 2, '  with both members' );

my ($id) = grep { $_->name eq 'id' } @{ $outer->fields };
is( $id->options->{json_name}, 'ID', 'field option survives' );

ok( ( grep { $_->name eq 'Inner' } @{ $outer->nested_messages } ),
    'nested message survives' );
ok( ( grep { $_->name eq 'Status' } @{ $outer->nested_enums } ),
    'nested enum survives' );
is( scalar @{ $outer->reserved_numbers }, 2, 'reserved numbers survive' );
is_deeply( $outer->reserved_names, ['old_field'], 'reserved names survive' );

ok( $schema->service('demo.Svc'), 'service survives round-trip' );
is( scalar @{ $file2->extensions }, 1, 'extend block survives' );
is( $file2->extensions->[0]->name, 'my_opt', '  extension field name' );

done_testing;
