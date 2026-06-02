# ABOUTME: Proto3::WKT facade — registers the well-known-type schemas into a
# Proto3::Schema and maps full names to their WKT JSON-form handler (§4.8).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::WKT::Timestamp;
use Proto3::WKT::Duration;
use Proto3::WKT::Empty;
use Proto3::WKT::Any;
use Proto3::WKT::FieldMask;
use Proto3::WKT::Wrappers;
use Proto3::WKT::Struct;

class Proto3::WKT {

    # register($schema) — add the well-known-type messages to a Proto3::Schema
    # and run resolve(). Each type's canonical Schema::Message is gathered into a
    # single synthetic google/protobuf WKT file so the schema's fully-qualified
    # index can find them by name (e.g. 'google.protobuf.Timestamp'). The nine
    # primitive wrappers share one parametric handler, so their schemas come from
    # Proto3::WKT::Wrappers->schema_message per name. The Struct family
    # (Struct/Value/ListValue) reference each other and NullValue, so all are
    # registered together and resolve() links the cross-references. Returns
    # $schema for chaining.
    sub register ( $class, $schema ) {
        my @messages = (
            Proto3::WKT::Timestamp->schema_message,
            Proto3::WKT::Duration->schema_message,
            Proto3::WKT::Empty->schema_message,
            Proto3::WKT::Any->schema_message,
            Proto3::WKT::FieldMask->schema_message,
            Proto3::WKT::Struct->schema_message,
            Proto3::WKT::Value->schema_message,
            Proto3::WKT::ListValue->schema_message,
            map { Proto3::WKT::Wrappers->schema_message($_) }
                Proto3::WKT::Wrappers->full_names,
        );

        my $file = Proto3::Schema::File->new(
            name     => 'google/protobuf/wkt.proto',
            package  => 'google.protobuf',
            messages => \@messages,
            enums    => [ Proto3::WKT::NullValue->schema_enum ],
        );
        $schema->add_file($file);
        $schema->resolve;
        return $schema;
    }

    # json_handler($full_name) — return the WKT class that owns the special JSON
    # form for $full_name, or undef if $full_name is not a JSON-special WKT. The
    # JSON layer (§4.9) uses this to delegate to_json_value/from_json_value.
    sub json_handler ( $class, $full_name ) {
        state %HANDLER = (
            'google.protobuf.Timestamp' => 'Proto3::WKT::Timestamp',
            'google.protobuf.Duration'  => 'Proto3::WKT::Duration',
            'google.protobuf.Empty'     => 'Proto3::WKT::Empty',
            'google.protobuf.Any'       => 'Proto3::WKT::Any',
            'google.protobuf.FieldMask' => 'Proto3::WKT::FieldMask',
            'google.protobuf.Struct'    => 'Proto3::WKT::Struct',
            'google.protobuf.Value'     => 'Proto3::WKT::Value',
            'google.protobuf.ListValue' => 'Proto3::WKT::ListValue',
            'google.protobuf.NullValue' => 'Proto3::WKT::NullValue',
            # All nine primitive wrappers share the parametric handler.
            map { $_ => 'Proto3::WKT::Wrappers' }
                Proto3::WKT::Wrappers->full_names,
        );
        return $HANDLER{$full_name};
    }
}

1;

__END__

=head1 NAME

Proto3::WKT - well-known-types facade

=head1 SYNOPSIS

    use Proto3::Schema;
    use Proto3::WKT;

    my $schema = Proto3::Schema->new;
    Proto3::WKT->register($schema);

    my $handler = Proto3::WKT->json_handler('google.protobuf.Timestamp');
    # 'Proto3::WKT::Timestamp'

=head1 DESCRIPTION

The well-known types (C<google.protobuf.*>) encode on the wire like any other
message, but several have B<special JSON forms> (see L<Proto3::WKT::Timestamp>,
L<Proto3::WKT::Duration>) that the JSON layer must delegate to. This facade
registers the WKT schemas into a L<Proto3::Schema> and maps fully-qualified type
names to their JSON-form handler class.

=head1 METHODS

=head2 register( $schema )

Add the well-known-type messages to C<$schema>, call C<< $schema->resolve >>, and
return C<$schema>.

=head2 json_handler( $full_name )

Return the WKT handler class for C<$full_name>, or C<undef> when the type has no
special JSON form.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
