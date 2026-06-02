# ABOUTME: Schema::Service — a service and its RPC methods (parse-only); §4.2.
# No RPC dispatch; just enough structure to round-trip .proto definitions.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Proto3::Schema::Service {
    field $name      :param;
    field $full_name :param;
    field $methods   :param = [];   # arrayref of { name, input_type, output_type, ... }
    field $options   :param = {};   # hashref of service-level options

    # Explicit readers (this Perl build has :param but not :reader).
    method name      { $name }
    method full_name { $full_name }
    method methods   { $methods }
    method options   { $options }
}

1;

__END__

=head1 NAME

Proto3::Schema::Service - A service definition within a schema

=head1 DESCRIPTION

Models a C<ServiceDescriptorProto>: its name, fully-qualified name, RPC methods,
and service-level options. Each method is a hashref of the form
C<< { name, input_type, output_type, client_streaming, server_streaming } >>,
where the streaming flags are booleans driven by the C<stream> keyword on the
request/response types. Parse-only — this library does not dispatch RPCs.

=head1 ACCESSORS

Each returns the correspondingly-named construction value.

=over 4

=item C<name>

The service's short name.

=item C<full_name>

The service's fully-qualified, package-prefixed name.

=item C<methods>

An arrayref of RPC-method hashrefs (see L</DESCRIPTION>).

=item C<options>

A hashref of service-level options.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
