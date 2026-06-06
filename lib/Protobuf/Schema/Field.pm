# ABOUTME: Schema::Field — one field of a message, with kind/packing predicates.
# Immutable except $type_ref (set later by the resolver); §4.2 of the spec.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Scalar::Util ();

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

class Protobuf::Schema::Field {
    field $name          :param;
    field $number        :param;
    field $type          :param;                    # 'int32','message','enum',...
    field $label         :param = 'singular';       # 'singular','repeated','optional'
    field $type_name     :param = undef;            # raw '.foo.Bar' before resolution
    field $json_name     :param = undef;
    field $packed        :param = undef;
    field $map_entry     :param = undef;            # set for map fields
    field $oneof_index   :param = undef;
    field $type_ref      :param = undef;            # populated by resolver
    field $options       :param = {};               # hashref of field options
    field $default_value :param = undef;            # proto2 [default = ...]
    field $is_extension  :param = 0;                # `extend` field
    field $extendee      :param = undef;            # '.foo.Base' extended message
    field $features      :param = {};               # explicit feature overrides;
                                                    # replaced with the resolved
                                                    # FeatureSet by the resolver
    field $group_encoded :param = 0;                # TYPE_GROUP: force delimited
                                                    # message_encoding regardless
                                                    # of resolved features

    # Explicit reader methods: this Perl 5.38.2 build supports :param but not
    # the :reader field attribute.
    method name          { $name }
    method number        { $number }
    method type          { $type }
    method label         { $label }
    method type_name     { $type_name }
    method json_name     { $json_name }
    method packed        { $packed }
    method map_entry     { $map_entry }
    method oneof_index   { $oneof_index }
    method type_ref      { $type_ref }
    method options       { $options }
    method default_value { $default_value }
    method is_extension  { $is_extension }
    method extendee      { $extendee }
    method features      { $features }

    # The ONE post-construction mutation allowed on a Field (spec §4.2): the
    # resolver calls this to link the resolved Schema::Message/Schema::Enum once
    # type-name resolution runs. Every other field stays immutable.
    method set_type_ref ($ref) { $type_ref = $ref; return $self; }

    # Companion to set_type_ref: the native parser cannot tell enum from message
    # syntactically and tags both 'message', so the resolver rewrites the type to
    # 'enum' once it sees the resolved target is a Schema::Enum. Idempotent — the
    # DescriptorSet path already supplies the correct type, so this is a no-op
    # there. Like set_type_ref, the only post-construction mutation kept narrow.
    method set_type ($new_type) { $type = $new_type; return $self; }

    # The resolver replaces the explicit-override hashref with the field's
    # effective Protobuf::Schema::Features. Idempotent like set_type_ref: storing
    # the same resolved set twice preserves identity.
    method set_features ($resolved) { $features = $resolved; return $self; }

    # The field's effective message wire encoding: 'delimited' or
    # 'length_prefixed'. A TYPE_GROUP field is always delimited (the group wire
    # format); otherwise the resolved message_encoding feature decides (editions
    # DELIMITED -> 'delimited'). Before resolution it defaults to
    # 'length_prefixed' unless group-forced.
    method message_encoding {
        return 'delimited' if $group_encoded;
        if ( $self->_features_resolved ) {
            return $features->message_encoding eq 'DELIMITED'
                ? 'delimited'
                : 'length_prefixed';
        }
        return 'length_prefixed';
    }

    # The field's effective string UTF-8 validation: 'VERIFY' or 'NONE'. A
    # proto3 (and editions-default) string field VERIFYs that its wire octets are
    # valid UTF-8 and rejects a payload that is not; a proto2 string does NOT
    # (NONE). Driven by the resolved utf8_validation feature; before resolution
    # the field defaults to NONE (no rejection) so a directly-built schema with
    # no feature pass keeps today's lenient behavior.
    method utf8_validation {
        if ( $self->_features_resolved ) {
            return $features->utf8_validation eq 'VERIFY' ? 'VERIFY' : 'NONE';
        }
        return 'NONE';
    }

    # True for a TYPE_GROUP field (modeled as a delimited message).
    method is_group { $group_encoded ? 1 : 0 }

