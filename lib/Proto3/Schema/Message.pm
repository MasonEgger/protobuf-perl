# ABOUTME: Schema::Message — a message type; §4.2 of the spec.
# Construction rejects duplicate field numbers and duplicate field names.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema::Util;
use Proto3::Exception;

class Proto3::Schema::Message {
    field $name            :param;
    field $full_name       :param;
    field $fields          :param = [];     # arrayref of Schema::Field
    field $oneofs          :param = [];     # arrayref of Schema::Oneof
    field $nested_messages :param = [];     # arrayref (recursive)
    field $nested_enums    :param = [];     # arrayref of Schema::Enum
    field $reserved_names   :param = [];
    field $reserved_numbers :param = [];    # arrayref of [lo,hi] pairs
    field $oneof_index     :param = undef;
    field $is_map_entry    :param = 0;      # synthetic map-entry message
    field $options         :param = {};     # hashref of options
    field $extension_ranges :param = [];    # arrayref of [lo,hi] extension ranges
    field $extensions      :param = [];     # arrayref of extension Schema::Field decls
    field $message_set_wire_format :param = 0;   # MessageSet wire-format flag
    field $features        :param = {};     # explicit message-level feature overrides

    # Explicit readers (this Perl build has :param but not :reader).
    method name            { $name }
    method full_name       { $full_name }
    method fields          { $fields }
    method oneofs          { $oneofs }
    method nested_messages { $nested_messages }
    method nested_enums    { $nested_enums }
    method reserved_names   { $reserved_names }
    method reserved_numbers { $reserved_numbers }
    method oneof_index     { $oneof_index }
    method is_map_entry    { $is_map_entry }
    method options         { $options }
    method extension_ranges { $extension_ranges }
    method extensions      { $extensions }
    method message_set_wire_format { $message_set_wire_format }
    method features        { $features }

    # Construction invariants: field numbers and field names are each unique
    # within the message.
    ADJUST {
        my @numbers = map { $_->number } @$fields;
        Proto3::Schema::Util::assert_unique(
            \@numbers,
            'Proto3::Exception::Schema::DuplicateField',
            "message $full_name has duplicate field number %s",
        );

        my @names = map { $_->name } @$fields;
        Proto3::Schema::Util::assert_unique(
            \@names,
            'Proto3::Exception::Schema::DuplicateField',
            "message $full_name has duplicate field name '%s'",
        );
    }
}

1;

__END__

=head1 NAME

Proto3::Schema::Message - A message type within a schema

=head1 DESCRIPTION

Models a C<DescriptorProto>: name, fully-qualified name, fields, oneofs, nested
messages/enums, reserved ranges/names, and options.

=head1 CONSTRUCTION INVARIANTS

Within a single message, both field B<numbers> and field B<names> must be
unique; either collision raises C<Proto3::Exception::Schema::DuplicateField> at
construction.

=head1 ACCESSORS

Each returns the correspondingly-named construction value.

=over 4

=item C<name>

The message's short name.

=item C<full_name>

The message's fully-qualified, package-prefixed name.

=item C<fields>

An arrayref of the message's L<Proto3::Schema::Field> objects.

=item C<oneofs>

An arrayref of the message's L<Proto3::Schema::Oneof> objects.

=item C<oneof_index>

The index of the containing oneof when relevant; C<undef> otherwise.

=item C<nested_messages>

An arrayref of nested L<Proto3::Schema::Message> objects.

=item C<nested_enums>

An arrayref of nested L<Proto3::Schema::Enum> objects.

=item C<reserved_numbers>

An arrayref of reserved field-number C<[lo, hi]> ranges.

=item C<reserved_names>

An arrayref of reserved field names.

=item C<options>

A hashref of message-level options.

=item C<is_map_entry>

True when this message is a synthetic C<map<K,V>> entry type.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
