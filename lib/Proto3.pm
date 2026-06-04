# ABOUTME: Top-level facade for the Proto3 pure-Perl protobuf implementation.
# Carries the distribution version; functional modules live under Proto3::*.
package Proto3;

use strict;
use warnings;

our $VERSION = '0.1.0';

1;

__END__

=head1 NAME

Proto3 - A pure-Perl Protocol Buffers implementation

=head1 DESCRIPTION

Proto3 is a pure-Perl implementation of Protocol Buffers: wire codec, schema
model, C<.proto> parser, JSON mapping, well-known types, and ahead-of-time
class generation. This top-level package exposes the distribution version; the
functional pieces live in the C<Proto3::*> namespace.

Despite the name, the implementation is not limited to proto3: it passes the
full Google conformance suite at protobuf v34 across B<proto2>, B<proto3>, and
B<editions 2023> (Required and Recommended), modelling the syntax/edition
dimension through a resolved feature set (presence, enum openness, repeated
encoding, message encoding, UTF-8 validation). The C<Proto3> name is kept as a
brand, in the spirit of C<Test2> and C<JSON::PP>.

See C<spec.md> and C<V34-PLAN.md> in the repository root for the design.

=head1 VERSION

Version 0.1.0

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
