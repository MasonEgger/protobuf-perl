# ABOUTME: Schema::Service — a service and its RPC methods (parse-only); §4.2.
# No RPC dispatch; just enough structure to round-trip .proto definitions.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Proto3::Schema::Service {
    field $name      :param;
    field $full_name :param;
    field $methods   :param = [];   # arrayref of { name, input_type, output_type, ... }

    # Explicit readers (this Perl build has :param but not :reader).
    method name      { $name }
    method full_name { $full_name }
    method methods   { $methods }
}

1;

__END__

=head1 NAME

Proto3::Schema::Service - A service definition within a schema

=head1 DESCRIPTION

Models a C<ServiceDescriptorProto>: its name, fully-qualified name, and RPC
methods (C<{ name, input_type, output_type, ... }> hashrefs). Parse-only — this
library does not dispatch RPCs.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
