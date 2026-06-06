# ABOUTME: Top-level facade for the Protobuf pure-Perl protobuf implementation.
# Carries the distribution version; functional modules live under Protobuf::*.
package Protobuf;

use strict;
use warnings;

our $VERSION = '0.1.0';

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf - A pure-Perl Protocol Buffers implementation

=head1 SYNOPSIS

    use Protobuf::Parser;
    use Protobuf::Codec;

    # Parse a .proto into a schema and resolve cross-type references.
    my $file = Protobuf::Parser->new->parse_string('demo.proto', <<~'PROTO');
        syntax = "proto3";
        package demo;
        message Point { int32 x = 1; int32 y = 2; }
        PROTO

    my $schema = Protobuf::Schema->new;
    $schema->add_file($file)->resolve;

    # A codec is the wire + JSON workhorse, bound to the resolved schema.
    # Message values are plain hashrefs keyed by proto field name.
    my $codec = Protobuf::Codec->new( schema => $schema );

    my $bytes = $codec->encode( 'demo.Point', { x => 3, y => 4 } );
    my $back  = $codec->decode( 'demo.Point', $bytes );        # { x => 3, y => 4 }

    my $json  = $codec->encode_json( 'demo.Point', { x => 3, y => 4 } );  # {"x":3,"y":4}
    my $obj   = $codec->decode_json( 'demo.Point', $json );

For the full guide — getting a schema three ways, the value data model, JSON,
well-known types, generated classes, and the proto2/proto3/editions feature
model — see L<Protobuf::Manual>.

=head1 DESCRIPTION

Protobuf is a pure-Perl implementation of Protocol Buffers: wire codec, schema
model, C<.proto> parser, JSON mapping, well-known types, and ahead-of-time
class generation. This top-level package exposes the distribution version; the
functional pieces live in the C<Protobuf::*> namespace.

Despite the name, the implementation is not limited to proto3: it passes the
full Google conformance suite at protobuf v34 across B<proto2>, B<proto3>, and
B<editions 2023> (Required and Recommended), modelling the syntax/edition
dimension through a resolved feature set (presence, enum openness, repeated
encoding, message encoding, UTF-8 validation). The C<Protobuf> name covers
brand, in the spirit of C<Test2> and C<JSON::PP>.

See C<spec.md> and C<V34-PLAN.md> in the repository root for the design.

=head1 VERSION

Version 0.1.0

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
