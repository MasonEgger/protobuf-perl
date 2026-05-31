# ABOUTME: Proto3::Schema — the top-level schema facade: a registry of parsed
# files plus a fully-qualified-name index over messages, enums, and services.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Exception;

class Proto3::Schema {

    field $files          = [];
    field $file_by_name   = {};
    field $message_index  = {};
    field $enum_index     = {};
    field $service_index  = {};
    field $resolved       = 0;

    # Add a parsed Proto3::Schema::File and index every type it declares
    # (including nested messages and enums) by fully-qualified name.
    method add_file ($file) {
        push @$files, $file;
        $file_by_name->{ $file->name } = $file;

        $self->_index_message($_) for @{ $file->messages };
        $self->_index_enum($_)    for @{ $file->enums };
        $self->_index_service($_) for @{ $file->services };

        return $self;
    }

    # Recursively index a message and any nested messages/enums it contains.
    method _index_message ($message) {
        my $full = $message->full_name;
        if ( exists $message_index->{$full} ) {
            Proto3::Exception::Schema::DuplicateMessage->throw(
                message => "duplicate message full_name: $full",
            );
        }
        $message_index->{$full} = $message;

        $self->_index_message($_) for @{ $message->nested_messages };
        $self->_index_enum($_)    for @{ $message->nested_enums };
        return;
    }

    method _index_enum ($enum) {
        my $full = $enum->full_name;
        if ( exists $enum_index->{$full} ) {
            Proto3::Exception::Schema::DuplicateMessage->throw(
                message => "duplicate enum full_name: $full",
            );
        }
        $enum_index->{$full} = $enum;
        return;
    }

    method _index_service ($service) {
        $service_index->{ $service->full_name } = $service;
        return;
    }

    method files { $files }

    method file ($name) { $file_by_name->{$name} }

    # Look up a message/enum/service by fully-qualified name; undef if unknown.
    method message ($full_name) { $message_index->{$full_name} }
    method enum ($full_name)    { $enum_index->{$full_name} }
    method service ($full_name) { $service_index->{$full_name} }

    # All indexed messages/enums (nested definitions flattened).
    method all_messages { [ values %$message_index ] }
    method all_enums    { [ values %$enum_index ] }

    # Type resolution is wired in Step 9; the stub is chainable so callers can
    # write `$schema->resolve` today without behavior changing later.
    method resolve {
        $resolved = 1;
        return $self;
    }
}

1;

__END__

=head1 NAME

Proto3::Schema - top-level proto3 schema facade and fully-qualified-name index

=head1 SYNOPSIS

    use Proto3::Schema;

    my $schema = Proto3::Schema->new;
    $schema->add_file($file);          # a Proto3::Schema::File

    my $msg  = $schema->message('pkg.Outer.Inner');   # nested lookup
    my $enum = $schema->enum('pkg.Status');
    my $svc  = $schema->service('pkg.Greeter');

    my $all_msgs  = $schema->all_messages;   # nested flattened
    my $all_enums = $schema->all_enums;

    $schema->resolve;   # links field type_refs (Step 9)

=head1 DESCRIPTION

C<Proto3::Schema> is the registry the resolver and codec consume. It holds the
parsed L<Proto3::Schema::File> objects added to it and maintains a
fully-qualified-name index over every message, enum, and service they declare,
recursing into nested message/enum definitions.

=head1 METHODS

=over 4

=item add_file($file)

Register a L<Proto3::Schema::File> and index all of its types. A single
recursive walk populates the message and enum indexes, reaching nested types
(e.g. C<Outer.Inner>). If a message or enum full_name collides with one already
registered, throws L<Proto3::Exception::Schema::DuplicateMessage>. Returns the
schema for chaining.

=item files

An arrayref of the registered L<Proto3::Schema::File> objects, in insertion
order.

=item file($name)

The registered file with the given name, or C<undef> if none.

=item message($full_name)

=item enum($full_name)

=item service($full_name)

Look up a message, enum, or service by its fully-qualified (dotted) name,
including nested types. Returns C<undef> for unknown names rather than dying.

=item all_messages

=item all_enums

Arrayrefs of every indexed message or enum, with nested definitions flattened
into the same list as top-level ones.

=item resolve

Resolve field type references against the index. Currently a chainable stub;
the resolution logic is wired in Step 9. Returns the schema.

=back

=cut
