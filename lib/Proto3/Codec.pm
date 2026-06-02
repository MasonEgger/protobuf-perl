# ABOUTME: Proto3::Codec — high-level encode/decode over a resolved Schema; §4.5.
# Singular scalars, packed/unpacked repeated, key-sorted maps, recursive nested
# messages, enums-as-varint, oneof, and opt-in unknown-field preservation.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Scalar::Util ();
use Math::BigInt ();
use Proto3::Exception;
use Proto3::Wire ();
use Proto3::Wire::Tag ();

# 2**64 and 2**63 as Math::BigInt, used to convert negative int32/int64 values
# to and from their proto3 two's-complement 64-bit varint representation. proto3
# encodes a negative int32/int64 as the full 64-bit two's complement (always a
# 10-byte varint), so a signed varint round-trips through the unsigned 64-bit
# range. Pre-class lexicals (the feature 'class' package-scoping trap).
my $TWO_64 = Math::BigInt->new(2)->bpow(64);
my $TWO_63 = Math::BigInt->new(2)->bpow(63);

# Signed int32/int64 helpers as anonymous coderefs in pre-class lexicals. They
# live inside a `do {}` block on purpose: this Perl 5.38.2 build mis-parses a
# file-scope `sub (signature)` that immediately precedes a `class` block
# ("Subroutine attributes must come before the signature"); the `do {}` wrapper
# insulates the signatures, the same trick %SCALAR_TYPE already relies on.
my ( $normalize_int, $encode_signed_varint, $decode_signed_varint ) = do {

    # Reduce a Math::BigInt to a native Perl integer when it fits the native
    # signed 64-bit range, so decoded values compare cleanly against plain
    # numbers; values outside that range stay Math::BigInt for exactness.
    my $norm = sub ($big) {
        return 0 if $big->is_zero;
        return $big->numify if $big->copy->babs->blt($TWO_63);
        return $big;
    };

    # Encode a signed int32/int64 as a proto3 varint. A non-negative value
    # encodes as a plain varint; a negative value encodes as its 64-bit two's
    # complement (2**64 + value), matching protoc (always 10 bytes).
    my $enc = sub ($value) {
        my $big = ( ref $value && $value->isa('Math::BigInt') )
            ? $value->copy
            : Math::BigInt->new("$value");
        $big->badd($TWO_64) if $big->is_neg;
        return Proto3::Wire::encode_varint($big);
    };

    # Decode a proto3 signed int32/int64 varint off the front of $bytes. Reads
    # the unsigned 64-bit varint, then reinterprets a value with the high bit set
    # as the corresponding negative two's-complement integer. Returns
    # ($value, $rest).
    my $dec = sub ($bytes) {
        my ( $u, $rest ) = Proto3::Wire::decode_varint($bytes);
        my $big = ref $u ? $u->copy : Math::BigInt->new("$u");
        $big->bsub($TWO_64) if $big->bcmp($TWO_63) >= 0;    # high bit -> negative
        return ( $norm->($big), $rest );
    };

    ( $norm, $enc, $dec );
};

