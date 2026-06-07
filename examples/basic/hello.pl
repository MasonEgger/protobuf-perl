#!/usr/bin/env perl
# ABOUTME: examples/basic — the Proto3 quickstart end-to-end against hello.proto.
# Parses the schema, resolves it, then encodes/decodes a message on the wire and
# as canonical proto3 JSON. Run from the repo root: perl -Ilib examples/basic/hello.pl
use v5.38;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/../../lib";

use Protobuf::Parser;
use Protobuf::Codec;

# 1. Parse the .proto file (searching the example directory as an include root)
#    and resolve cross-type references into a single schema.
my $parser = Protobuf::Parser->new( include_paths => [$FindBin::Bin] );
my $schema = $parser->parse_with_imports('hello.proto');
$schema->resolve;

# 2. A codec is the wire + JSON workhorse, bound to the resolved schema.
my $codec = Protobuf::Codec->new( schema => $schema );

# The message value is a plain hashref keyed by proto field name.
my %greeting = (
    text       => 'Hello, world!',
    priority   => 1,
    recipients => [ 'alice', 'bob' ],
);

# 3. Encode to proto3 wire bytes, then decode them back.
my $bytes   = $codec->encode( 'hello.Greeting', \%greeting );
my $decoded = $codec->decode( 'hello.Greeting', $bytes );

say 'Wire bytes: ', length($bytes), ' bytes';
say 'Decoded text: ', $decoded->{text};
say 'Decoded recipients: ', join( ', ', @{ $decoded->{recipients} } );

# 4. The same value as canonical proto3 JSON (deterministic key order), and back.
my $json = $codec->encode_json( 'hello.Greeting', \%greeting );
say "JSON: $json";

my $from_json = $codec->decode_json( 'hello.Greeting', $json );
say 'JSON round-trips: ',
    ( $from_json->{text} eq $greeting{text} ? 'yes' : 'no' );
