# ABOUTME: Schema::Field — one field of a message, with kind/packing predicates.
# Immutable except $type_ref (set later by the resolver); §4.2 of the spec.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

# Set of scalar proto3 types eligible for packed repeated encoding. Held as a
# pre-class lexical so methods can read it without tripping the feature 'class'
# package-scoping trap (an imported/constant sub would land in the file package,
# not the class package, and die at runtime). string/bytes/message are NOT
# packable; enum IS (it travels as a varint).
my %PACKABLE_SCALAR = map { $_ => 1 } qw(
    int32 int64 uint32 uint64 sint32 sint64
    fixed32 fixed64 sfixed32 sfixed64
    bool float double enum
);

class Proto3::Schema::Field {
    field $name        :param;
    field $number      :param;
    field $type        :param;                      # 'int32','message','enum',...
    field $label       :param = 'singular';         # 'singular','repeated','optional'
    field $type_name   :param = undef;              # raw '.foo.Bar' before resolution
    field $json_name   :param = undef;
    field $packed      :param = undef;
    field $map_entry   :param = undef;              # set for map fields
    field $oneof_index :param = undef;
    field $type_ref    :param = undef;              # populated by resolver

    # Explicit reader methods: this Perl 5.38.2 build supports :param but not
    # the :reader field attribute.
    method name        { $name }
    method number      { $number }
    method type        { $type }
    method label       { $label }
    method type_name   { $type_name }
    method json_name   { $json_name }
    method packed      { $packed }
    method map_entry   { $map_entry }
    method oneof_index { $oneof_index }
    method type_ref    { $type_ref }

    # The ONE post-construction mutation allowed on a Field (spec §4.2): the
    # resolver calls this to link the resolved Schema::Message/Schema::Enum once
    # type-name resolution runs. Every other field stays immutable.
    method set_type_ref ($ref) { $type_ref = $ref; return $self; }

    method is_message  { $type eq 'message' }
    method is_enum     { $type eq 'enum' }
    method is_repeated { $label eq 'repeated' }
    method is_map      { defined $map_entry }

    # Packed only when explicitly flagged, repeated, and a packable scalar type.
    method is_packed {
        $packed && $self->is_repeated && $self->_is_packable_scalar;
    }

    # Private: is this field's type one of the packable scalar wire types?
    method _is_packable_scalar { $PACKABLE_SCALAR{$type} ? 1 : 0 }
}

1;

__END__

=head1 NAME

Proto3::Schema::Field - A single field within a message schema

=head1 DESCRIPTION

Models one C<FieldDescriptorProto>: its name, number, proto3 type, label, and
optional map/oneof/packing metadata. All fields are immutable after
construction except C<type_ref>, which the resolver populates post-load.

=head1 PREDICATES

=over 4

=item C<is_message> / C<is_enum>

True when C<type> is C<'message'> / C<'enum'> respectively.

=item C<is_repeated>

True when C<label> is C<'repeated'>.

=item C<is_map>

True when this field carries map-entry metadata.

=item C<is_packed>

True only when the field is explicitly flagged packed, is repeated, AND its
type is a packable scalar (numeric, bool, or enum). String, bytes, and message
types are never packed.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
