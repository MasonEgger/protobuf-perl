# ABOUTME: Unit tests for Proto3::Wire::Tag — field+wire-type tag pack/unpack.
# Covers encode_tag spec vectors, the decode_tag (field, wire, rest) contract
# with max-field round-trip, deprecated group wire types 3/4, and field 0.

use strict;
use warnings;
use Test::More;

use Proto3::Wire::Tag qw(
    encode_tag decode_tag
    WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32
);

# ---------------------------------------------------------------------------
# Wire-type constants carry the canonical proto3 numbering.
# ---------------------------------------------------------------------------
{
    is( WIRE_VARINT, 0, 'WIRE_VARINT == 0' );
    is( WIRE_I64,    1, 'WIRE_I64 == 1' );
    is( WIRE_LEN,    2, 'WIRE_LEN == 2' );
    is( WIRE_I32,    5, 'WIRE_I32 == 5' );
}

# ---------------------------------------------------------------------------
# T-wire-3: encode_tag(field, wire) == varint((field << 3) | wire). The two
# canonical vectors: field 1 varint -> 0x08, field 2 length-delimited -> 0x12.
# ---------------------------------------------------------------------------
{
    is( encode_tag( 1, WIRE_VARINT ), "\x08",
        'encode_tag(1, WIRE_VARINT) == "\x08"' );
    is( encode_tag( 2, WIRE_LEN ), "\x12",
        'encode_tag(2, WIRE_LEN) == "\x12"' );
}

# ---------------------------------------------------------------------------
# decode_tag returns (field_number, wire_type, rest) and consumes only the
# leading tag varint, leaving trailing payload bytes intact.
# ---------------------------------------------------------------------------
{
    my ( $field, $wire, $rest ) = decode_tag( "\x08\x2a" );
    is( $field, 1,           'decode_tag reads the field number' );
    is( $wire,  WIRE_VARINT, 'decode_tag reads the wire type' );
    is( $rest,  "\x2a",      'decode_tag returns the untouched payload bytes' );
}

# ---------------------------------------------------------------------------
# encode_tag / decode_tag round-trip across every wire type and field numbers
# up to the proto3 maximum (2**29 - 1 == 536870911).
# ---------------------------------------------------------------------------
{
    my @wires  = ( WIRE_VARINT, WIRE_I64, WIRE_LEN, WIRE_I32 );
    my @fields = ( 1, 2, 15, 16, 2047, 2048, 536870911 );
    for my $f (@fields) {
        for my $w (@wires) {
            my ( $field, $wire, $rest ) = decode_tag( encode_tag( $f, $w ) );
            is( $field, $f,  "tag round-trip field $f / wire $w (field)" );
            is( $wire,  $w,  "tag round-trip field $f / wire $w (wire)" );
            is( $rest,  '',  "tag round-trip field $f / wire $w (no trailing)" );
        }
    }
}

# ---------------------------------------------------------------------------
# Group wire types 3 (SGROUP) and 4 (EGROUP) are first-class: decode_tag returns
# them rather than raising, so the codec can handle proto2 groups and editions
# DELIMITED message encoding. (proto3-only enforcement now lives at the codec/
# schema layer, not the raw tag layer.)
# ---------------------------------------------------------------------------
{
    for my $wire ( 3, 4 ) {
        my $tag = encode_tag( 7, $wire );
        my ( $field, $wt, $rest ) = decode_tag($tag);
        is( $field, 7,     "decode_tag returns field for group wire $wire" );
        is( $wt,    $wire, "decode_tag returns wire type $wire (no raise)" );
        is( $rest,  '',    "decode_tag consumes the whole group tag (wire $wire)" );
    }
}

# ---------------------------------------------------------------------------
# Field number 0 is not a legal proto3 field number; encode_tag rejects it with
# Proto3::Exception::Argument.
# ---------------------------------------------------------------------------
{
    eval { encode_tag( 0, WIRE_VARINT ) };
    isa_ok( $@, 'Proto3::Exception::Argument',
        'encode_tag field number 0 raises Argument' );
}

done_testing;
