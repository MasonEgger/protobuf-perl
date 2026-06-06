# ABOUTME: Unit tests for Protobuf::Wire::Varint — varint + zigzag encode/decode.
# Covers round-trips, known vectors, the (value, rest) decode contract, the
# Math::BigInt fallback path, and truncated / over-long / negative failure modes.

use strict;
use warnings;
use Test::More;

use Math::BigInt;

use Protobuf::Wire::Varint qw(
    encode_varint decode_varint
    encode_zigzag32 decode_zigzag32
    encode_zigzag64 decode_zigzag64
);

# Compare two integers that may be native or Math::BigInt by their canonical
# decimal string, so assertions stay stable across the bigint boundary.
sub num_is {
    my ( $got, $want, $name ) = @_;
    is( "$got", "$want", $name );
}

# ---------------------------------------------------------------------------
# T-wire-1: varint encode/decode round-trips for representative values.
# ---------------------------------------------------------------------------
{
    my @values = (
        0,
        1,
        127,
        128,
        16383,
        16384,
        2**32,
        Math::BigInt->new(2)->bpow(63),             # 2**63 (exact; 2**63 as a
                                                    # bare Perl literal is a
                                                    # lossy float)
        Math::BigInt->new(2)->bpow(64)->bsub(1),    # 2**64 - 1
    );

    for my $v (@values) {
        my $bytes = encode_varint($v);
        my ( $decoded, $rest ) = decode_varint($bytes);
        num_is( $decoded, $v, "varint round-trip for $v" );
        is( $rest, '', "varint round-trip for $v leaves no trailing bytes" );
    }
}

# ---------------------------------------------------------------------------
# Known vector: encode_varint(300) eq "\xac\x02".
# ---------------------------------------------------------------------------
{
    is( encode_varint(300), "\xac\x02",
        'encode_varint(300) matches the spec vector' );
}

# ---------------------------------------------------------------------------
# decode_varint returns (value, remaining-bytes) and consumes ONLY the varint,
# leaving trailing bytes intact.
# ---------------------------------------------------------------------------
{
    my $buf = encode_varint(300) . "\xff\xee";    # 300, then two trailing bytes
    my ( $value, $rest ) = decode_varint($buf);
    num_is( $value, 300, 'decode_varint reads the leading varint value' );
    is( $rest, "\xff\xee",
        'decode_varint returns the untouched trailing bytes' );
}

# ---------------------------------------------------------------------------
# T-wire-2: zigzag round-trips for representative signed values.
# ---------------------------------------------------------------------------
{
    my @v32 = ( -1, 0, 1, -2147483648, 2147483647 );
    for my $v (@v32) {
        num_is( decode_zigzag32( encode_zigzag32($v) ), $v,
            "zigzag32 round-trip for $v" );
    }

    my @v64 = (
        -1, 0, 1,
        Math::BigInt->new(2)->bpow(63)->bneg,       # -2**63
        Math::BigInt->new(2)->bpow(63)->bsub(1),    #  2**63 - 1
    );
    for my $v (@v64) {
        num_is( decode_zigzag64( encode_zigzag64($v) ), $v,
            "zigzag64 round-trip for $v" );
    }
}

# Known zigzag vectors (from the protobuf encoding spec).
{
    is( encode_zigzag32(-1), encode_varint(1),
        'zigzag32(-1) encodes as varint 1' );
    is( encode_zigzag32(1), encode_varint(2),
        'zigzag32(1) encodes as varint 2' );
    is( encode_zigzag32(-2), encode_varint(3),
        'zigzag32(-2) encodes as varint 3' );
    is( encode_zigzag32(2147483647), encode_varint(4294967294),
        'zigzag32(2147483647) encodes as varint 4294967294' );
}

# ---------------------------------------------------------------------------
# T-wire-7: the forced-Math::BigInt path produces byte-identical output to the
# native path for large 64-bit values. _encode_varint_bigint /
# _decode_varint_bigint are the internal helpers exposing the fallback that
# 32-bit Perls take automatically.
# ---------------------------------------------------------------------------
{
    my @big = (
        Math::BigInt->new(2)->bpow(63),             # 2**63 (exact)
        Math::BigInt->new(2)->bpow(64)->bsub(1),    # 2**64 - 1
        300, 0, 1,
    );
    for my $v (@big) {
        is(
            Protobuf::Wire::Varint::_encode_varint_bigint($v),
            encode_varint($v),
            "forced-bigint encode matches native for $v",
        );
        my ( $decoded, $rest ) =
            Protobuf::Wire::Varint::_decode_varint_bigint( encode_varint($v) );
        num_is( $decoded, $v, "forced-bigint decode matches native for $v" );
        is( $rest, '',
            "forced-bigint decode for $v leaves no trailing bytes" );
    }
}

# ---------------------------------------------------------------------------
# T-wire-4: a truncated varint (continuation bit set, then the buffer ends)
# raises Protobuf::Exception::Wire::Truncated.
# ---------------------------------------------------------------------------
{
    eval { decode_varint("\xac") };    # continuation bit set, no terminator
    my $err = $@;
    ok( ref $err, 'truncated varint dies with an object' );
    isa_ok( $err, 'Protobuf::Exception::Wire::Truncated',
        'truncated varint raises Wire::Truncated' );

    eval { decode_varint('') };
    isa_ok( $@, 'Protobuf::Exception::Wire::Truncated',
        'empty input raises Wire::Truncated' );
}

# ---------------------------------------------------------------------------
# T-wire-5: an 11-byte varint (no terminator within the 10-byte limit) raises
# Protobuf::Exception::Wire::VarintTooLong.
# ---------------------------------------------------------------------------
{
    my $overlong = "\xff" x 11;        # 11 continuation bytes, never terminates
    eval { decode_varint($overlong) };
    isa_ok( $@, 'Protobuf::Exception::Wire::VarintTooLong',
        'over-long varint raises Wire::VarintTooLong' );
}

# ---------------------------------------------------------------------------
# A negative value passed to encode_varint raises Protobuf::Exception::Argument.
# ---------------------------------------------------------------------------
{
    eval { encode_varint(-1) };
    isa_ok( $@, 'Protobuf::Exception::Argument',
        'negative value to encode_varint raises Argument' );
}

done_testing;
