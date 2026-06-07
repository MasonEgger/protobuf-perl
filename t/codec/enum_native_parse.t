# ABOUTME: enum fields parsed from native .proto source round-trip on the wire.
# Regression: the parser tags named-type fields 'message'; resolve must correct
# enum-resolved fields to 'enum' so the codec uses the varint path, not embedded.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;
use Protobuf::Schema;
use Protobuf::Codec;

my $src = <<'PROTO';
syntax = "proto3";
package t;
enum Color {
  UNKNOWN = 0;
  RED = 1;
  GREEN = 2;
}
message M {
  Color c = 1;
  string name = 2;
}
PROTO

my $parser = Protobuf::Parser->new;
my $schema = Protobuf::Schema->new;
$schema->add_file( $parser->parse_string( 'mem.proto', $src ) );
$schema->resolve;

# The enum field resolved through the native parser must read as an enum, not a
# message (the bug left it tagged 'message' with an Enum type_ref).
my ($enum_field) = grep { $_->name eq 'c' } @{ $schema->message('t.M')->fields };
ok( $enum_field->is_enum,     'native-parsed enum field reads as enum' );
ok( !$enum_field->is_message, 'native-parsed enum field is not a message' );

my $codec = Protobuf::Codec->new( schema => $schema );

# Wire round-trip: encode an enum value (a varint), decode it back.
my $bytes = $codec->encode( 't.M', { c => 2, name => 'x' } );
my $back  = $codec->decode( 't.M', $bytes );
is( $back->{c},    2,   'enum value round-trips on the wire' );
is( $back->{name}, 'x', 'sibling scalar round-trips alongside the enum' );

# JSON round-trip exercises the same dispatch through the JSON codec: an enum
# encodes to its symbolic name, and decode normalizes that name back to its
# integer (canonical proto3 JSON).
my $json = $codec->encode_json( 't.M', { c => 1, name => 'y' } );
like( $json, qr/"c":"RED"/, 'enum encodes to its symbolic name in JSON' );
my $from_json = $codec->decode_json( 't.M', $json );
is( $from_json->{c}, 1, 'enum name decodes back to its integer value' );

done_testing;
