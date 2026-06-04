# ABOUTME: Proto3::JSON — proto3 canonical JSON encoding over a resolved Schema;
# §4.9. camelCase names, 64-bit-as-string, enum-as-name, base64 bytes,
# default-omit, WKT special-form delegation, and maps-as-objects.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use B ();
use JSON::PP ();
use Math::BigInt ();
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

# Inclusive [min, max] range for each integer proto3 type, as Math::BigInt so
# the 64-bit bounds are exact (a native float cannot hold 2^64-1). proto3 JSON
# input must reject an integer field whose value falls outside this range, the
# same as protoc. Held as a pre-class lexical for the feature 'class' scoping
# rule.
my %INT_RANGE = (
    int32    => [ Math::BigInt->new('-2147483648'),          Math::BigInt->new('2147483647') ],
    sint32   => [ Math::BigInt->new('-2147483648'),          Math::BigInt->new('2147483647') ],
    sfixed32 => [ Math::BigInt->new('-2147483648'),          Math::BigInt->new('2147483647') ],
    uint32   => [ Math::BigInt->new('0'),                    Math::BigInt->new('4294967295') ],
    fixed32  => [ Math::BigInt->new('0'),                    Math::BigInt->new('4294967295') ],
    int64    => [ Math::BigInt->new('-9223372036854775808'), Math::BigInt->new('9223372036854775807') ],
    sint64   => [ Math::BigInt->new('-9223372036854775808'), Math::BigInt->new('9223372036854775807') ],
    sfixed64 => [ Math::BigInt->new('-9223372036854775808'), Math::BigInt->new('9223372036854775807') ],
    uint64   => [ Math::BigInt->new('0'),                    Math::BigInt->new('18446744073709551615') ],
    fixed64  => [ Math::BigInt->new('0'),                    Math::BigInt->new('18446744073709551615') ],
);

# The largest finite magnitude representable in each floating proto3 type. A
# numeric JSON literal whose absolute value exceeds this overflows the type and
# is rejected on input, matching protoc (the "Infinity"/"-Infinity" string forms
# are handled separately and are NOT routed through this check).
my %FLOAT_MAX = (
    float  => 3.4028234663852886e+38,
    double => 1.7976931348623157e+308,
);

# Classify a decoded JSON::PP scalar by the SV flags JSON::PP leaves on it: a
# JSON string carries POK, a JSON number carries IOK or NOK, and a JSON boolean
# is a blessed JSON::PP::Boolean. This is the only reliable way to tell a JSON
# string "12" from a JSON number 12 after parsing, which proto3 input validation
# needs (a string field must reject a number; an int field treats the two
# spellings differently). Returns 'string', 'number', 'bool', or 'other'.
my $json_kind = do {
    sub ($value) {
        return 'bool' if Scalar::Util::blessed($value)
            && $value->isa('JSON::PP::Boolean');
        return 'other' if ref $value;    # arrayref/hashref (array/object)
        my $flags = B::svref_2object( \$value )->FLAGS;
        return 'number' if $flags & ( B::SVf_IOK() | B::SVf_NOK() );
        return 'string' if $flags & B::SVf_POK();
        return 'other';
    };
};

# True when $text is the decimal spelling of an integer with no surrounding
# whitespace, sign-and-digits only (an optional leading '-' then one or more
# digits). Used to validate the JSON-string form of an integer field, which
# proto3 accepts but which protoc requires be a clean integer: " 1", "1 ",
# "1.5", "1e5", and "" are all rejected.
my $is_integer_string = do {
    sub ($text) {
        return $text =~ /\A-?[0-9]+\z/;
    };
};

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

# Convert a camelCase name to snake_case (dataBlob -> data_blob). The inverse of
# $camel_case, used on decode to normalize an incoming JSON key to the proto
# field name so both spellings of a key resolve to the same field. Same pre-class
# lexical / do{} wrapper rationale as $camel_case above.
my $snake_case = do {
    sub ($name) {
        $name =~ s/([A-Z])/_\L$1/g;
        return $name;
    };
};

class Proto3::JSON {
    field $codec :param;
    field $schema :param;

