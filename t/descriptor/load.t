# ABOUTME: T-fds-1/T-fds-3 — DescriptorSet loads a protoc FileDescriptorSet into
# a Schema matching Proto3::Parser, with the Type-enum mapping and corrupt-FDS path.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use lib 't/lib';

use Proto3Test::Protoc qw(have_protoc);

use Proto3::DescriptorSet;
use Proto3::Parser;
use Proto3::Exception;

use File::Temp ();
use File::Spec ();

# ----------------------------------------------------------------------
# T-fds-2x: the protobuf Type enum -> our string type identifiers. The
# full table is the contract between the bootstrap decode and our schema
# model; a wrong entry silently mis-types a loaded field.
# ----------------------------------------------------------------------
my %EXPECTED_TYPE_MAP = (
    1  => 'double',
    2  => 'float',
    3  => 'int64',
    4  => 'uint64',
    5  => 'int32',
    6  => 'fixed64',
    7  => 'fixed32',
    8  => 'bool',
    9  => 'string',
    11 => 'message',
    12 => 'bytes',
    13 => 'uint32',
    14 => 'enum',
    15 => 'sfixed32',
    16 => 'sfixed64',
    17 => 'sint32',
    18 => 'sint64',
);

is_deeply(
    Proto3::DescriptorSet->type_enum_to_string,
    \%EXPECTED_TYPE_MAP,
    'protobuf Type enum maps to our scalar/message/enum type identifiers',
);

# ----------------------------------------------------------------------
# T-fds-3: a corrupt FDS (bytes that are not a valid FileDescriptorSet)
# surfaces a Proto3::Exception::Codec, not a silent mis-parse.
# ----------------------------------------------------------------------
{
    # A LEN field (field 1) claiming 50 payload bytes but with none following:
    # tag 0x0a, length 50, no body -> truncated inside the codec.
    my $corrupt = "\x0a\x32";
    my $err;
    eval { Proto3::DescriptorSet->load_string($corrupt); 1 } or $err = $@;
    ok( $err, 'corrupt FDS raises' );
    isa_ok( $err, 'Proto3::Exception::Codec',
        'corrupt FDS raises Proto3::Exception::Codec' );
}

# ----------------------------------------------------------------------
# T-fds-1: load a protoc-produced FDS and verify the Schema matches what
# Proto3::Parser produces from the same .proto source.
# ----------------------------------------------------------------------
SKIP: {
    skip 'protoc not on PATH', 1 unless have_protoc();

    my $PROTO = <<'PROTO';
syntax = "proto3";
package fds;

enum Color {
  COLOR_UNSPECIFIED = 0;
  RED = 1;
  GREEN = 2;
}

message Inner {
  int32 x = 1;
}

message Outer {
  int32  id    = 1;
  string name  = 2;
  repeated int64 nums = 3;
  Inner  inner = 4;
  Color  color = 5;
  map<string, int32> attrs = 6;
  oneof choice {
    int32  a = 7;
    string b = 8;
  }
  optional bool flag = 9;
}
PROTO

    # Produce the FDS via protoc.
    my $dir = File::Temp->newdir;
    my $proto_path = File::Spec->catfile( "$dir", 'fds.proto' );
    open my $pfh, '>', $proto_path or die "write $proto_path: $!";
    print {$pfh} $PROTO;
    close $pfh;

    my $fds_path = File::Spec->catfile( "$dir", 'out.fds' );
    system( 'protoc', "--proto_path=$dir",
        "--descriptor_set_out=$fds_path", $proto_path ) == 0
        or die "protoc failed";

    my $loaded = Proto3::DescriptorSet->load_file($fds_path);

    my $parser = Proto3::Parser->new;
    my $parsed_file = $parser->parse_string( 'fds.proto', $PROTO );
    my $parsed = Proto3::Schema->new;
    $parsed->add_file($parsed_file);
    $parsed->resolve;

    # Same set of top-level messages and enums.
    my @loaded_msgs = sort map { $_->full_name } @{ $loaded->all_messages };
    my @parsed_msgs = sort map { $_->full_name } @{ $parsed->all_messages };
    is_deeply( \@loaded_msgs, \@parsed_msgs,
        'loaded and parsed schemas declare the same messages' );

    my @loaded_enums = sort map { $_->full_name } @{ $loaded->all_enums };
    my @parsed_enums = sort map { $_->full_name } @{ $parsed->all_enums };
    is_deeply( \@loaded_enums, \@parsed_enums,
        'loaded and parsed schemas declare the same enums' );

    # Field-level equivalence on Outer, compared by a normalized summary so the
    # parser's relative type_name and our fully-qualified one collapse to the
    # same resolved fully-qualified target.
    my $loaded_outer = $loaded->message('fds.Outer');
    my $parsed_outer = $parsed->message('fds.Outer');

    is_deeply(
        _field_summary($loaded_outer),
        _field_summary($parsed_outer),
        'Outer fields match between loaded FDS and parsed source',
    );

    # The enum values round-trip with names and numbers intact.
    my $loaded_color = $loaded->enum('fds.Color');
    is_deeply(
        [ map { [ $_->{name}, $_->{number} ] } @{ $loaded_color->values } ],
        [ [ 'COLOR_UNSPECIFIED', 0 ], [ 'RED', 1 ], [ 'GREEN', 2 ] ],
        'loaded enum values preserve names and numbers',
    );

    # The oneof is reconstructed with its members.
    my ($oneof) = @{ $loaded_outer->oneofs };
    ok( $oneof, 'Outer has a reconstructed oneof' );
    is( $oneof->name, 'choice', 'oneof name preserved' );
}

# A per-field summary keyed by field name. For named (message/enum) fields the
# resolved target's fully-qualified name is used, so a relative reference
# (parser) and a fully-qualified one (FDS) compare equal once resolved. The
# message-vs-enum distinction is deliberately collapsed into a single `is_named`
# flag plus the resolved target: the parser represents both as `message` and
# settles the kind only via the resolved ref, while our FDS loader records the
# precise kind, so comparing the two on is_message/is_enum directly would be a
# false mismatch.
sub _field_summary ($message) {
    my %summary;
    for my $f ( @{ $message->fields } ) {
        my $named = $f->is_message || $f->is_enum;
        my $target = $named && $f->type_ref ? $f->type_ref->full_name : '';
        $summary{ $f->name } = {
            number    => $f->number,
            label     => $f->label,
            is_map    => $f->is_map ? 1 : 0,
            is_named  => $named ? 1 : 0,
            target    => $target,
            json_name => $f->json_name,
        };
    }
    return \%summary;
}

done_testing;