# Scalar-type encoding table — the single source of truth for how each proto3
# scalar wire-encodes. Held as a pre-class lexical so methods read it without
# tripping the feature 'class' package-scoping trap (an imported/constant sub or
# our-variable would land in the file package, not the class package, and die at
# runtime). Later codec/JSON/codegen steps reuse this table (plan §1282).
#
# Each entry is a hashref:
#   wire    : the wire type constant (varint/i32/i64/len)
#   encode  : ($value) -> the field PAYLOAD bytes (no tag)
#   decode  : ($bytes) -> ($value, $rest); reads one field payload off the front
#             of $bytes (the tag is already consumed) and returns the value plus
#             the unconsumed remainder.
#   is_num  : true if the value must look like a number (TypeMismatch otherwise)
#   default : the proto3 implicit-presence default; a singular (non-optional)
#             field whose value equals this is omitted from the wire, and an
#             omitted implicit-presence field decodes back to it.
my %SCALAR_TYPE = do {
    my $W_VARINT = Proto3::Wire::Tag::WIRE_VARINT();
    my $W_I64    = Proto3::Wire::Tag::WIRE_I64();
    my $W_LEN    = Proto3::Wire::Tag::WIRE_LEN();
    my $W_I32    = Proto3::Wire::Tag::WIRE_I32();

    my $varint  = sub ($v) { Proto3::Wire::encode_varint($v) };
    # int32/int64 use signed-varint semantics: negatives become the 64-bit
    # two's complement, matching protoc. uint32/uint64/bool/enum stay unsigned.
    my $signed  = sub ($v) { $encode_signed_varint->($v) };
    my $zigzag32 = sub ($v) { Proto3::Wire::encode_zigzag32($v) };
    my $zigzag64 = sub ($v) { Proto3::Wire::encode_zigzag64($v) };
    my $bool    = sub ($v) { Proto3::Wire::encode_varint( $v ? 1 : 0 ) };
    my $fixed32 = sub ($v) { Proto3::Wire::encode_fixed32($v) };
    my $fixed64 = sub ($v) { Proto3::Wire::encode_fixed64($v) };
    my $float   = sub ($v) { Proto3::Wire::encode_float($v) };
    my $double  = sub ($v) { Proto3::Wire::encode_double($v) };
    # Length-delimited: a varint byte-count prefix, then the raw payload.
    my $len     = sub ($v) {
        my $bytes = "$v";
        return Proto3::Wire::encode_varint( length $bytes ) . $bytes;
    };

    # --- decoders (mirror the encoders; the table is the single dispatch) ---
    # Every decoder returns ($value, $rest). decode_zigzag* yield only the value,
    # so we read the varint separately to recover the unconsumed remainder.
    my $d_varint   = sub ($b) { Proto3::Wire::decode_varint($b) };
    my $d_signed   = sub ($b) { $decode_signed_varint->($b) };
    my $d_zigzag32 = sub ($b) {
        my ( undef, $rest ) = Proto3::Wire::decode_varint($b);
        return ( Proto3::Wire::decode_zigzag32($b), $rest );
    };
    my $d_zigzag64 = sub ($b) {
        my ( undef, $rest ) = Proto3::Wire::decode_varint($b);
        return ( Proto3::Wire::decode_zigzag64($b), $rest );
    };
    # bool normalizes any non-zero varint to 1 and zero to 0.
    my $d_bool     = sub ($b) {
        my ( $v, $rest ) = Proto3::Wire::decode_varint($b);
        return ( ( $v ? 1 : 0 ), $rest );
    };
    my $d_fixed32  = sub ($b) { Proto3::Wire::decode_fixed32($b) };
    my $d_fixed64  = sub ($b) { Proto3::Wire::decode_fixed64($b) };
    my $d_float    = sub ($b) { Proto3::Wire::decode_float($b) };
    my $d_double   = sub ($b) { Proto3::Wire::decode_double($b) };
    # Length-delimited: a varint byte-count prefix, then that many raw bytes.
    my $d_len      = sub ($b) {
        my ( $n, $rest ) = Proto3::Wire::decode_varint($b);
        $n = $n->numify if ref $n;
        if ( length($rest) < $n ) {
            Proto3::Exception::Wire::Truncated->throw(
                message => "expected $n bytes, got " . length($rest),
            );
        }
        return ( substr( $rest, 0, $n ), substr( $rest, $n ) );
    };

    (
        int32    => { wire => $W_VARINT, encode => $signed,   decode => $d_signed,   is_num => 1, default => 0 },
        int64    => { wire => $W_VARINT, encode => $signed,   decode => $d_signed,   is_num => 1, default => 0 },
        uint32   => { wire => $W_VARINT, encode => $varint,   decode => $d_varint,   is_num => 1, default => 0 },
        uint64   => { wire => $W_VARINT, encode => $varint,   decode => $d_varint,   is_num => 1, default => 0 },
        bool     => { wire => $W_VARINT, encode => $bool,     decode => $d_bool,     is_num => 1, default => 0 },
        enum     => { wire => $W_VARINT, encode => $varint,   decode => $d_varint,   is_num => 1, default => 0 },
        sint32   => { wire => $W_VARINT, encode => $zigzag32, decode => $d_zigzag32, is_num => 1, default => 0 },
        sint64   => { wire => $W_VARINT, encode => $zigzag64, decode => $d_zigzag64, is_num => 1, default => 0 },
        fixed32  => { wire => $W_I32,    encode => $fixed32,  decode => $d_fixed32,  is_num => 1, default => 0 },
        sfixed32 => { wire => $W_I32,    encode => $fixed32,  decode => $d_fixed32,  is_num => 1, default => 0 },
        float    => { wire => $W_I32,    encode => $float,    decode => $d_float,    is_num => 1, default => 0 },
        fixed64  => { wire => $W_I64,    encode => $fixed64,  decode => $d_fixed64,  is_num => 1, default => 0 },
        sfixed64 => { wire => $W_I64,    encode => $fixed64,  decode => $d_fixed64,  is_num => 1, default => 0 },
        double   => { wire => $W_I64,    encode => $double,   decode => $d_double,   is_num => 1, default => 0 },
        string   => { wire => $W_LEN,    encode => $len,      decode => $d_len,      is_num => 0, default => '' },
        bytes    => { wire => $W_LEN,    encode => $len,      decode => $d_len,      is_num => 0, default => '' },
    );
};

# The proto3 scalar types permitted as a map key (spec §4.5): every integral
# type, plus bool and string. Floating-point, bytes, enum, and message keys are
# forbidden. Held as a pre-class lexical for the same package-scoping reason as
# %SCALAR_TYPE above. Consulted once per map field at codec construction.
my %ALLOWED_MAP_KEY_TYPE = map { $_ => 1 } qw(
    int32 int64 uint32 uint64 sint32 sint64
    fixed32 fixed64 sfixed32 sfixed64
    bool string
);

# The result-hashref key under which decode stores the raw bytes of any unknown
# fields when preserve_unknown_fields is on, and from which encode re-emits them
# after the known fields. A pre-class lexical (the feature 'class' scoping trap).
my $UNKNOWN_FIELDS_KEY = '__unknown_fields__';

