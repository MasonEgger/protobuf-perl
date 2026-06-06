# ABOUTME: Base-128 varint + zigzag encode/decode — the numeric core of the wire format.
# Pure Perl with a Math::BigInt fallback so 32-bit Perls handle full 64-bit values.
use v5.38;
use warnings;

package Protobuf::Wire::Varint;

use Exporter 'import';
use Config;
use Math::BigInt;

use Protobuf::Exception;

our @EXPORT_OK = qw(
    encode_varint decode_varint
    encode_zigzag32 decode_zigzag32
    encode_zigzag64 decode_zigzag64
);

# Maximum bytes a 64-bit varint can occupy: ceil(64 / 7) == 10.
use constant MAX_VARINT_BYTES => 10;

# True when this Perl's native integers are wide enough for unsigned 64-bit
# math. When false (a 32-bit build) every operation routes through Math::BigInt.
use constant NATIVE_64BIT => ( $Config{ivsize} >= 8 );

# ---------------------------------------------------------------------------
# Internal helpers — the Math::BigInt fallback path. On a 32-bit Perl these run
# for every value; on a 64-bit Perl they run only for magnitudes that would
# overflow native arithmetic, and are exercised directly by the T-wire-7 tests.
# ---------------------------------------------------------------------------

# Coerce a value to a non-negative Math::BigInt, raising Argument on a negative.
sub _to_unsigned_bigint ($value) {
    my $big = ( ref $value && $value->isa('Math::BigInt') )
        ? $value->copy
        : Math::BigInt->new("$value");
    if ( $big->is_neg ) {
        Protobuf::Exception::Argument->throw( message =>
                "varint encode requires a non-negative value, got $value" );
    }
    return $big;
}

# Emit the LSB-first 7-bit groups of an unsigned value as varint bytes, via
# Math::BigInt so the arithmetic is exact regardless of native integer width.
sub _encode_varint_bigint ($value) {
    my $big = _to_unsigned_bigint($value);
    my $out = '';
    while (1) {
        my $byte = $big->copy->bmod(128)->numify;
        $big->brsft(7);
        if ( $big->is_zero ) {
            $out .= chr($byte);
            last;
        }
        $out .= chr( $byte | 0x80 );
    }
    return $out;
}

# Decode a varint into a Math::BigInt value; returns (value, remaining-bytes).
sub _decode_varint_bigint ($bytes) {
    my $value = Math::BigInt->bzero;
    my $shift = 0;
    my $len   = length $bytes;
    my $i     = 0;
    while (1) {
        if ( $i >= $len ) {
            Protobuf::Exception::Wire::Truncated->throw(
                message => 'buffer ended mid-varint' );
        }
        if ( $i >= MAX_VARINT_BYTES ) {
            Protobuf::Exception::Wire::VarintTooLong->throw(
                message => 'varint exceeds 10 bytes with no terminator' );
        }
        my $byte = ord substr( $bytes, $i, 1 );
        $i++;
        $value->badd( Math::BigInt->new( $byte & 0x7f )->blsft($shift) );
        last unless $byte & 0x80;
        $shift += 7;
    }
    return ( $value, substr( $bytes, $i ) );
}

# ---------------------------------------------------------------------------
# Public varint API
# ---------------------------------------------------------------------------

# encode_varint($n) -> bytes. $n is an unsigned integer (native or Math::BigInt).
# LSB-first 7-bit groups, each non-final byte carrying the 0x80 continuation bit.
sub encode_varint ($value) {
    if ( ( ref $value && $value->isa('Math::BigInt') ) || !NATIVE_64BIT ) {
        return _encode_varint_bigint($value);
    }
    if ( $value < 0 ) {
        Protobuf::Exception::Argument->throw( message =>
                "varint encode requires a non-negative value, got $value" );
    }
    my $n   = $value;
    my $out = '';
    while (1) {
        my $byte = $n % 128;
        $n = int( $n / 128 );
        if ( $n == 0 ) {
            $out .= chr($byte);
            last;
        }
        $out .= chr( $byte | 0x80 );
    }
    return $out;
}

# decode_varint($bytes) -> (value, remaining-bytes). Consumes only the leading
# varint. Raises Wire::Truncated on a short buffer and Wire::VarintTooLong past
# 10 bytes without a terminator.
sub decode_varint ($bytes) {
    return _decode_varint_bigint($bytes) unless NATIVE_64BIT;

    my $len   = length $bytes;
    my $n     = 0;
    my $shift = 0;
    my $i     = 0;
    while (1) {
        if ( $i >= $len ) {
            Protobuf::Exception::Wire::Truncated->throw(
                message => 'buffer ended mid-varint' );
        }
        if ( $i >= MAX_VARINT_BYTES ) {
            Protobuf::Exception::Wire::VarintTooLong->throw(
                message => 'varint exceeds 10 bytes with no terminator' );
        }
        my $byte = ord substr( $bytes, $i, 1 );
        $i++;
        # Past 56 bits of shift the next group spills into the top byte of a
        # 64-bit value; native shifting would lose precision, so hand the whole
        # buffer to the Math::BigInt decoder.
        if ( $shift >= 56 ) {
            return _decode_varint_bigint($bytes);
        }
        $n |= ( $byte & 0x7f ) << $shift;
        last unless $byte & 0x80;
        $shift += 7;
    }
    return ( $n, substr( $bytes, $i ) );
}