    # Per-encode registry of float/double literals that must appear UNQUOTED and
    # at full precision in the output. JSON::PP re-stringifies a native double at
    # ~15 digits (dropping round-trip precision) and offers no raw-number
    # injection, so the float encoder emits a unique sentinel string, records the
    # exact literal here, and encode() substitutes the bare literal for the
    # quoted sentinel after serialization.
    field %float_literal;

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
        %float_literal = ();
        my $structure = $self->_to_json_structure( $full_name, $values, \%opts );
        my $json = JSON::PP->new->canonical->encode($structure);
        if (%float_literal) {
            # Replace each "sentinel" (a quoted JSON string) with its bare
            # full-precision numeric literal.
            $json =~ s/"(\Q$_\E)"/$float_literal{$1}/g for keys %float_literal;
        }
        return $json;
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
              $handler eq 'Proto3::WKT::Any'      ? $handler->to_json_value( $values, $codec, $self )
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
        return $self->_encode_float_json($value) if $type eq 'float' || $type eq 'double';
        if ( $NUMBER_TYPE{$type} ) {
            # A 32-bit int renders as a JSON number. A Math::BigInt would
            # serialize as a blessed object (JSON::PP rejects it), so numify it
            # to a native scalar first; the integer types are always in 32-bit
            # range here, so numify is exact.
            return ( ref $value && $value->can('numify') )
                ? $value->numify
                : $value + 0;
        }
        return "$value";    # string
    }

    # Render a float/double for proto3 JSON. Non-finite values use the spec's
    # string forms ("Infinity", "-Infinity", "NaN"); a finite value is emitted as
    # a JSON number with enough precision to round-trip (a raw number, wrapped so
    # JSON::PP emits it unquoted). Perl's default stringification can drop digits
    # (2.2250738585072014e-308 -> 2.2250738585072e-308), so format with %.17g and
    # trim, which is exact for IEEE-754 doubles.
    method _encode_float_json ($value) {
        my $n = ( ref $value && $value->can('numify') ) ? $value->numify : $value + 0;
        # Non-finite values use the spec's quoted string forms.
        return 'NaN'       if $n != $n;             # NaN is the only value != itself
        return 'Infinity'  if $n == 9**9**9;
        return '-Infinity' if $n == -9**9**9;
        # Shortest decimal that round-trips back to the same double (protoc's
        # shortest-round-trip output). Register it as a bare literal under a
        # unique sentinel; encode() swaps the quoted sentinel for the literal so
        # JSON::PP cannot re-truncate the precision.
        my $literal = sprintf '%.17g', $n;
        for my $p ( 1 .. 17 ) {
            my $s = sprintf "%.${p}g", $n;
            if ( ( $s + 0 ) == $n ) { $literal = $s; last }
        }
        # Sentinel uses only characters JSON::PP emits verbatim (no escaping), so
        # the post-serialization substitution can find the quoted token reliably.
        my $sentinel = '@@FLOATLITERAL' . scalar(keys %float_literal) . '@@';
        $float_literal{$sentinel} = $literal;
        return $sentinel;
    }

    # Encode a map field as a JSON object: each map key becomes an object key
    # (stringified, as JSON object keys are always strings), and each value is
    # encoded per the value field's kind via a synthetic value field.
    method _encode_map ($field, $entries, $opts) {
        my $entry_name = $self->_field_type_name($field);
        my $entry      = $schema->message($entry_name);
        my ($key_field) =
            grep { $_->number == 1 } @{ $entry->fields };
        my ($value_field) =
            grep { $_->number == 2 } @{ $entry->fields };
        my $key_type = $key_field ? $key_field->type : 'string';

        my %out;
        for my $key ( keys %$entries ) {
            $out{ $self->_encode_map_key( $key_type, $key ) } =
                $self->_encode_element( $value_field, $entries->{$key}, $opts );
        }
        return \%out;
    }

    # A proto3 map key is always a JSON object key (a string), but proto3 JSON
    # spells a bool key as "true"/"false" (not "1"/"0") — integer keys are their
    # decimal string, which is what stringification already gives.
    method _encode_map_key ($key_type, $key) {
        return ( $key ? 'true' : 'false' ) if $key_type eq 'bool';
        return "$key";
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

    # decode($full_name, $json_string, %opts) -> a field-name-keyed hashref.
    #
    # Parse the JSON text (a malformed document raises JSON::Parse) then map the
    # decoded JSON structure onto the message named $full_name, producing the same
    # hashref shape Proto3::Codec uses. Input is lenient per the proto3 JSON spec
    # (§4.9): both camelCase and snake_case keys, both string and number for
    # 64-bit integers, both name and number for enums. Option:
    #   reject_unknown_fields  raise JSON::Parse on a JSON key matching no field
    method decode ($full_name, $json_string, %opts) {
        my $parsed = $self->_parse_json($json_string);
        # A top-level JSON null is not a valid message (proto3 rejects it; only
        # a nested field may be null, leaving that field unset). A WKT with a
        # null special form (e.g. Value/NullValue) handles its own null.
        if ( !defined $parsed && !$self->_is_wkt($full_name) ) {
            Proto3::Exception::JSON::Parse->throw(
                message => "top-level null is not a valid $full_name",
            );
        }
        return $self->_from_json_structure( $full_name, $parsed, \%opts );
    }

    # Parse a JSON string, translating any JSON::PP failure into a
    # Proto3::Exception::JSON::Parse so callers see one library-native error type.
    method _parse_json ($json_string) {
        my $parsed = eval { JSON::PP->new->decode($json_string) };
        if ($@) {
            my $detail = $@;
            $detail =~ s/\s+\z//;
            Proto3::Exception::JSON::Parse->throw(
                message => "invalid JSON: $detail",
            );
        }
        return $parsed;
    }

    # Map a decoded JSON value ($json) onto the message named $full_name. A
    # well-known type with a special JSON form is delegated to its WKT
    # from_json_value handler; every other message walks the JSON object's keys.
    method _from_json_structure ($full_name, $json, $opts) {
        if ( $self->_is_wkt($full_name) ) {
            return $self->_wkt_from_json( $full_name, $json );
        }

        my $message = $schema->message($full_name);
        if ( !defined $message ) {
            Proto3::Exception::Codec::UnknownType->throw(
                message => "unknown message type: $full_name",
            );
        }

        # Index the message's fields by every JSON key that may name them: the
        # proto name, the camelCase json_name, and the snake_case spelling of the
        # json_name (so a camelCase incoming key and a snake_case one both hit).
        my %field_by_key;
        for my $field ( @{ $message->fields } ) {
            my $name = $field->name;
            my $json_name = $field->json_name // $camel_case->($name);
            $field_by_key{$name}                 = $field;
            $field_by_key{$json_name}            = $field;
            $field_by_key{ $snake_case->($json_name) } = $field;
        }

        my %out;
        my %oneof_seen;    # oneof_index -> the field name already taken
        for my $key ( keys %$json ) {
            my $field = $field_by_key{$key};
            if ( !$field ) {
                next unless $opts->{reject_unknown_fields};
                Proto3::Exception::JSON::Parse->throw(
                    message => "unknown field '$key' in message $full_name",
                );
            }
            my $value = $json->{$key};

            # A JSON null normally leaves a field unset. The exception is a
            # singular google.protobuf.Value (or NullValue) field, for which null
            # is a legitimate value (Value.null_value = NULL_VALUE), so it must be
            # decoded rather than skipped.
            next if !defined $value && !$self->_field_takes_json_null($field);

            # At most one member of a oneof may be present in the JSON object;
            # two members set is an error (proto3 OneofFieldDuplicate). A null
            # value above does not count as setting the field.
            if ( defined( my $idx = $field->oneof_index ) ) {
                if ( exists $oneof_seen{$idx} ) {
                    Proto3::Exception::JSON::Parse->throw(
                        message => sprintf(
                            'oneof in %s has multiple members set: %s and %s',
                            $full_name, $oneof_seen{$idx}, $field->name,
                        ),
                    );
                }
                $oneof_seen{$idx} = $field->name;
            }

            $out{ $field->name } =
                $self->_decode_field( $field, $value, $opts );
        }
        return \%out;
    }

    # Decode one JSON field value into its codec-shaped Perl value, dispatching by
    # field kind: map, repeated, singular message, enum, then scalar.
    method _decode_field ($field, $value, $opts) {
        return $self->_decode_map( $field, $value, $opts )    if $field->is_map;
        if ( $field->is_repeated ) {
            return [ map { $self->_decode_element( $field, $_, $opts ) }
                    @$value ];
        }
        return $self->_decode_message_value( $field, $value, $opts )
            if $field->is_message;
        return $self->_decode_enum( $field, $value ) if $field->is_enum;
        return $self->_decode_scalar( $field, $field->type, $value );
    }

    # Decode one element of a repeated field (a scalar, enum, or message). The
    # array container itself is handled by the caller.
    method _decode_element ($field, $value, $opts) {
        return $self->_decode_message_value( $field, $value, $opts )
            if $field->is_message;
        return $self->_decode_enum( $field, $value ) if $field->is_enum;
        return $self->_decode_scalar( $field, $field->type, $value );
    }

    # Decode a singular message-typed JSON value: delegate to the field type's WKT
    # from_json handler when it is a well-known type, else recurse as a nested
    # message.
    method _decode_message_value ($field, $value, $opts) {
        my $type_name = $self->_field_type_name($field);
        if ( $self->_is_wkt($type_name) ) {
            return $self->_wkt_from_json( $type_name, $value );
        }
        return $self->_from_json_structure( $type_name, $value, $opts );
    }

    # Decode an enum JSON value to its integer number. A string is looked up in
    # the enum's value table (its symbolic name); a number is taken as-is (an
    # unknown enumerator number is preserved, matching the binary codec).
    method _decode_enum ($field, $value) {
        # A JSON null is accepted only for a google.protobuf.NullValue enum, where
        # it denotes NULL_VALUE (0); _field_takes_json_null gates which nulls
        # reach here.
        return 0 if !defined $value;
        if ( !Scalar::Util::looks_like_number($value) ) {
            my $number = $self->_enum_number( $field, "$value" );
            if ( !defined $number ) {
                Proto3::Exception::Codec::TypeMismatch->throw(
                    message => sprintf(
                        'enum field %s has no value named %s',
                        $field->name, "'$value'",
                    ),
                );
            }
            return $number;
        }
        return $value + 0;
    }

    # The integer number of enumerator $name for an enum-typed field, or undef
    # when the enum or the name is unknown.
    method _enum_number ($field, $name) {
        my $enum = $self->_field_enum($field) or return undef;
        for my $v ( @{ $enum->values } ) {
            return $v->{number} if $v->{name} eq $name;
        }
        return undef;
    }

    # Decode a scalar JSON value per the field's proto3 type. 64-bit integers
    # accept both a JSON string and a JSON number; bytes decode from base64; bool
    # accepts JSON true/false (a JSON::PP::Boolean) and is normalized to 1/0; the
    # 32-bit integers and floats take the numeric value. A non-numeric value for a
    # numeric field raises TypeMismatch.
    method _decode_scalar ($field, $type, $value) {
        my $kind = $json_kind->($value);

        if ( $type eq 'bytes' ) {
            return MIME::Base64::decode_base64("$value");
        }
        if ( $type eq 'bool' ) {
            # A bool field accepts ONLY a JSON true/false, never a number or
            # string (proto3 rejects e.g. a string for a bool field).
            $self->_reject_value( $field, $type, $value )
                if $kind ne 'bool';
            return $value ? 1 : 0;
        }
        if ( $type eq 'string' ) {
            # A string field accepts ONLY a JSON string, never a number, bool,
            # array, or object (StringFieldNotAString).
            $self->_reject_value( $field, $type, $value )
                if $kind ne 'string';
            return "$value";
        }

        # Every remaining scalar type is numeric: the integers and the floats.
        if ( $INT_RANGE{$type} ) {
            return $self->_decode_integer( $field, $type, $value, $kind );
        }
        return $self->_decode_float( $field, $type, $value, $kind );
    }

    # Decode and validate a JSON value for an integer-typed field. proto3 accepts
    # both a bare JSON number and a quoted JSON string, but the value must denote
    # an integer in the type's range: a fractional number (0.5), a number out of
    # range, or a string that is not a clean decimal integer (" 1", "1 ", "1.5",
    # "1e5", "") is rejected. Returns a native integer when it fits, else a
    # Math::BigInt for exactness (64-bit values that overflow a native int).
    method _decode_integer ($field, $type, $value, $kind) {
        my $digits;
        if ( $kind eq 'string' ) {
            $self->_reject_value( $field, $type, $value )
                unless $is_integer_string->("$value");
            $digits = "$value";
        }
        elsif ( $kind eq 'number' ) {
            # A JSON number must be integral: no fractional or exponent part
            # that yields a non-integer. Stringify and require a clean integer.
            my $text = sprintf( '%s', $value );
            $self->_reject_value( $field, $type, $value )
                unless $is_integer_string->($text);
            $digits = $text;
        }
        else {
            $self->_reject_value( $field, $type, $value );
        }

        my $big = Math::BigInt->new($digits);
        my ( $min, $max ) = @{ $INT_RANGE{$type} };
        if ( $big < $min || $big > $max ) {
            $self->_reject_value( $field, $type, $value, 'out of range' );
        }

        # Reduce to a native integer when the magnitude is small enough to be
        # exact as a Perl double (<= 2^53); keep the Math::BigInt otherwise so
        # the wide 64-bit edge values stay exact for the binary re-encode.
        my $limit = Math::BigInt->new(2)->bpow(53);
        return $big->copy->babs <= $limit ? $big->numify : $big;
    }

    # Decode and validate a JSON value for a float/double field. A numeric JSON
    # literal whose magnitude overflows the type is rejected (FloatFieldTooLarge
    # /TooSmall, DoubleFieldTooSmall); a non-numeric, non-string value (bool,
    # array, object) is rejected as a type mismatch. A JSON string is left to the
    # existing numeric coercion (it carries the special "Infinity"/"NaN" forms).
    method _decode_float ($field, $type, $value, $kind) {
        if ( $kind eq 'number' ) {
            my $max = $FLOAT_MAX{$type};
            if ( abs( $value + 0 ) > $max ) {
                $self->_reject_value( $field, $type, $value, 'out of range' );
            }
            return $value + 0;
        }
        if ( $kind eq 'string' ) {
            $self->_reject_value( $field, $type, $value )
                unless Scalar::Util::looks_like_number($value);
            return $value + 0;
        }
        $self->_reject_value( $field, $type, $value );
    }

    # Raise the proto3 error for a JSON value that does not match its field's
    # type. Throws Proto3::Exception::Codec::TypeMismatch (the conformance
    # handler turns any thrown exception into a parse_error, and a value of the
    # wrong type is precisely a type mismatch).
    method _reject_value ($field, $type, $value, $reason = 'type mismatch') {
        my $shown = ref $value ? ref($value)
            : defined $value   ? "'$value'"
            :                    'null';
        Proto3::Exception::Codec::TypeMismatch->throw(
            message => sprintf(
                'field %s expected %s, got %s (%s)',
                $field->name, $type, $shown, $reason,
            ),
        );
    }

    # Decode a map field from a JSON object into a { key => value } hashref. Each
    # object value is decoded per the value field's kind (via the synthetic
    # value field at number 2 in the MapEntry).
    method _decode_map ($field, $object, $opts) {
        my $entry_name = $self->_field_type_name($field);
        my $entry      = $schema->message($entry_name);
        my ($key_field)   = grep { $_->number == 1 } @{ $entry->fields };
        my ($value_field) = grep { $_->number == 2 } @{ $entry->fields };

        my %out;
        for my $key ( keys %$object ) {
            my $decoded_key = $self->_decode_map_key( $key_field, $key );
            $out{$decoded_key} =
                $self->_decode_element( $value_field, $object->{$key}, $opts );
        }
        return \%out;
    }

    # Coerce a JSON object key (always a string) into the map key field's proto3
    # type. proto3 JSON renders every map key as a string, so an integer key
    # arrives as "42" and a bool key as "true"/"false"; both must map back to the
    # codec key form (a native integer or 1/0) so the binary re-encode and Perl
    # hash lookups behave. A bool key accepts only the literals "true"/"false".
    method _decode_map_key ($key_field, $key) {
        my $type = $key_field->type;
        if ( $type eq 'bool' ) {
            return 1 if $key eq 'true';
            return 0 if $key eq 'false';
            $self->_reject_value( $key_field, $type, $key );
        }
        return $key;
    }

    # True when $full_name is a well-known type with a special JSON form.
    method _is_wkt ($full_name) {
        return defined Proto3::WKT->json_handler($full_name);
    }

    # True when a JSON null is a real value for this singular field rather than an
    # "unset" marker. That holds only for a google.protobuf.Value field (null ->
    # Value.null_value) or a google.protobuf.NullValue enum field. A repeated or
    # map field never reaches here with a bare null, and every other field treats
    # null as unset.
    method _field_takes_json_null ($field) {
        return 0 if $field->is_repeated || $field->is_map;
        if ( $field->is_message ) {
            my $type = $self->_field_type_name($field);
            return $type eq 'google.protobuf.Value';
        }
        if ( $field->is_enum ) {
            my $type = $self->_field_type_name($field);
            return $type eq 'google.protobuf.NullValue';
        }
        return 0;
    }

    # --- structure bridge for the Any handler -------------------------------
    #
    # google.protobuf.Any's JSON form embeds the wrapped message's own JSON. The
    # Any handler holds the wrapped message as codec-shaped bytes, so it needs to
    # cross the binary <-> JSON boundary for the inner message. These three thin
    # methods expose exactly that, reusing the encoder's own conversion paths so
    # camelCase names, WKT special forms, and default-omit all apply inside an Any.

    # The JSON-shaped structure (hashref/arrayref/scalar) for a codec-shaped
    # message value named $full_name. For a special-form WKT this is the bare
    # special form (e.g. an RFC3339 string); for an ordinary message it is the
    # camelCase JSON object.
    method json_structure_for ($full_name, $values) {
        return $self->_to_json_structure( $full_name, $values, {} );
    }

    # The codec-shaped message value for a JSON structure $json named $full_name.
    # Inverse of json_structure_for.
    method message_from_json ($full_name, $json) {
        return $self->_from_json_structure( $full_name, $json, {} );
    }

    # True when $full_name has a special (non-plain-object) JSON form, so an Any
    # wrapping it must carry the form under a reserved "value" key rather than
    # inlining the wrapped message's fields beside "@type".
    method wkt_has_special_form ($full_name) {
        return $self->_is_wkt($full_name);
    }

    # Delegate $json to the WKT from_json_value handler for $full_name, wrapping
    # any failure (a malformed special form, e.g. a bad RFC3339 timestamp) as
    # Proto3::Exception::JSON::WKT. The handlers have differing arities — Any
    # needs the codec, the wrappers take the full name — so dispatch is per class.
    method _wkt_from_json ($full_name, $json) {
        my $handler = Proto3::WKT->json_handler($full_name);

        my $result = eval {
            $handler eq 'Proto3::WKT::Any'      ? $handler->from_json_value( $json, $codec, $self )
            : $handler eq 'Proto3::WKT::Wrappers' ? $handler->from_json_value( $full_name, $json )
            :                                       $handler->from_json_value($json);
        };
        if ($@) {
            my $err = $@;
            # A WKT handler that already raised a typed JSON::WKT error passes
            # through unchanged; any other failure is wrapped as one.
            die $err
                if Scalar::Util::blessed($err)
                && $err->isa('Proto3::Exception::JSON::WKT');
            my $detail = ref $err ? "$err" : $err;
            $detail =~ s/\s+\z//;
            Proto3::Exception::JSON::WKT->throw(
                message => "malformed JSON form for $full_name: $detail",
            );
        }
        return $result;
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

=head2 decode

    my $values = $json->decode( $full_name, $json_string, %opts );

Parse C<$json_string> and map it onto the message named C<$full_name>, returning
the same field-name-keyed hashref shape L<Proto3::Codec> uses (so it can be
re-encoded to the wire). Decoding is B<lenient> per the proto3 JSON spec; see
L</DECODING RULES>. The only option is C<< reject_unknown_fields => 1 >>.

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

=head1 DECODING RULES

C<decode> is deliberately B<lenient> on input, accepting more than C<encode>
produces (proto3 JSON spec, §4.9):

=over 4

=item *

B<Field names.> A JSON key may be either the field's B<camelCase> C<json_name>
or its raw B<snake_case> proto name; both resolve to the same field.

=item *

B<64-bit integers.> C<int64>, C<uint64>, C<fixed64>, and C<sfixed64> decode from
B<both> a quoted JSON string and a bare JSON number.

=item *

B<Enums.> An enum value decodes from B<both> its symbolic B<name> (a JSON
string) and its B<number>. An unknown enumerator number is preserved as the
integer.

=item *

B<Booleans> accept JSON C<true>/C<false> (normalized to C<1>/C<0>); B<bytes>
decode from a base64 string.

=item *

B<Null.> A JSON C<null> value leaves the field unset.

=item *

B<Unknown fields.> A JSON key matching no field is B<silently skipped> by
default; C<< reject_unknown_fields => 1 >> raises
L<Proto3::Exception::JSON::Parse> instead.

=item *

B<Maps> decode from JSON B<objects>; B<repeated> fields from JSON B<arrays>.

=item *

B<Well-known types.> A field (or top-level message) whose type has a special
JSON form is delegated to that type's C<from_json_value>, so e.g. an RFC3339
string decodes into a C<Timestamp>'s C<{ seconds, nanos }>.

=back

=head1 FAILURE MODES

=over 4

=item *

Malformed JSON text raises L<Proto3::Exception::JSON::Parse>.

=item *

A value whose type clashes with the field (e.g. a non-numeric string in an
C<int32>) raises L<Proto3::Exception::Codec::TypeMismatch>.

=item *

A well-known type with a malformed string form (e.g. a bad RFC3339 timestamp)
raises L<Proto3::Exception::JSON::WKT>.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