class Proto3::Codec {
    field $schema :param;

    # When true, decode preserves the raw bytes of unrecognized fields under the
    # result's __unknown_fields__ key, and encode re-emits them verbatim after
    # the known fields, so an unknown-field-bearing message survives a
    # decode/encode round-trip byte-for-byte (spec §4.5, §5.3). Default off: an
    # unknown field is skipped on decode and never resurrected on encode.
    field $preserve_unknown_fields :param = 0;

    method schema { $schema }

    method preserve_unknown_fields { $preserve_unknown_fields }

    # Validate every map field's key type at construction (spec §4.5): a map key
    # must be an integral type, bool, or string. A disallowed key (float/double/
    # bytes/enum/message) raises Proto3::Exception::Schema here, when the codec
    # is built for a schema containing the offending map — not lazily at encode
    # time. A map field is modeled as a repeated field whose element is a
    # synthetic MapEntry message (is_map_entry) with key=field 1, value=field 2.
    ADJUST {
        for my $message ( @{ $schema->all_messages } ) {
            next unless $message->is_map_entry;
            $self->_assert_map_key_type($message);
        }
    }

    # Raise Schema when the MapEntry's key field (field 1) is not a permitted
    # map-key type. The MapEntry is the synthetic message a map field points to.
    method _assert_map_key_type ($map_entry) {
        my ($key_field) =
            grep { $_->number == 1 } @{ $map_entry->fields };
        return unless $key_field;    # malformed entry; nothing to validate

        my $key_type = $key_field->type;
        return if $ALLOWED_MAP_KEY_TYPE{$key_type};

        Proto3::Exception::Schema->throw(
            message => sprintf(
                'map %s has disallowed key type %s '
                    . '(map keys must be integral, bool, or string)',
                $map_entry->full_name, $key_type,
            ),
        );
    }

    # encode($full_name, $hashref) -> wire bytes.
    #
    # Looks up the message by fully-qualified name (UnknownType if absent),
    # then walks its fields in field-number order, emitting each present field:
    # singular scalars/enums (default-omitted unless explicit-presence),
    # repeated and map fields, and recursively-encoded singular messages. Fields
    # declared `optional` and oneof members use explicit-presence semantics: a
    # set value is always emitted, even at the type default.
    #
    # When preserve_unknown_fields is on and the value carries preserved unknown
    # bytes under __unknown_fields__ (typically from a prior decode), those bytes
    # are appended verbatim after the known fields, so a decode/encode round-trip
    # reproduces an unknown-field-bearing message byte-for-byte.
    method encode ($full_name, $values) {
        my $message = $schema->message($full_name);
        if ( !defined $message ) {
            Proto3::Exception::Codec::UnknownType->throw(
                message => "unknown message type: $full_name",
            );
        }

        my @fields =
            sort { $a->number <=> $b->number } @{ $message->fields };

        my $out = '';
        for my $field (@fields) {
            $out .= $self->_encode_field( $field, $values );
        }

        if ( $preserve_unknown_fields
            && defined $values->{$UNKNOWN_FIELDS_KEY} )
        {
            $out .= $values->{$UNKNOWN_FIELDS_KEY};
        }

        return $out;
    }

    # Encode one field given the message value hashref. Returns the field's
    # tag-prefixed bytes, or '' when the field is absent or default-omitted.
    method _encode_field ($field, $values) {
        my $name = $field->name;
        return '' unless exists $values->{$name};

        my $value = $values->{$name};
        return '' unless defined $value;

        return $self->_encode_map( $field, $value )      if $field->is_map;
        return $self->_encode_repeated( $field, $value ) if $field->is_repeated;

        # Singular embedded message: length-delimited recursive encode via the
        # single shared embedded-message writer (the same path used by map
        # entries and repeated-message elements). An unset message field never
        # reaches here (the exists/defined guards above omit it); a present but
        # empty-hashref message still emits a zero-length LEN entry.
        return $self->_encode_embedded_message(
            $field->number, $self->_field_message_name($field), $value,
        ) if $field->is_message;

        return $self->_encode_singular_scalar( $field, $value );
    }

    # Encode a singular scalar field's tag-prefixed bytes (or '' when the value
    # is the implicit-presence default for a non-optional field).
    method _encode_singular_scalar ($field, $value) {
        my $spec = $SCALAR_TYPE{ $field->type };
        return '' unless $spec;    # message/group handled elsewhere

        # Validate the value's type first: a non-numeric value for a numeric
        # field must raise TypeMismatch, not be silently coerced to 0 and then
        # dropped by the default-omit check below.
        $self->_assert_value_type( $field, $spec, $value );

        # A field with explicit presence is always written when set, even at the
        # type default: that covers both `optional` fields and oneof members
        # (presence in a oneof is "this member is the one set", independent of
        # the value). Implicit-presence singular scalars at their default are
        # omitted from the wire.
        if ( !$self->_has_explicit_presence($field)
            && $self->_is_default_value( $spec, $value ) )
        {
            return '';
        }

        my $tag = Proto3::Wire::Tag::encode_tag( $field->number, $spec->{wire} );
        return $tag . $spec->{encode}->($value);
    }