    method is_message  { $type eq 'message' }
    method is_enum     { $type eq 'enum' }
    method is_repeated { $label eq 'repeated' }
    method is_map      { defined $map_entry }

    # The field's effective presence: 'implicit', 'explicit', or
    # 'legacy_required'. Driven by resolved features when present; otherwise it
    # reproduces today's proto3 behavior: a singular scalar is implicit unless
    # declared `optional` or it sits in a oneof.
    method presence {
        if ( $self->_features_resolved ) {
            return 'legacy_required' if $features->field_presence eq 'LEGACY_REQUIRED';
            return 'explicit'        if $features->field_presence eq 'EXPLICIT';
            # IMPLICIT: a field in a oneof or declared `optional` still tracks
            # presence explicitly even when the edition default is implicit.
            return 'explicit' if $label eq 'optional' || defined $oneof_index;
            return 'implicit';
        }
        return 'explicit' if $label eq 'optional' || defined $oneof_index;
        return 'implicit';
    }

    # True when the field tracks explicit presence (hazzer-style). The codec
    # uses this to decide default-omit: an implicit field at its type default is
    # omitted; an explicit-presence field is always written when set.
    method has_presence { $self->presence ne 'implicit' ? 1 : 0 }

    # Packed when repeated and a packable scalar. When features are resolved the
    # effective repeated_field_encoding decides (PACKED by default for proto3 /
    # edition2023; EXPANDED for proto2), with an explicit [packed = false] still
    # honored. Before resolution this preserves the original Step-6 semantics:
    # packed only when the explicit `packed` flag is set.
    method is_packed {
        return 0 unless $self->is_repeated && $self->_is_packable_scalar;

        if ( $self->_features_resolved ) {
            return 0 unless $features->repeated_field_encoding eq 'PACKED';
            # PACKED edition default still honors an explicit [packed = false].
            return 0 if defined $packed && !$packed;
            return 1;
        }

        # Pre-resolution legacy path: packed only when explicitly flagged.
        return $packed ? 1 : 0;
    }

    # Private: have the resolved features been installed (vs. the raw override
    # hashref a freshly-constructed field carries)?
    method _features_resolved {
        Scalar::Util::blessed($features)
            && $features->isa('Protobuf::Schema::Features');
    }

    # Private: is this field's type one of the packable scalar wire types?
    method _is_packable_scalar { $PACKABLE_SCALAR{$type} ? 1 : 0 }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Schema::Field - A single field within a message schema

=head1 DESCRIPTION

Models one C<FieldDescriptorProto>: its name, number, proto3 type, label, and
optional map/oneof/packing metadata. All fields are immutable after
construction except C<type_ref>, which the resolver populates post-load.

=head1 ACCESSORS

Each returns the correspondingly-named construction value.

=over 4

=item C<name>

The field's proto name.

=item C<number>

The field's wire tag number.

=item C<type>

The proto3 type string (e.g. C<'int32'>, C<'message'>, C<'enum'>).

=item C<label>

One of C<'singular'>, C<'repeated'>, or C<'optional'>.

=item C<type_name>

The raw, unresolved dotted type name (e.g. C<'.foo.Bar'>) for message/enum
fields; C<undef> for scalars.

=item C<json_name>

The field's JSON name, or C<undef> to derive it from C<name>.

=item C<packed>

The explicit C<packed> option value, or C<undef> when unspecified.

=item C<map_entry>

The map-entry message for a C<map<K,V>> field; C<undef> otherwise.

=item C<oneof_index>

The index of the containing oneof, or C<undef> when the field is not in a
oneof.

=item C<type_ref>

The resolved L<Protobuf::Schema::Message> / L<Protobuf::Schema::Enum> the field
references, populated by the resolver; C<undef> before resolution.

=item C<options>

A hashref of the field's options.

=back

=head1 METHODS

=over 4

=item C<set_type_ref($ref)>

A post-construction mutation the resolver uses: it links the resolved type.
Returns C<$self>.

=item C<set_type($new_type)>

Companion to C<set_type_ref>: the native parser cannot distinguish enum from
message syntactically and tags both C<'message'>, so the resolver rewrites the
type to C<'enum'> once it sees the resolved target is a L<Protobuf::Schema::Enum>.
Idempotent. Returns C<$self>.

=back

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
