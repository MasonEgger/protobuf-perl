# ABOUTME: Proto3::JSON — proto3 canonical JSON encoding over a resolved Schema;
# §4.9. camelCase names, 64-bit-as-string, enum-as-name, base64 bytes,
# default-omit, WKT special-form delegation, and maps-as-objects.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use JSON::PP ();
use MIME::Base64 ();
use Scalar::Util ();

use Proto3::Exception;
use Proto3::WKT;

# The set of scalar proto3 types whose JSON form is a quoted decimal STRING,
# not a JSON number (proto3 JSON spec, §4.9): every 64-bit integer type. A
# value larger than IEEE-754 can represent would lose precision as a JSON
# number, so the canonical form quotes it. Held as a pre-class lexical (the
# feature 'class' package-scoping trap — an our-variable or constant sub would
# land in the file package and be invisible inside class methods).
my %STRING_NUMBER_TYPE =
    map { $_ => 1 } qw( int64 uint64 fixed64 sfixed64 );

# Scalar proto3 types serialized as a JSON number. bool is handled separately
# (JSON true/false), bytes as base64, string as itself. These cover the 32-bit
# integers and the floating-point types.
my %NUMBER_TYPE = map { $_ => 1 } qw(
    int32 uint32 sint32 fixed32 sfixed32 float double
);

# Compute the default json_name: camelCase of a snake_case field name (data_blob
# -> dataBlob). Mirrors the parser's _camel_case so a directly-built schema (no
# json_name set) produces the same keys as a parsed one. A pre-class lexical
# coderef: a file-scope bareword sub is invisible inside class methods under the
# feature 'class' package-scoping rules (it lands in the file package, not the
# class package, and dies at runtime), so the methods close over this lexical.
# The `do {}` wrapper insulates the signatured coderef: this Perl 5.38.2 build
# mis-parses a file-scope `sub (signature)` that immediately precedes a `class`
# block ("Subroutine attributes must come before the signature").
my $camel_case = do {
    sub ($name) {
        $name =~ s/_(.)/\U$1/g;
        return $name;
    };
};

class Proto3::JSON {
    field $codec :param;
    field $schema :param;

    method codec  { $codec }
    method schema { $schema }

    # encode($full_name, $values, %opts) -> a canonical proto3 JSON string.
    #
    # Builds the JSON-shaped Perl structure for the message then serializes it
    # with JSON::PP (canonical mode for stable key order). Options (all default
    # off):
    #   enums_as_ints        emit an enum field as its integer, not its name
    #   preserve_field_names use proto field names instead of camelCase json_name
    #   emit_defaults        include singular scalar fields at their type default
    method encode ($full_name, $values, %opts) {
        my $structure = $self->_to_json_structure( $full_name, $values, \%opts );
        return JSON::PP->new->canonical->encode($structure);
    }

    # Build the JSON-shaped Perl structure (hashref/arrayref/scalar) for the
    # message named $full_name. A well-known type with a special JSON form is
    # delegated to its WKT handler; every other message walks its fields.
    method _to_json_structure ($full_name, $values, $opts) {
        if ( my $special = $self->_wkt_json_value( $full_name, $values ) ) {
            return $special->{value};
        }

        my $message = $schema->message($full_name);
        if ( !defined $message ) {
            Proto3::Exception::Codec::UnknownType->throw(
                message => "unknown message type: $full_name",
            );
        }

        my %out;
        for my $field ( @{ $message->fields } ) {
            $self->_encode_field( $field, $values, $opts, \%out );
        }
        return \%out;
    }

    # Delegate a well-known type to its WKT JSON handler when one exists. Returns
    # a { value => $json } wrapper (so a legitimately-undef WKT form, e.g.
    # NullValue, is distinguishable from "not a WKT"), or undef when $full_name
    # has no special JSON form. The handlers have differing arities — Any needs
    # the codec, the wrappers take the full name — so dispatch is per class.
    method _wkt_json_value ($full_name, $values) {
        my $handler = Proto3::WKT->json_handler($full_name);
        return undef unless $handler;

        my $json =
              $handler eq 'Proto3::WKT::Any'      ? $handler->to_json_value( $values, $codec )
            : $handler eq 'Proto3::WKT::Wrappers' ? $handler->to_json_value( $full_name, $values )
            :                                       $handler->to_json_value($values);
        return { value => $json };
    }