    # True when a field uses explicit-presence serialization: it is declared
    # `optional`, or it is a member of a oneof. Such a field is serialized
    # whenever it is set, even when its value equals the type default.
    method _has_explicit_presence ($field) {
        return 1 if $field->label eq 'optional';
        return 1 if defined $field->oneof_index;
        return 0;
    }

    # Encode a repeated field. $elements is the field's arrayref value.
    #
    # An empty list is omitted entirely. Packable scalars (numeric/bool/enum)
    # are emitted as a SINGLE length-delimited block of concatenated element
    # payloads (proto3 packed-by-default). String/bytes/message elements are not
    # packable: each is emitted as its own tag-prefixed entry, in list order.
    method _encode_repeated ($field, $elements) {
        return '' unless @$elements;

        my $spec = $SCALAR_TYPE{ $field->type };

        if ( $spec && $self->_is_packable( $field->type ) ) {
            my $payload = '';
            for my $element (@$elements) {
                $self->_assert_value_type( $field, $spec, $element );
                $payload .= $spec->{encode}->($element);
            }
            my $tag = Proto3::Wire::Tag::encode_tag(
                $field->number,
                Proto3::Wire::Tag::WIRE_LEN(),
            );
            return $tag
                . Proto3::Wire::encode_varint( length $payload )
                . $payload;
        }

        # Unpacked path: one tag-prefixed entry per element.
        my $out = '';
        for my $element (@$elements) {
            $out .= $self->_encode_repeated_element( $field, $spec, $element );
        }
        return $out;
    }

    # Encode one element of a non-packed repeated field (string/bytes scalar, or
    # an embedded message) as its own tag-prefixed entry.
    method _encode_repeated_element ($field, $spec, $element) {
        if ($spec) {    # length-delimited scalar (string/bytes)
            $self->_assert_value_type( $field, $spec, $element );
            my $tag = Proto3::Wire::Tag::encode_tag(
                $field->number, $spec->{wire},
            );
            return $tag . $spec->{encode}->($element);
        }

        # Embedded message element: encode recursively, then tag + length-prefix.
        return $self->_encode_embedded_message(
            $field->number,
            $self->_field_message_name($field),
            $element,
        );
    }

    # Encode one embedded (length-delimited) message field: recursively encode
    # the value hashref as $message_name, then emit tag(field_number, LEN) + a
    # varint byte-count + the message bytes. The single embedded-message writer,
    # shared by singular message fields, repeated-message elements, and map
    # entries — recursion through encode() handles arbitrarily deep nesting.
    method _encode_embedded_message ($field_number, $message_name, $value) {
        my $bytes = $self->encode( $message_name, $value );
        my $tag =
            Proto3::Wire::Tag::encode_tag( $field_number,
            Proto3::Wire::Tag::WIRE_LEN() );
        return $tag . Proto3::Wire::encode_varint( length $bytes ) . $bytes;
    }

    # Encode a map field. $entries is the field's hashref value ({ key => value
    # }). A map is wire-equivalent to a repeated synthetic MapEntry message with
    # key=field 1 and value=field 2: each pair becomes an embedded MapEntry under
    # the map field's number. Entries are emitted sorted by key for deterministic
    # output (proto3 leaves map order unspecified; we make it stable). An empty
    # map is omitted entirely.
    method _encode_map ($field, $entries) {
        return '' unless %$entries;

        my $entry_name = $self->_field_message_name($field);
        my $key_type   = $self->_map_key_type($entry_name);

        my $out = '';
        for my $key ( $self->_sorted_map_keys( $key_type, [ keys %$entries ] ) )
        {
            $out .= $self->_encode_embedded_message(
                $field->number,
                $entry_name,
                { key => $key, value => $entries->{$key} },
            );
        }
        return $out;
    }

    # The proto3 type of a MapEntry's key field (field 1), used to choose a
    # deterministic key sort and to drive validation. Returns undef if absent.
    method _map_key_type ($entry_name) {
        my $entry = $schema->message($entry_name) or return undef;
        my ($key_field) = grep { $_->number == 1 } @{ $entry->fields };
        return $key_field ? $key_field->type : undef;
    }

    # Order map keys deterministically: numeric key types sort numerically so
    # 2 precedes 10; string (and bool, treated as text) keys sort as strings.
    method _sorted_map_keys ($key_type, $keys) {
        my $spec = $key_type ? $SCALAR_TYPE{$key_type} : undef;
        if ( $spec && $spec->{is_num} && $key_type ne 'bool' ) {
            return sort { $a <=> $b } @$keys;
        }
        return sort @$keys;
    }

    # The fully-qualified message name for a message-typed field. Prefers the
    # resolved $type_ref (set by Schema->resolve); falls back to the raw
    # $type_name so directly-constructed schemas work without a resolve pass.
    method _field_message_name ($field) {
        my $ref = $field->type_ref;
        return $ref->full_name if $ref;
        return $field->type_name;
    }

