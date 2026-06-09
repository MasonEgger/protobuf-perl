# ABOUTME: Protobuf::Schema — the top-level schema facade: a registry of parsed
# files plus a fully-qualified-name index over messages, enums, and services.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Exception;
use Protobuf::Resolver;
use Protobuf::Schema::Features;
use Scalar::Util ();

class Protobuf::Schema {

    field $files          = [];
    field $file_by_name   = {};
    field $message_index  = {};
    field $enum_index     = {};
    field $service_index  = {};
    field $extension_index = {};    # extendee fq-name -> arrayref of extension Fields
    field $resolved       = 0;

    # Add a parsed Protobuf::Schema::File and index every type it declares
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
            Protobuf::Exception::Schema::DuplicateMessage->throw(
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
            Protobuf::Exception::Schema::DuplicateMessage->throw(
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

    # Registered extension Fields for an extended message's fully-qualified name
    # (no leading dot), or an empty arrayref when none. Populated by resolve.
    method extensions_for ($extendee_full_name) {
        return $extension_index->{$extendee_full_name} // [];
    }

    # Link every message/enum-typed field to its resolved Schema::Message or
    # Schema::Enum via the Step 8 resolver, following proto3 scoping. Each field
    # resolves in its owning message's scope: current_package is the declaring
    # file's package, current_message is the owning message's full_name.
    #
    # Idempotent (spec §4.2): the first call sets every $type_ref; a second call
    # is a no-op, preserving object identity. A dangling type_name propagates
    # Protobuf::Exception::Schema::UnresolvedType from the resolver.
    method resolve {
        return $self if $resolved;

        my $resolver = Protobuf::Resolver->new( schema => $self );

        for my $file (@$files) {
            my $package = $file->package;
            $self->_resolve_message( $_, $package, $resolver )
                for @{ $file->messages };
        }

        # Second pass: fold edition defaults <- file overrides <- field/enum
        # overrides into an effective FeatureSet on every Field and Enum, derive
        # closed-enum/presence flags, and build the extension registry. Kept a
        # separate pass so type-ref resolution above is independent of features.
        for my $file (@$files) {
            $self->_resolve_features( $file );
        }

        $resolved = 1;
        return $self;
    }

    # Resolve the effective FeatureSet for every element a file declares. The
    # file's own FeatureSet is its edition defaults with the file-level override
    # merged in; messages/enums/fields inherit it unless they override.
    method _resolve_features ($file) {
        my $edition       = $file->edition;
        my $base          = Protobuf::Schema::Features->for_edition($edition);
        my $file_features = Protobuf::Schema::Features->merge( $base, $file->features );

        $self->_resolve_message_features( $_, $file_features )
            for @{ $file->messages };
        $self->_resolve_enum_features( $_, $file_features )
            for @{ $file->enums };
    }

    # Apply inherited features down through a message's fields, nested enums,
    # nested messages, and extension declarations, then register extensions.
    method _resolve_message_features ($message, $parent_features) {
        # A message may carry its own override; absent one it inherits as-is.
        my $msg_features = $self->_merge_element_features(
            $parent_features, $message,
        );

        for my $field ( @{ $message->fields } ) {
            $self->_install_field_features( $field, $msg_features );
        }

        for my $ext ( @{ $message->extensions } ) {
            $self->_install_field_features( $ext, $msg_features );
            $self->_register_extension( $ext );
        }

        $self->_resolve_enum_features( $_, $msg_features )
            for @{ $message->nested_enums };
        $self->_resolve_message_features( $_, $msg_features )
            for @{ $message->nested_messages };
    }

    # Install a field's effective FeatureSet (parent merged with the field's own
    # override hashref) via the field's narrow setter.
    method _install_field_features ($field, $parent_features) {
        my $effective = $self->_merge_element_features( $parent_features, $field );
        $field->set_features($effective);
    }

    method _resolve_enum_features ($enum, $parent_features) {
        my $effective = $self->_merge_element_features( $parent_features, $enum );
        $enum->set_features($effective);
    }

    # Merge an element's explicit feature-override hashref over inherited
    # parent features. Elements carry overrides as a plain hashref until resolved
    # (a resolved FeatureSet means already-merged; treat it as no override).
    method _merge_element_features ($parent_features, $element) {
        my $override = $element->features;
        return $parent_features
            if Scalar::Util::blessed($override)
            && $override->isa('Protobuf::Schema::Features');
        return Protobuf::Schema::Features->merge( $parent_features, $override );
    }

    # Add an extension Field to the registry under its extendee's fq-name (the
    # leading dot, if any, stripped).
    method _register_extension ($ext) {
        my $extendee = $ext->extendee;
        return unless defined $extendee;
        ( my $key = $extendee ) =~ s/^\.//;
        push @{ $extension_index->{$key} }, $ext;
    }

    # Resolve every message/enum-typed field of one message, then recurse into
    # nested messages. current_message is the message's own fully-qualified name.
    method _resolve_message ($message, $package, $resolver) {
        my $current_message = $message->full_name;

        for my $field ( @{ $message->fields } ) {
            next unless $field->is_message || $field->is_enum;

            my $ref = $resolver->resolve(
                type_name       => $field->type_name,
                current_package => $package,
                current_message => $current_message,
            );
            $field->set_type_ref($ref);

            # The native parser tags every named-type field 'message' (it can't
            # tell enum from message syntactically). Correct the type from the
            # resolved ref's class so an enum field takes the codec's varint path
            # rather than the embedded-message path. Idempotent for the
            # DescriptorSet path, which already supplies the right type.
            $field->set_type(
                $ref->isa('Protobuf::Schema::Enum') ? 'enum' : 'message' );
        }

        $self->_resolve_message( $_, $package, $resolver )
            for @{ $message->nested_messages };
        return;
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Schema - top-level proto3 schema facade and fully-qualified-name index

=head1 SYNOPSIS

    use Protobuf::Schema;

    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);          # a Protobuf::Schema::File

    my $msg  = $schema->message('pkg.Outer.Inner');   # nested lookup
    my $enum = $schema->enum('pkg.Status');
    my $svc  = $schema->service('pkg.Greeter');

    my $all_msgs  = $schema->all_messages;   # nested flattened
    my $all_enums = $schema->all_enums;

    $schema->resolve;   # links field type_refs (Step 9)

=head1 DESCRIPTION

C<Protobuf::Schema> is the registry the resolver and codec consume. It holds the
parsed L<Protobuf::Schema::File> objects added to it and maintains a
fully-qualified-name index over every message, enum, and service they declare,
recursing into nested message/enum definitions.

=head1 METHODS

=over 4

=item add_file($file)

Register a L<Protobuf::Schema::File> and index all of its types. A single
recursive walk populates the message and enum indexes, reaching nested types
(e.g. C<Outer.Inner>). If a message or enum full_name collides with one already
registered, throws L<Protobuf::Exception::Schema::DuplicateMessage>. Returns the
schema for chaining.

=item files

An arrayref of the registered L<Protobuf::Schema::File> objects, in insertion
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

Link every message- or enum-typed field to its resolved
L<Protobuf::Schema::Message> or L<Protobuf::Schema::Enum>. Each field is resolved in
its owning message's scope (the declaring file's package plus the owning
message's fully-qualified name) using L<Protobuf::Resolver>, so proto3
innermost-first type-name scoping is honored.

B<Idempotent> (spec §4.2): the first call populates every C<type_ref>; a second
call is a no-op and preserves object identity. A field whose C<type_name> cannot
be resolved makes C<resolve> propagate
L<Protobuf::Exception::Schema::UnresolvedType>. C<type_ref> is the single mutable
field on L<Protobuf::Schema::Field>; it is written only here, via that class's
narrow C<set_type_ref> setter. Returns the schema for chaining.

=item extensions_for($extendee_full_name)

Return the arrayref of extension L<Protobuf::Schema::Field>s registered against
the message named C<$extendee_full_name> (collected from C<extend> blocks across
every added file), or an empty arrayref when the message has no extensions.

=back

=cut