# ---------------------------------------------------------------------------
# Zigzag: map signed integers to unsigned so small-magnitude negatives stay
# small. encode: (n << 1) XOR (n >> bits-1). decode: (n >> 1) XOR -(n & 1).
# All arithmetic goes through Math::BigInt so it is correct on any Perl.
# ---------------------------------------------------------------------------

# Encode a signed value via zigzag over $bits, then varint.
sub _encode_zigzag ( $value, $bits ) {
    my $n = ( ref $value && $value->isa('Math::BigInt') )
        ? $value->copy
        : Math::BigInt->new("$value");
    my $zig = $n->copy->blsft(1)->bxor( $n->copy->brsft( $bits - 1 ) );
    # Constrain to the unsigned $bits-wide range before varint encoding.
    $zig->bmod( Math::BigInt->new(2)->bpow($bits) );
    return encode_varint($zig);
}

# Decode a varint then reverse the zigzag mapping over $bits.
sub _decode_zigzag ( $bytes, $bits ) {
    my ($u) = _decode_varint_bigint($bytes);
    my $low  = $u->copy->bmod(2);     # n & 1
    my $half = $u->copy->brsft(1);    # n >> 1
    my $sign = $low->is_zero ? Math::BigInt->bzero : Math::BigInt->bone->bneg;
    my $val  = $half->bxor($sign);
    return _normalize_signed($val);
}

# Reduce a Math::BigInt to a native integer when it fits the native signed
# range, so callers compare cleanly against plain Perl numbers; otherwise keep
# the Math::BigInt.
sub _normalize_signed ($big) {
    return 0 if $big->is_zero;
    if (NATIVE_64BIT) {
        my $limit = Math::BigInt->new(2)->bpow(63);
        return $big->numify if $big->copy->babs->blt($limit);
    }
    return $big;
}

sub encode_zigzag32 ($value) { _encode_zigzag( $value, 32 ) }
sub decode_zigzag32 ($bytes) { _decode_zigzag( $bytes, 32 ) }
sub encode_zigzag64 ($value) { _encode_zigzag( $value, 64 ) }
sub decode_zigzag64 ($bytes) { _decode_zigzag( $bytes, 64 ) }

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Wire::Varint - base-128 varint and zigzag encoding for the proto3 wire format

=head1 SYNOPSIS

    use Protobuf::Wire::Varint qw(
        encode_varint decode_varint
        encode_zigzag32 decode_zigzag32
        encode_zigzag64 decode_zigzag64
    );

    my $bytes = encode_varint(300);          # "\xac\x02"
    my ( $value, $rest ) = decode_varint($bytes);

    my $z = encode_zigzag32(-1);             # varint(1)
    my $n = decode_zigzag32($z);             # -1

=head1 DESCRIPTION

This module implements the numeric core of the protobuf binary wire format:
unsigned base-128 varints and the zigzag transform used by the C<sint32> and
C<sint64> scalar types. It is pure Perl. On a 64-bit Perl the common varint path
uses native integer arithmetic; large 64-bit magnitudes and 32-bit Perls fall
back to L<Math::BigInt> so the full unsigned 64-bit range is always
representable. Zigzag always uses L<Math::BigInt> for exact results.

=head1 FUNCTIONS

All functions are exported on request (none by default).

=head2 encode_varint

    my $bytes = encode_varint($n);

Encode a non-negative integer C<$n> (a native integer or a L<Math::BigInt>) as a
little-endian base-128 varint: successive 7-bit groups, least-significant first,
with the high bit (C<0x80>) of every non-final byte set as a continuation flag.
A 64-bit value occupies at most 10 bytes. A negative C<$n> raises
L<Protobuf::Exception::Argument>.

=head2 decode_varint

    my ( $value, $rest ) = decode_varint($bytes);

Decode the varint at the start of C<$bytes>. Returns the decoded value and the
remaining bytes after the varint (only the leading varint is consumed). Raises
L<Protobuf::Exception::Wire::Truncated> if the buffer ends with the continuation
bit still set, and L<Protobuf::Exception::Wire::VarintTooLong> if no terminator
appears within 10 bytes.

=head2 encode_zigzag32 / encode_zigzag64

    my $bytes = encode_zigzag32($signed);
    my $bytes = encode_zigzag64($signed);

Apply the zigzag transform C<< (n << 1) XOR (n >> bits-1) >> over 32 or 64 bits
respectively, then varint-encode the result. Zigzag maps small-magnitude signed
values (including negatives) to small unsigned values.

=head2 decode_zigzag32 / decode_zigzag64

    my $signed = decode_zigzag32($bytes);
    my $signed = decode_zigzag64($bytes);

Decode a varint, then reverse the zigzag transform C<< (n >> 1) XOR -(n & 1) >>.
The result is returned as a native integer when it fits the native signed range,
otherwise as a L<Math::BigInt>.

=head1 LIMITS

Varints encode unsigned values up to C<2**64 - 1> (10 bytes). Zigzag covers the
signed ranges C<-2**31 .. 2**31-1> (32-bit) and C<-2**63 .. 2**63-1> (64-bit).

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