    # True when a proto3 scalar type uses packed encoding for repeated fields:
    # every numeric/bool/enum type is packable; string and bytes are not.
    method _is_packable ($type) {
        my $spec = $SCALAR_TYPE{$type};
        return 0 unless $spec;
        return $spec->{is_num} ? 1 : 0;
    }

    # True when $value is the proto3 implicit-presence default for the scalar
    # described by $spec. Numeric types compare numerically (0 == 0.0 == "0");
    # string/bytes compare as the empty string. Only consulted for singular
    # (non-optional) scalar fields.
    method _is_default_value ($spec, $value) {
        return $value == $spec->{default} if $spec->{is_num};
        return length("$value") == 0;
    }

    # Raise Codec::TypeMismatch when $value is unusable for the field's type:
    # numeric types require a number-looking value; string/bytes accept any
    # non-reference scalar. The message names the field, expected type, and the
    # value actually received.
    method _assert_value_type ($field, $spec, $value) {
        my $bad = 0;
        if ( ref $value ) {
            # A blessed Math::BigInt is a legitimate numeric value; any other
            # reference is a type error for a scalar field.
            $bad = 1
                unless $spec->{is_num}
                && Scalar::Util::blessed($value)
                && $value->isa('Math::BigInt');
        }
        elsif ( $spec->{is_num} ) {
            $bad = 1 unless Scalar::Util::looks_like_number($value);
        }

        return unless $bad;

        my $got = ref $value ? ( ref $value ) : "'$value'";
        Proto3::Exception::Codec::TypeMismatch->throw(
            message => sprintf(
                'field %s expected %s, got %s',
                $field->name, $field->type, $got,
            ),
        );
    }

    # decode($full_name, $bytes) -> hashref of field name => value.
    #
    # Looks up the message by fully-qualified name (UnknownType if absent), then
    # walks the wire byte-by-record: read each tag, and if the field number is
    # known decode its singular scalar value (last value wins on a duplicate
    # tag); unknown field numbers are skipped by their wire type and left out of
    # the result. After the loop, implicit-presence singular scalar fields that
    # never appeared are set to their proto3 default; explicit-presence
    # (`optional`) fields that never appeared stay absent. Wire-level errors
    # (DeprecatedGroup, Truncated) propagate from the wire layer.
    method decode ($full_name, $bytes) {
        my $message = $schema->message($full_name);
        if ( !defined $message ) {
            Proto3::Exception::Codec::UnknownType->throw(
                message => "unknown message type: $full_name",
            );
        }

        # Index the message's fields by number for O(1) tag dispatch.
        my %field_by_number =
            map { $_->number => $_ } @{ $message->fields };

        # Index oneof members by oneof_index so a newly-decoded member can clear
        # any earlier-set sibling (proto3 oneof last-wins).
        my %oneof_members;
        for my $f ( @{ $message->fields } ) {
            next unless defined $f->oneof_index;
            push @{ $oneof_members{ $f->oneof_index } }, $f->name;
        }

        my %result;
        my $unknown = '';    # accumulated raw bytes of unknown fields, in order
        my $rest = $bytes;
        while ( length $rest ) {
            # Remember the record start (tag included) so an unknown field's full
            # tag+payload bytes can be captured verbatim for preservation.
            my $record_start = $rest;

            ( my $field_number, my $wire_type, $rest ) =
                Proto3::Wire::Tag::decode_tag($rest);

            my $field = $field_by_number{$field_number};

            # Unknown field number: drain it by wire type. With preservation on,
            # capture the whole record (tag + payload) verbatim; otherwise drop.
            if ( !$field ) {
                my $after = Proto3::Wire::skip_field( $wire_type, $rest );
                if ($preserve_unknown_fields) {
                    my $consumed = length($record_start) - length($after);
                    $unknown .= substr( $record_start, 0, $consumed );
                }
                $rest = $after;
                next;
            }

            if ( $field->is_map ) {
                $rest = $self->_decode_map( $field, $rest, \%result );
                next;
            }

            if ( $field->is_repeated ) {
                $rest = $self->_decode_repeated(
                    $field, $wire_type, $rest, \%result,
                );
                next;
            }

            # Singular embedded message: decode recursively via the single
            # shared embedded-message reader (the same path that handles map
            # entries and repeated-message elements). Last occurrence wins.
            if ( $field->is_message ) {
                ( my $value, $rest ) = $self->_decode_embedded_message(
                    $self->_field_message_name($field), $rest,
                );
                $result{ $field->name } = $value;
                $self->_clear_oneof_siblings( $field, \%result,
                    \%oneof_members );
                next;
            }

            my $spec = $SCALAR_TYPE{ $field->type };

            # Known singular field with no scalar spec: drain it by wire type and
            # drop it. (All proto3 scalar/enum types have a spec; this guards
            # only against an unexpected non-scalar singular type.)
            if ( !$spec ) {
                $rest = Proto3::Wire::skip_field( $wire_type, $rest );
                next;
            }

            ( my $value, $rest ) = $spec->{decode}->($rest);
            $result{ $field->name } = $value;    # last value wins
            $self->_clear_oneof_siblings( $field, \%result, \%oneof_members );
        }

        $self->_apply_defaults( $message, \%result );

        # Surface preserved unknown bytes only when there are any, so a message
        # with no unknown fields keeps the marker key absent.
        $result{$UNKNOWN_FIELDS_KEY} = $unknown if length $unknown;

        return \%result;
    }