    # Encode one field into the output hashref %$out under its JSON key, unless
    # the field is absent, undef, or an omitted default. Dispatches by field kind:
    # map, repeated, singular message, enum, then scalar.
    method _encode_field ($field, $values, $opts, $out) {
        my $name = $field->name;
        return unless exists $values->{$name};
        my $value = $values->{$name};
        return unless defined $value;

        my $key = $self->_json_key( $field, $opts );

        if ( $field->is_map ) {
            $out->{$key} = $self->_encode_map( $field, $value, $opts );
            return;
        }
        if ( $field->is_repeated ) {
            return unless @$value;    # an empty repeated field is omitted
            $out->{$key} =
                [ map { $self->_encode_element( $field, $_, $opts ) } @$value ];
            return;
        }
        if ( $field->is_message ) {
            $out->{$key} = $self->_encode_message_value( $field, $value, $opts );
            return;
        }
        if ( $field->is_enum ) {
            $out->{$key} = $self->_encode_enum( $field, $value, $opts );
            return;
        }

        # Singular scalar: honour proto3 default-omit unless emit_defaults is on
        # or the field has explicit presence.
        if ( !$opts->{emit_defaults}
            && !$self->_has_explicit_presence($field)
            && $self->_is_default_scalar( $field->type, $value ) )
        {
            return;
        }
        $out->{$key} = $self->_encode_scalar( $field->type, $value );
    }

    # The JSON object key for a field: its camelCase json_name by default (the
    # parser precomputes this; for a directly-built schema we camelCase the proto
    # name), or the raw proto name when preserve_field_names is set.
    method _json_key ($field, $opts) {
        return $field->name if $opts->{preserve_field_names};
        return $field->json_name // $camel_case->( $field->name );
    }

    # Encode one element of a repeated field (a scalar, enum, or message). The
    # repeated kind itself (the array) is handled by the caller.
    method _encode_element ($field, $value, $opts) {
        return $self->_encode_message_value( $field, $value, $opts )
            if $field->is_message;
        return $self->_encode_enum( $field, $value, $opts ) if $field->is_enum;
        return $self->_encode_scalar( $field->type, $value );
    }

    # Encode a singular message-typed value: delegate to its WKT special form
    # when the field's type is a well-known type, else recurse as a nested object.
    method _encode_message_value ($field, $value, $opts) {
        my $type_name = $self->_field_type_name($field);
        if ( my $special = $self->_wkt_json_value( $type_name, $value ) ) {
            return $special->{value};
        }
        return $self->_to_json_structure( $type_name, $value, $opts );
    }

    # Encode an enum value: its symbolic NAME by default, or the integer when
    # enums_as_ints is set or the number has no matching enumerator (an unknown
    # enum number, preserved as the integer per proto3).
    method _encode_enum ($field, $value, $opts) {
        return $value + 0 if $opts->{enums_as_ints};
        my $name = $self->_enum_value_name( $field, $value );
        return defined $name ? $name : $value + 0;
    }

    # The symbolic name of enumerator $number for an enum-typed field, or undef
    # when the enum or the number is unknown.
    method _enum_value_name ($field, $number) {
        my $enum = $self->_field_enum($field) or return undef;
        for my $v ( @{ $enum->values } ) {
            return $v->{name} if $v->{number} == $number;
        }
        return undef;
    }

    # Encode a scalar value to its JSON representation per type: 64-bit integers
    # as decimal strings, bool as JSON true/false, bytes as base64, the 32-bit
    # integers and floats as JSON numbers, and string as itself.
    method _encode_scalar ($type, $value) {
        return "$value" if $STRING_NUMBER_TYPE{$type};
        return $value ? JSON::PP::true : JSON::PP::false if $type eq 'bool';
        return MIME::Base64::encode_base64( $value, '' ) if $type eq 'bytes';
        return $value + 0 if $NUMBER_TYPE{$type};
        return "$value";    # string
    }

    # Encode a map field as a JSON object: each map key becomes an object key
    # (stringified, as JSON object keys are always strings), and each value is
    # encoded per the value field's kind via a synthetic value field.
    method _encode_map ($field, $entries, $opts) {
        my $entry_name = $self->_field_type_name($field);
        my $entry      = $schema->message($entry_name);
        my ($value_field) =
            grep { $_->number == 2 } @{ $entry->fields };

        my %out;
        for my $key ( keys %$entries ) {
            $out{"$key"} =
                $self->_encode_element( $value_field, $entries->{$key}, $opts );
        }
        return \%out;
    }

