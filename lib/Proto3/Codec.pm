# ABOUTME: Proto3::Codec — high-level encode/decode over a resolved Schema; §4.5.
# This step: encode + decode singular scalar fields with unknown-field skipping.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Scalar::Util ();
use Proto3::Exception;
use Proto3::Wire ();
use Proto3::Wire::Tag ();

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
    my $d_varint   = sub ($b) { Proto3::Wire::decode_varint($b) };
    my $d_zigzag32 = sub ($b) { Proto3::Wire::decode_zigzag32($b) };
    my $d_zigzag64 = sub ($b) { Proto3::Wire::decode_zigzag64($b) };
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
        int32    => { wire => $W_VARINT, encode => $varint,   decode => $d_varint,   is_num => 1, default => 0 },
        int64    => { wire => $W_VARINT, encode => $varint,   decode => $d_varint,   is_num => 1, default => 0 },
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

class Proto3::Codec {
    field $schema :param;

    method schema { $schema }

    # encode($full_name, $hashref) -> wire bytes.
    #
    # Looks up the message by fully-qualified name (UnknownType if absent),
    # then walks its fields in field-number order, emitting each singular scalar
    # whose value is present and not the proto3 default. Fields declared
    # `optional` use explicit-presence semantics: a set value is always emitted,
    # even at the type default. Repeated/map/message fields are handled by later
    # steps and are skipped here.
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
        return $out;
    }

    # Encode one field given the message value hashref. Returns the field's
    # tag-prefixed bytes, or '' when the field is absent or default-omitted.
    method _encode_field ($field, $values) {
        my $name = $field->name;
        return '' unless exists $values->{$name};

        my $value = $values->{$name};
        return '' unless defined $value;

        # Only singular scalars are in scope this step.
        return '' if $field->is_repeated || $field->is_message;

        my $type = $field->type;
        my $spec = $SCALAR_TYPE{$type};
        return '' unless $spec;    # message/group handled elsewhere

        # Validate the value's type first: a non-numeric value for a numeric
        # field must raise TypeMismatch, not be silently coerced to 0 and then
        # dropped by the default-omit check below.
        $self->_assert_value_type( $field, $spec, $value );

        my $is_optional = $field->label eq 'optional';

        # proto3 implicit-presence default-omit: singular (non-optional) scalar
        # at its default is not written. Optional fields are explicit-presence
        # and are always written when set.
        if ( !$is_optional && $self->_is_default_value( $spec, $value ) ) {
            return '';
        }

        my $tag = Proto3::Wire::Tag::encode_tag( $field->number, $spec->{wire} );
        return $tag . $spec->{encode}->($value);
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

        my %result;
        my $rest = $bytes;
        while ( length $rest ) {
            ( my $field_number, my $wire_type, $rest ) =
                Proto3::Wire::Tag::decode_tag($rest);

            my $field = $field_by_number{$field_number};
            my $spec  = $field ? $SCALAR_TYPE{ $field->type } : undef;

            # Unknown field number, or a known field this step does not yet
            # handle (message/repeated): drain it by wire type and drop it.
            if ( !$spec || $field->is_repeated || $field->is_message ) {
                $rest = Proto3::Wire::skip_field( $wire_type, $rest );
                next;
            }

            ( my $value, $rest ) = $spec->{decode}->($rest);
            $result{ $field->name } = $value;    # last value wins
        }

        $self->_apply_defaults( $message, \%result );
        return \%result;
    }

    # Fill in proto3 implicit-presence defaults for singular scalar fields that
    # did not appear on the wire. Explicit-presence (`optional`) fields are left
    # absent; repeated/message fields are out of scope this step.
    method _apply_defaults ($message, $result) {
        for my $field ( @{ $message->fields } ) {
            next if exists $result->{ $field->name };
            next if $field->label eq 'optional';
            next if $field->is_repeated || $field->is_message;

            my $spec = $SCALAR_TYPE{ $field->type };
            next unless $spec;

            $result->{ $field->name } = $spec->{default};
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

This step implements C<encode> and C<decode> for B<singular scalar> fields.
Repeated, map, and embedded-message fields are added by subsequent steps.

=head1 METHODS

=head2 new

    my $codec = Proto3::Codec->new( schema => $schema );

Construct a codec bound to a L<Proto3::Schema>. The schema should already be
resolved (see L<Proto3::Schema/resolve>) for message-typed fields, though that
matters only once those are encoded.

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

=back

=head1 DECODING BEHAVIOR

=over 4

=item *

B<Unknown fields.> A tag whose field number is not declared by the message (or
whose field is not yet handled this step) is skipped according to its wire type
(varint drained, length-delimited skips its byte count, I32/I64 skip their fixed
width) and is B<absent> from the returned hashref.

=item *

B<Duplicate singular fields.> When a singular scalar field appears more than
once, the last value on the wire wins.

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

=head1 FAILURE MODES

=over 4

=item *

An unknown message type name raises L<Proto3::Exception::Codec::UnknownType>.

=item *

A value whose type clashes with the field (e.g. a non-numeric string for an
C<int32>) raises L<Proto3::Exception::Codec::TypeMismatch>, naming the field and
its expected type.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