    # Decode one wire occurrence of a repeated field, appending its element(s) to
    # $result->{field-name} (an arrayref) in order. Returns the unconsumed bytes.
    #
    # Lenient by design: a packable scalar field accepts BOTH the packed LEN
    # block (concatenated payloads under one tag) AND the unpacked form (one tag
    # per element), and mixed occurrences for the same field concatenate in wire
    # order. String/bytes/message elements arrive one tag-prefixed entry at a
    # time.
    method _decode_repeated ($field, $wire_type, $rest, $result) {
        my $list = $result->{ $field->name } //= [];
        my $spec = $SCALAR_TYPE{ $field->type };

        # Packable scalar carried in a LEN block: read the whole block and
        # decode each element from it. (Distinguished from the unpacked form by
        # the wire type: a packed block is WIRE_LEN; an unpacked element uses the
        # scalar's native wire type.)
        if (   $spec
            && $self->_is_packable( $field->type )
            && $wire_type == Proto3::Wire::Tag::WIRE_LEN() )
        {
            ( my $block, $rest ) = $self->_read_packed_block($rest);
            push @$list, $self->_decode_packed_elements( $spec, $block );
            return $rest;
        }

        # Embedded message element: read its LEN block and decode recursively.
        if ( !$spec || $field->is_message ) {
            ( my $value, $rest ) = $self->_decode_embedded_message(
                $self->_field_message_name($field), $rest,
            );
            push @$list, $value;
            return $rest;
        }

        # Unpacked scalar element (also the only path for string/bytes): one
        # element under one tag.
        ( my $value, $rest ) = $spec->{decode}->($rest);
        push @$list, $value;
        return $rest;
    }

    # Decode one embedded (length-delimited) message off the front of $bytes:
    # read its LEN block then recursively decode it as $message_name. Returns
    # ($value_hashref, $rest). The single embedded-message reader, shared by
    # singular message fields, repeated-message elements, and map entries —
    # recursion through decode() handles arbitrarily deep nesting.
    method _decode_embedded_message ($message_name, $bytes) {
        my ( $block, $rest ) = $self->_read_packed_block($bytes);
        return ( $self->decode( $message_name, $block ), $rest );
    }

    # Decode one wire occurrence of a map field: a single embedded MapEntry
    # message under the map field's tag. The entry decodes to { key => ...,
    # value => ... }; we collapse it into $result->{field-name}{key} = value.
    # Duplicate keys keep the last occurrence (proto3 map last-wins). Returns the
    # unconsumed bytes. An always-present (possibly empty) hashref is ensured so
    # a declared map with no entries on the wire still decodes to {}.
    method _decode_map ($field, $rest, $result) {
        my $map = $result->{ $field->name } //= {};

        ( my $entry, $rest ) = $self->_decode_embedded_message(
            $self->_field_message_name($field), $rest,
        );

        # MapEntry omits a default-valued key/value on the wire. _apply_defaults
        # restores a scalar key/value to its proto3 zero; a message-typed value
        # left off the wire defaults to an empty message hashref here.
        my $key   = $entry->{key};
        my $value = exists $entry->{value} ? $entry->{value} : {};
        $map->{$key} = $value;    # last value wins per key
        return $rest;
    }

    # Read a length-delimited block: a varint byte-count prefix followed by that
    # many raw bytes. Returns ($block, $rest). Truncation raises Wire::Truncated.
    method _read_packed_block ($bytes) {
        my ( $n, $rest ) = Proto3::Wire::decode_varint($bytes);
        $n = $n->numify if ref $n;
        if ( length($rest) < $n ) {
            Proto3::Exception::Wire::Truncated->throw(
                message => "expected $n bytes, got " . length($rest),
            );
        }
        return ( substr( $rest, 0, $n ), substr( $rest, $n ) );
    }

    # Decode every scalar element packed into $block using $spec's decoder.
    # Returns the list of decoded values, in order.
    method _decode_packed_elements ($spec, $block) {
        my @values;
        my $rest = $block;
        while ( length $rest ) {
            ( my $value, $rest ) = $spec->{decode}->($rest);
            push @values, $value;
        }
        return @values;
    }

