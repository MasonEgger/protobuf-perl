# ABOUTME: codec-level fuzz (S-004) — random byte strings through Codec::decode of
# a fixed schema must each either decode or raise a TYPED Protobuf::Exception,
# never an uncaught Perl die. Complements the wire-level t/wire/fuzz.t.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;
use Protobuf::Schema;
use Protobuf::Codec;
use Protobuf::Exception;
use Scalar::Util ();

my $src = <<'PROTO';
syntax = "proto3";
message Fuzz {
  int32  i  = 1;
  string s  = 2;
  repeated int64 r = 3;
  Nested n  = 4;
  map<string, int32> m = 5;
  oneof pick { bool b = 6; bytes by = 7; }
}
message Nested { int32 x = 1; string y = 2; }
PROTO

my $schema = Protobuf::Schema->new;
$schema->add_file( Protobuf::Parser->new->parse_string( 'fuzz.proto', $src ) );
$schema->resolve;
my $codec = Protobuf::Codec->new( schema => $schema );

srand(20260608);    # deterministic corpus

my $iterations = 5000;
my $bad        = 0;
for ( 1 .. $iterations ) {
    my $len   = int( rand 32 );
    my $bytes = join '', map { chr int rand 256 } 1 .. $len;

    my $ok = eval { $codec->decode( 'Fuzz', $bytes ); 1 };
    next if $ok;    # decoded cleanly

    my $err = $@;
    next
        if ref $err
        && Scalar::Util::blessed($err)
        && $err->isa('Protobuf::Exception');

    $bad++;
    diag sprintf( 'uncaught non-typed error on input %s: %s',
        unpack( 'H*', $bytes ), $err );
    last if $bad > 5;
}

is( $bad, 0, "all $iterations random inputs decoded or raised a typed exception" );

done_testing;