    # The fully-qualified type name for a message/map/enum field: the resolved
    # $type_ref's full_name when present, else the raw $type_name (so a
    # directly-built schema works without a resolve pass).
    method _field_type_name ($field) {
        my $ref = $field->type_ref;
        return $ref->full_name if $ref;
        return $field->type_name;
    }

    # The Schema::Enum a field refers to: the resolved $type_ref when it is an
    # enum, else looked up by $type_name in the schema's enum index.
    method _field_enum ($field) {
        my $ref = $field->type_ref;
        return $ref if $ref && $ref->isa('Proto3::Schema::Enum');
        return $schema->enum( $field->type_name );
    }

    # True when a field uses explicit-presence JSON serialization (always
    # emitted when set, even at the type default): `optional` fields and oneof
    # members.
    method _has_explicit_presence ($field) {
        return 1 if $field->label eq 'optional';
        return 1 if defined $field->oneof_index;
        return 0;
    }

    # True when $value is the proto3 implicit-presence default for a scalar
    # $type: 0 for numerics and bool, the empty string for string/bytes.
    method _is_default_scalar ($type, $value) {
        return length("$value") == 0 if $type eq 'string' || $type eq 'bytes';
        return $value == 0;
    }
}

1;

__END__

=head1 NAME

Proto3::JSON - proto3 canonical JSON encoding over a resolved schema

=head1 SYNOPSIS

    use Proto3::Codec;

    my $codec = Proto3::Codec->new( schema => $schema );
    my $json  = $codec->encode_json( 'pkg.M', { user_id => 42 } );
    # {"userId":42}

=head1 DESCRIPTION

C<Proto3::JSON> renders a message value hashref (the same shape
L<Proto3::Codec> uses) as a canonical proto3 JSON string, following the proto3
JSON mapping (spec §4.9). It is normally reached through
L<Proto3::Codec/encode_json>, which constructs a C<Proto3::JSON> bound to the
codec and its schema.

=head1 METHODS

=head2 new

    my $json = Proto3::JSON->new( codec => $codec, schema => $schema );

Construct a JSON encoder bound to a L<Proto3::Codec> (used for L<Proto3::WKT>
C<Any> delegation, which encodes its inner message) and a resolved
L<Proto3::Schema>.

=head2 encode

    my $string = $json->encode( $full_name, \%values, %opts );

Encode C<\%values> as the message named C<$full_name> and return a JSON string
with deterministic (canonical) key order.

=head1 ENCODING RULES

=over 4

=item *

B<Field names.> Each field is emitted under its B<camelCase> C<json_name> by
default; C<< preserve_field_names => 1 >> uses the raw proto field name instead.

=item *

B<64-bit integers as strings.> C<int64>, C<uint64>, C<fixed64>, and C<sfixed64>
are emitted as quoted decimal B<strings> (JSON numbers cannot carry their full
precision). The 32-bit integers and the floating types are emitted as JSON
numbers.

=item *

B<Booleans> become JSON C<true>/C<false>; B<bytes> become a B<base64> string;
B<string> is emitted as-is.

=item *

B<Enums> emit their symbolic value B<name> by default; C<< enums_as_ints => 1 >>
emits the integer. An unknown enumerator number (no matching name) always falls
back to the integer.

=item *

B<Default-omit.> A singular scalar field whose value equals its proto3 default
(C<0>, C<false>, or C<"">) is omitted, unless C<< emit_defaults => 1 >> is set or
the field has explicit presence (C<optional> or a oneof member). An empty
repeated field and an empty map are likewise omitted.

=item *

B<Maps> emit as JSON B<objects> keyed by the (stringified) map key, with each
value encoded per the value type.

=item *

B<Well-known types.> A field (or top-level message) whose type has a special
JSON form (L<Proto3::WKT::Timestamp>, L<Proto3::WKT::Duration>, the wrappers,
C<Any>, C<Struct>/C<Value>/C<ListValue>, C<FieldMask>, C<Empty>) is delegated to
that type's C<to_json_value>, so e.g. a C<Timestamp> renders as an RFC3339
string rather than a C<{ seconds, nanos }> object.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
