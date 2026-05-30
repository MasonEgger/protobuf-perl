# ABOUTME: Top-level facade for the Proto3 pure-Perl protobuf implementation.
# Carries the distribution version; functional modules live under Proto3::*.
package Proto3;

use strict;
use warnings;

our $VERSION = '0.1.0';

1;

__END__

=head1 NAME

Proto3 - A pure-Perl proto3 implementation

=head1 DESCRIPTION

Proto3 is a pure-Perl implementation of Protocol Buffers version 3 (proto3):
wire codec, schema model, .proto parser, JSON mapping, well-known types, and
ahead-of-time class generation. This top-level package exposes the
distribution version; the functional pieces live in the C<Proto3::*>
namespace.

This distribution is pre-alpha. See C<spec.md> in the repository root for the
full specification.

=head1 VERSION

Version 0.1.0

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