    # Fill in proto3 defaults for declared fields that did not appear on the
    # wire. A repeated field defaults to the empty list. An implicit-presence
    # singular scalar defaults to its proto3 zero value; explicit-presence
    # (`optional`) fields and singular message fields are left absent.
    method _apply_defaults ($message, $result) {
        for my $field ( @{ $message->fields } ) {
            next if exists $result->{ $field->name };

            if ( $field->is_map ) {
                $result->{ $field->name } = {};
                next;
            }

            if ( $field->is_repeated ) {
                $result->{ $field->name } = [];
                next;
            }

            next if $field->label eq 'optional';
            next if $field->is_message;

            # A oneof member has explicit presence: if it was not on the wire it
            # stays absent (filling it with a default would set every member of
            # the oneof at once).
            next if defined $field->oneof_index;

            my $spec = $SCALAR_TYPE{ $field->type };
            next unless $spec;

            $result->{ $field->name } = $spec->{default};
        }
        return;
    }

    # Enforce oneof last-wins after decoding member $field: delete any other
    # member of the same oneof from $result, so only the most recently seen
    # member of the group survives. $oneof_members maps oneof_index to the list
    # of member field names. A no-op for fields not in any oneof.
    method _clear_oneof_siblings ($field, $result, $oneof_members) {
        my $index = $field->oneof_index;
        return unless defined $index;

        for my $sibling ( @{ $oneof_members->{$index} } ) {
            next if $sibling eq $field->name;
            delete $result->{$sibling};
        }
        return;
    }
}

1;

__END__

=head1 NAME

Proto3::Codec - high-level proto3 encode/decode over a resolved schema

=head1 SYNOPSIS

    use Proto3::Codec;

    my $codec = Proto3::Codec->new( schema => $schema );
    my $bytes = $codec->encode( 'pkg.M', { f => 42 } );

=head1 DESCRIPTION

C<Proto3::Codec> encodes (and, in later steps, decodes) message values against a
resolved L<Proto3::Schema>. Values are plain Perl hashrefs keyed by field name.

It implements C<encode> and C<decode> for B<singular scalar>, B<repeated>,
B<map>, B<singular embedded-message>, B<enum>, and B<oneof> fields. Nested
messages recurse through the same encode/decode entry points, so arbitrarily
deep message trees round-trip.

=head1 METHODS

=head2 new

    my $codec = Proto3::Codec->new( schema => $schema );
    my $codec = Proto3::Codec->new(
        schema                  => $schema,
        preserve_unknown_fields => 1,
    );

Construct a codec bound to a L<Proto3::Schema>. The schema should already be
resolved (see L<Proto3::Schema/resolve>) for message-typed fields, though that
matters only once those are encoded.

The optional C<preserve_unknown_fields> flag (default off) turns on
unknown-field retention across a decode/encode round-trip; see
L</UNKNOWN-FIELD PRESERVATION>.

At construction every map field's B<key type> is validated: a map key must be
an integral type, C<bool>, or C<string>. A schema containing a map with a
C<float>, C<double>, C<bytes>, C<enum>, or message key makes C<new> raise
L<Proto3::Exception::Schema> immediately, rather than failing later at encode
time.

=head2 encode

    my $bytes = $codec->encode( $full_name, \%values );

Encode the hashref C<\%values> as the message named C<$full_name> (a
fully-qualified, dotted name). Fields are emitted in ascending field-number
order.

=head2 decode

    my $values = $codec->decode( $full_name, $bytes );

Decode wire C<$bytes> into a hashref keyed by field name, for the message named
C<$full_name>. The wire is read record-by-record: each tag is dispatched on its
field number, known singular scalar fields are decoded by type, and a duplicate
tag for a singular field keeps the last value seen.

=head1 ENCODING BEHAVIOR

=over 4

=item *

B<Default-omit (implicit presence).> A singular scalar field whose value equals
its proto3 default (C<0> for numerics and bool, C<""> for string/bytes) is
omitted from the wire entirely. An absent or C<undef> field is likewise omitted.

=item *

B<Explicit presence.> A field declared C<optional> is always serialized when its
value is set, even at the type default. C<< { f => 0 } >> for an C<optional
int32> emits two bytes; the same for an implicit-presence C<int32> emits
nothing.

=item *

B<Scalar dispatch.> Each scalar type maps to a wire type and encoder via a
single internal table (varint for the integer/bool/enum types, zigzag for
C<sint32>/C<sint64>, fixed32/fixed64 for the fixed and floating forms, and
length-delimited for C<string>/C<bytes>). That table is the shared source later
codec, JSON, and code-generation steps build on.

=item *

B<Repeated fields.> A repeated field's value is an arrayref. A packable scalar
(any numeric, C<bool>, or C<enum> type) is B<packed by default>: all element
payloads are concatenated into one length-delimited block under a single tag. A
repeated C<string>, C<bytes>, or message field is emitted as one tag-prefixed
entry per element, in list order. An empty (or absent) repeated field is omitted
from the wire entirely.

=item *

B<Map fields.> A map field's value is a hashref. On the wire a map is
B<repeated synthetic MapEntry>: each pair is an embedded message with C<key> at
field 1 and C<value> at field 2, emitted under the map field's number. Entries
are written B<sorted by key> (numeric key types numerically, string/bool keys
as text) so the encoding is deterministic, even though proto3 leaves map order
unspecified. An empty (or absent) map is omitted from the wire entirely.

=item *

