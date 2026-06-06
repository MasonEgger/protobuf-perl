# ABOUTME: Public proto3 wire-format facade — fixed32/64, float/double, skip.
# Re-exports the full Varint + Tag API so callers have a single import surface.
package Protobuf::Wire;

use v5.38;
use warnings;
use experimental 'signatures';

use Exporter 'import';
use Config;
use Math::BigInt;
use Protobuf::Wire::Varint qw(
    encode_varint decode_varint
    encode_zigzag32 decode_zigzag32
    encode_zigzag64 decode_zigzag64
);
use Protobuf::Wire::Tag qw(
    encode_tag decode_tag
    WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32
    WIRE_GROUP_START WIRE_GROUP_END
);
use Protobuf::Exception;

our @EXPORT_OK = qw(
    encode_varint decode_varint
    encode_zigzag32 decode_zigzag32
    encode_zigzag64 decode_zigzag64
    encode_tag decode_tag
    encode_fixed32 decode_fixed32
    encode_fixed64 decode_fixed64
    encode_float decode_float
    encode_double decode_double
    WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32
    WIRE_GROUP_START WIRE_GROUP_END
    skip_field skip_group
);

# True when running on a Perl whose IVs are only 32 bits wide; on such builds
# pack('Q<') is unavailable, so fixed64 falls back to two 32-bit halves.
my $IS_32BIT = $Config{ivsize} < 8;

# 2**32, used for the 32-bit fixed64 split/combine fallback.
my $TWO32 = Math::BigInt->new('4294967296');

# --- helpers -------------------------------------------------------------

# Take exactly $n bytes from the front of $bytes, returning (chunk, rest).
# Raises Wire::Truncated if fewer than $n bytes are available.
sub _take ($bytes, $n) {
    if ( length $bytes < $n ) {
        Protobuf::Exception::Wire::Truncated->throw(
            message => "expected $n bytes, got " . length($bytes),
        );
    }
    return ( substr( $bytes, 0, $n ), substr( $bytes, $n ) );
}

# --- fixed32 -------------------------------------------------------------

# Encode an unsigned 32-bit integer as 4 little-endian bytes.
sub encode_fixed32 ($value) {
    return pack 'V', $value;
}

# Decode 4 little-endian bytes into an unsigned 32-bit integer.
# Returns (value, rest).
sub decode_fixed32 ($bytes) {
    my ( $chunk, $rest ) = _take( $bytes, 4 );
    return ( unpack( 'V', $chunk ), $rest );
}

# --- fixed64 -------------------------------------------------------------

# Encode an unsigned 64-bit integer as 8 little-endian bytes.
# Uses native Q< where available, with a Math::BigInt two-halves fallback on
# 32-bit Perls.
sub encode_fixed64 ($value) {
    return pack 'Q<', $value unless $IS_32BIT;

    my $big  = ref $value ? $value->copy : Math::BigInt->new("$value");
    my $lo   = $big->copy->bmod($TWO32)->numify;
    my $hi   = $big->copy->bdiv($TWO32)->bmod($TWO32)->numify;
    return pack( 'V', $lo ) . pack( 'V', $hi );
}

# Decode 8 little-endian bytes into an unsigned 64-bit integer.
# Returns (value, rest); the value is a Math::BigInt on 32-bit Perls.
sub decode_fixed64 ($bytes) {
    my ( $chunk, $rest ) = _take( $bytes, 8 );
    return ( unpack( 'Q<', $chunk ), $rest ) unless $IS_32BIT;

    my $lo = unpack 'V', substr( $chunk, 0, 4 );
    my $hi = unpack 'V', substr( $chunk, 4, 4 );
    my $value = Math::BigInt->new($hi)->bmul($TWO32)->badd($lo);
    return ( $value, $rest );
}

# --- float / double ------------------------------------------------------

# Encode a number as a 4-byte little-endian IEEE-754 single.
sub encode_float ($value) {
    return pack 'f<', $value;
}

# Decode a 4-byte little-endian IEEE-754 single. Returns (value, rest).
sub decode_float ($bytes) {
    my ( $chunk, $rest ) = _take( $bytes, 4 );
    return ( unpack( 'f<', $chunk ), $rest );
}

# Encode a number as an 8-byte little-endian IEEE-754 double.
sub encode_double ($value) {
    return pack 'd<', $value;
}

# Decode an 8-byte little-endian IEEE-754 double. Returns (value, rest).
sub decode_double ($bytes) {
    my ( $chunk, $rest ) = _take( $bytes, 8 );
    return ( unpack( 'd<', $chunk ), $rest );
}

# --- skip ----------------------------------------------------------------

