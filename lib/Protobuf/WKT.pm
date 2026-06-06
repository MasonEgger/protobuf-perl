# ABOUTME: Protobuf::WKT facade — registers the well-known-type schemas into a
# Protobuf::Schema and maps full names to their WKT JSON-form handler (§4.8).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::WKT::Timestamp;
use Protobuf::WKT::Duration;
use Protobuf::WKT::Empty;
use Protobuf::WKT::Any;
use Protobuf::WKT::FieldMask;
use Protobuf::WKT::Wrappers;
use Protobuf::WKT::Struct;

class Protobuf::WKT {

    # register($schema) — add the well-known-type messages to a Protobuf::Schema
    # and run resolve(). Each type's canonical Schema::Message is gathered into a
    # single synthetic google/protobuf WKT file so the schema's fully-qualified
    # index can find them by name (e.g. 'google.protobuf.Timestamp'). The nine
    # primitive wrappers share one parametric handler, so their schemas come from
    # Protobuf::WKT::Wrappers->schema_message per name. The Struct family
    # (Struct/Value/ListValue) reference each other and NullValue, so all are
    # registered together and resolve() links the cross-references. Returns
    # $schema for chaining.
    sub register ( $class, $schema ) {
        my @messages = (
            Protobuf::WKT::Timestamp->schema_message,
            Protobuf::WKT::Duration->schema_message,
            Protobuf::WKT::Empty->schema_message,
            Protobuf::WKT::Any->schema_message,
            Protobuf::WKT::FieldMask->schema_message,
            Protobuf::WKT::Struct->schema_message,
            Protobuf::WKT::Value->schema_message,
            Protobuf::WKT::ListValue->schema_message,
            map { Protobuf::WKT::Wrappers->schema_message($_) }
                Protobuf::WKT::Wrappers->full_names,
        );

        my $file = Protobuf::Schema::File->new(
            name     => 'google/protobuf/wkt.proto',
            package  => 'google.protobuf',
            messages => \@messages,
            enums    => [ Protobuf::WKT::NullValue->schema_enum ],
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
            'google.protobuf.Timestamp' => 'Protobuf::WKT::Timestamp',
            'google.protobuf.Duration'  => 'Protobuf::WKT::Duration',
            'google.protobuf.Empty'     => 'Protobuf::WKT::Empty',
            'google.protobuf.Any'       => 'Protobuf::WKT::Any',
            'google.protobuf.FieldMask' => 'Protobuf::WKT::FieldMask',
            'google.protobuf.Struct'    => 'Protobuf::WKT::Struct',
            'google.protobuf.Value'     => 'Protobuf::WKT::Value',
            'google.protobuf.ListValue' => 'Protobuf::WKT::ListValue',
            'google.protobuf.NullValue' => 'Protobuf::WKT::NullValue',
            # All nine primitive wrappers share the parametric handler.
            map { $_ => 'Protobuf::WKT::Wrappers' }
                Protobuf::WKT::Wrappers->full_names,
        );
        return $HANDLER{$full_name};
    }
}

1;

__END__

=head1 NAME

Protobuf::WKT - well-known-types facade

=head1 SYNOPSIS

    use Protobuf::Schema;
    use Protobuf::WKT;

    my $schema = Protobuf::Schema->new;
    Protobuf::WKT->register($schema);

    my $handler = Protobuf::WKT->json_handler('google.protobuf.Timestamp');
    # 'Protobuf::WKT::Timestamp'

=head1 DESCRIPTION

The well-known types (C<google.protobuf.*>) encode on the wire like any other
message, but several have B<special JSON forms> (see L<Protobuf::WKT::Timestamp>,
L<Protobuf::WKT::Duration>) that the JSON layer must delegate to. This facade
registers the WKT schemas into a L<Protobuf::Schema> and maps fully-qualified type
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