B<Singular message fields.> A singular message field's value is a hashref,
encoded recursively and wrapped as one length-delimited entry (wire type 2). A
field that is absent (or C<undef>) is omitted entirely; a present but empty
hashref still emits a zero-length entry. Nested messages recurse through the
same writer, so arbitrarily deep trees encode.

=item *

B<Enum fields.> An enum is carried as the varint integer value (no symbol
table is consulted). It follows the same implicit-presence default-omit rule as
the other varint scalars: an enum at C<0> is omitted unless the field is
C<optional> or a oneof member.

=item *

B<Oneof fields.> A oneof member is serialized with B<explicit presence>: when
the value hashref sets it, it is always emitted, even at the type default. A
well-formed value sets at most one member of a given oneof, and only that
member appears on the wire.

=back

=head1 DECODING BEHAVIOR

=over 4

=item *

B<Unknown fields.> A tag whose field number is not declared by the message is
skipped according to its wire type (varint drained, length-delimited skips its
byte count, I32/I64 skip their fixed width). By default it is B<absent> from the
returned hashref; with C<preserve_unknown_fields> its raw bytes are retained (see
L</UNKNOWN-FIELD PRESERVATION>).

=item *

B<Duplicate singular fields.> When a singular scalar field appears more than
once, the last value on the wire wins.

=item *

B<Repeated fields (lenient).> A repeated field decodes to an arrayref, with each
occurrence appended in wire order. Decoding a packable scalar repeated field
accepts B<both> forms regardless of how the field was declared: a packed
length-delimited block (its elements expanded in order) and the unpacked form
(one tag-prefixed element at a time). Packed and unpacked occurrences of the same
field concatenate in the order they appear. A declared repeated field that never
appears decodes to the empty list.

=item *

B<Map fields (last-wins).> A map field decodes to a hashref. Each occurrence is
one embedded MapEntry message; its C<key>/C<value> collapse into the hashref. A
repeated key keeps the B<last> value seen (proto3 map last-wins). A
message-typed value omitted on the wire decodes to an empty message hashref. A
declared map that never appears decodes to an empty hashref.

=item *

B<Singular message fields.> An embedded message decodes recursively into a
nested hashref keyed by the inner message's field names. A message field that
never appears on the wire stays B<absent> from the result (messages have no
default value). Last occurrence wins for a repeated tag.

=item *

B<Enum fields.> An enum decodes to its integer value. An B<unknown> enumerator
number (one not defined by the enum) is B<preserved> as that integer rather
than rejected.

=item *

B<Oneof fields (last-wins).> When several members of the same oneof appear on
the wire, only the B<last-seen> member is kept; decoding it clears any
earlier-set sibling from the result. A oneof member that never appears stays
absent (it is not filled with a default).

=item *

B<Defaults for omitted fields.> A declared implicit-presence singular scalar
field that never appears on the wire is set to its proto3 default (C<0> for
numerics and bool, C<""> for string/bytes). An C<optional> (explicit-presence)
field that never appears stays absent.

=item *

B<Wire errors propagate.> A deprecated group wire type (3/4) raises
L<Proto3::Exception::Wire::DeprecatedGroup>, and truncated input raises
L<Proto3::Exception::Wire::Truncated>, both surfaced unchanged from the wire
layer.

=back

=head1 UNKNOWN-FIELD PRESERVATION

By default an unknown field (a tag whose number the message does not declare) is
dropped on decode and never reappears on encode. Constructing the codec with
C<< preserve_unknown_fields => 1 >> changes that:

=over 4

=item *

B<On decode>, the raw bytes of every unknown record (tag plus payload) are
concatenated in wire order and stored under the result hashref's
C<__unknown_fields__> key. A message with no unknown fields leaves that key
B<absent> (there is no empty marker).

=item *

B<On encode>, if the value hashref carries a C<__unknown_fields__> string, those
bytes are appended B<verbatim, after> all known fields. A decode immediately
followed by an encode therefore reproduces an unknown-field-bearing message
B<byte-for-byte> after its known fields (spec §4.5, §5.3).

=back

With the flag off, C<__unknown_fields__> is never produced on decode and is
ignored on encode (it is not a declared field), so it cannot resurrect dropped
bytes.

=head1 SIGNED INTEGER ENCODING

The C<int32> and C<int64> types use proto3 signed-varint semantics: a
non-negative value is a plain varint, while a B<negative> value is encoded as
its full 64-bit two's complement (C<2**64 + value>), which always occupies ten
bytes — matching C<protoc>. Decoding reverses this: an unsigned varint with the
high (63rd) bit set is reinterpreted as the corresponding negative integer. Use
C<sint32>/C<sint64> (zigzag) when small-magnitude negatives should stay compact.

=head1 FAILURE MODES

=over 4

=item *

An unknown message type name raises L<Proto3::Exception::Codec::UnknownType>.

=item *

A value whose type clashes with the field (e.g. a non-numeric string for an
C<int32>) raises L<Proto3::Exception::Codec::TypeMismatch>, naming the field and
its expected type.

=item *

A schema containing a map field with a disallowed key type raises
L<Proto3::Exception::Schema> at codec construction (see L</new>).

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