# Skip one field's payload given its wire type. The tag must already have been
# consumed; $bytes begins at the payload. Returns the remaining bytes.
# Raises Wire::InvalidWireType for unknown wire types (3/4 are rejected at the
# tag layer, so any value reaching here other than 0/1/2/5 is invalid) and
# Wire::Truncated when the payload is short.
sub skip_field ($wire_type, $bytes) {
    if ( $wire_type == WIRE_VARINT ) {
        my ( undef, $rest ) = decode_varint($bytes);
        return $rest;
    }
    if ( $wire_type == WIRE_I64 ) {
        my ( undef, $rest ) = _take( $bytes, 8 );
        return $rest;
    }
    if ( $wire_type == WIRE_I32 ) {
        my ( undef, $rest ) = _take( $bytes, 4 );
        return $rest;
    }
    if ( $wire_type == WIRE_LEN ) {
        my ( $len, $rest ) = decode_varint($bytes);
        $len = $len->numify if ref $len;
        ( undef, my $tail ) = _take( $rest, $len );
        return $tail;
    }
    # An SGROUP opens a group whose body runs until the matching EGROUP. Read the
    # next tag to learn the group's field number, then skip its whole body. (The
    # group's own field number is on the SGROUP tag the caller already consumed;
    # when skip_field is reached via an unknown-field skip the body's records
    # carry their own tags, and skip_group tracks depth by field number.)
    if ( $wire_type == WIRE_GROUP_START ) {
        # The caller consumed the SGROUP tag but not its field number, so we
        # cannot know which EGROUP closes us from $wire_type alone. Group skips
        # therefore go through skip_group($bytes, $field_number); reaching here
        # means an SGROUP turned up without a field number, which is a malformed
        # standalone skip. Surface it as an invalid wire use.
        Protobuf::Exception::Wire::InvalidWireType->throw(
            message => 'skip_field cannot skip a group without its field number; '
                . 'use skip_group',
        );
    }
    Protobuf::Exception::Wire::InvalidWireType->throw(
        message => "unknown wire type $wire_type",
    );
}

# skip_group($bytes, $field_number) -> remaining bytes. The opening SGROUP tag
# for $field_number has already been consumed; $bytes begins at the group body.
# Consumes records until the EGROUP tag that matches $field_number, handling
# nested groups (of any field number) by depth, and returns whatever follows the
# closing EGROUP. Raises Wire::Truncated if the group is never closed.
sub skip_group ($bytes, $field_number) {
    while ( length $bytes ) {
        my ( $f, $wt, $rest ) = decode_tag($bytes);
        if ( $wt == WIRE_GROUP_END ) {
            # Matching close for our group.
            return $rest if $f == $field_number;
            # An EGROUP for a different field number is malformed nesting.
            Protobuf::Exception::Wire::Truncated->throw(
                message => "group field $field_number closed by EGROUP for $f",
            );
        }
        if ( $wt == WIRE_GROUP_START ) {
            $bytes = skip_group( $rest, $f );    # recurse into nested group
            next;
        }
        $bytes = skip_field( $wt, $rest );
    }
    Protobuf::Exception::Wire::Truncated->throw(
        message => "group field $field_number not closed by an EGROUP",
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Wire - proto3 wire-format primitives (public facade)

=head1 SYNOPSIS

    use Protobuf::Wire qw(
        encode_varint decode_varint
        encode_tag decode_tag
        encode_fixed32 decode_fixed32
        encode_fixed64 decode_fixed64
        encode_float decode_float
        encode_double decode_double
        skip_field
        WIRE_VARINT WIRE_FIXED64 WIRE_LEN WIRE_FIXED32
    );

=head1 DESCRIPTION

C<Protobuf::Wire> is the single import surface for proto3 wire-format
primitives. It re-exports the full L<Protobuf::Wire::Varint> and
L<Protobuf::Wire::Tag> public API and adds the fixed-width and floating-point
codecs plus a wire-type-aware field skipper.

All C<decode_*> functions return C<($value, $rest)>, where C<$rest> is the
unconsumed remainder of the input. All multi-byte numeric forms are
little-endian, per the proto3 wire format.

=head1 WIRE TYPES

=over 4

=item * C<WIRE_VARINT> (0) — int32/64, uint32/64, sint32/64, bool, enum

=item * C<WIRE_FIXED64> (1) — fixed64, sfixed64, double

=item * C<WIRE_LEN> (2) — string, bytes, embedded messages, packed repeated

=item * C<WIRE_FIXED32> (5) — fixed32, sfixed32, float

=back

Wire types 3 and 4 (start/end group) are deprecated and rejected at the tag
layer (L<Protobuf::Wire::Tag/decode_tag>).

=head1 FUNCTIONS

=head2 encode_fixed32 / decode_fixed32

4-byte little-endian unsigned 32-bit integer (C<pack 'V'>).

=head2 encode_fixed64 / decode_fixed64

8-byte little-endian unsigned 64-bit integer (packed little-endian via the
C<Q> template). On 32-bit Perls,
where C<Q> is unavailable, the value is split into two 32-bit halves and
C<decode_fixed64> returns a L<Math::BigInt>.

=head2 encode_float / decode_float

4-byte little-endian IEEE-754 single (C<pack 'f<'>).

=head2 encode_double / decode_double

8-byte little-endian IEEE-754 double (C<pack 'd<'>). C<NaN>, C<+Inf> and
C<-Inf> round-trip; compare them by their encoded bit pattern, not with C<==>.

=head2 skip_field

    my $rest = skip_field($wire_type, $payload_bytes);

Consume one field's payload (the tag must already be consumed) and return the
remaining bytes. Raises L<Protobuf::Exception::Wire::Truncated> on a short
payload and L<Protobuf::Exception::Wire::InvalidWireType> for unknown wire types.

=head1 SEE ALSO

L<Protobuf::Wire::Varint>, L<Protobuf::Wire::Tag>, L<Protobuf::Exception>

=cut
