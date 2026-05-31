# ABOUTME: Tests for Proto3::Wire facade — fixed32/64, float/double, re-exports.
# Covers little-endian vectors, round-trips, and NaN/+Inf/-Inf bit-pattern fidelity.
package main;

use v5.38;
use warnings;
use Test::More;
use Proto3::Wire qw(
    encode_varint decode_varint
    encode_zigzag32 decode_zigzag32
    encode_zigzag64 decode_zigzag64
    encode_tag decode_tag
    encode_fixed32 decode_fixed32
    encode_fixed64 decode_fixed64
    encode_float decode_float
    encode_double decode_double
    WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32
    skip_field
);
use Proto3::Exception;

# --- re-export smoke ----------------------------------------------------
# The facade re-exports the full Varint + Tag public API (single import
# surface per spec §4.1).
is encode_tag(1, WIRE_VARINT), "\x08", 're-exported encode_tag works';
{
    my ($f, $w, $rest) = decode_tag(encode_tag(2, WIRE_LEN));
    is $f, 2, 're-exported decode_tag field';
    is $w, WIRE_LEN, 're-exported decode_tag wire';
}
is encode_varint(300), "\xac\x02", 're-exported encode_varint vector';
{
    my ($v, $rest) = decode_varint("\xac\x02");
    is $v, 300, 're-exported decode_varint vector';
}
{
    my ($v, $rest) = decode_zigzag32(encode_zigzag32(-1));
    is $v, -1, 're-exported zigzag32 round-trip';
}
{
    my ($v, $rest) = decode_zigzag64(encode_zigzag64(-2));
    is $v, -2, 're-exported zigzag64 round-trip';
}

# --- fixed32 ------------------------------------------------------------
# fixed32 is 4 bytes little-endian.
is encode_fixed32(0),          "\x00\x00\x00\x00", 'encode_fixed32(0)';
is encode_fixed32(1),          "\x01\x00\x00\x00", 'encode_fixed32(1) little-endian';
is encode_fixed32(0x04030201), "\x01\x02\x03\x04", 'encode_fixed32 byte order';
is encode_fixed32(0xFFFFFFFF), "\xFF\xFF\xFF\xFF", 'encode_fixed32 max';

for my $v (0, 1, 42, 255, 256, 65535, 0x04030201, 0xFFFFFFFF) {
    my $enc = encode_fixed32($v);
    is length($enc), 4, "fixed32($v) is 4 bytes";
    my ($got, $rest) = decode_fixed32($enc . "TAIL");
    is $got, $v, "fixed32 round-trip $v";
    is $rest, "TAIL", "fixed32 leaves remainder for $v";
}

# Truncated fixed32 raises a typed Wire exception.
{
    my $err = eval { decode_fixed32("\x01\x02\x03"); 1 } ? undef : $@;
    ok $err, 'truncated fixed32 dies';
    isa_ok $err, 'Proto3::Exception::Wire::Truncated', 'truncated fixed32 type';
}

# --- fixed64 ------------------------------------------------------------
# fixed64 is 8 bytes little-endian.
is encode_fixed64(0), "\x00\x00\x00\x00\x00\x00\x00\x00", 'encode_fixed64(0)';
is encode_fixed64(1), "\x01\x00\x00\x00\x00\x00\x00\x00", 'encode_fixed64(1) little-endian';

for my $v (0, 1, 42, 255, 0xFFFFFFFF, 0x1_0000_0000) {
    my $enc = encode_fixed64($v);
    is length($enc), 8, "fixed64($v) is 8 bytes";
    my ($got, $rest) = decode_fixed64($enc . "TAIL");
    is $got, $v, "fixed64 round-trip $v";
    is $rest, "TAIL", "fixed64 leaves remainder for $v";
}

# Max 64-bit value round-trips (string comparison to dodge float coercion).
{
    my $max = 18446744073709551615;
    my $enc = encode_fixed64($max);
    is length($enc), 8, 'fixed64 max is 8 bytes';
    my ($got, $rest) = decode_fixed64($enc);
    is "$got", "$max", 'fixed64 max round-trip';
}

# Truncated fixed64 raises a typed Wire exception.
{
    my $err = eval { decode_fixed64("\x01\x02\x03\x04\x05\x06\x07"); 1 } ? undef : $@;
    ok $err, 'truncated fixed64 dies';
    isa_ok $err, 'Proto3::Exception::Wire::Truncated', 'truncated fixed64 type';
}

# --- float --------------------------------------------------------------
for my $v (0.0, 1.0, -1.0, 0.5, -0.5, 3.5, 1234.0) {
    my $enc = encode_float($v);
    is length($enc), 4, "float($v) is 4 bytes";
    my ($got, $rest) = decode_float($enc . "X");
    is $got, $v, "float round-trip $v";
    is $rest, "X", "float leaves remainder for $v";
}

# --- double -------------------------------------------------------------
for my $v (0.0, 1.0, -1.0, 0.1, -0.1, 3.141592653589793, 1e300, -1e-300) {
    my $enc = encode_double($v);
    is length($enc), 8, "double($v) is 8 bytes";
    my ($got, $rest) = decode_double($enc . "X");
    is $got, $v, "double round-trip $v";
    is $rest, "X", "double leaves remainder for $v";
}

# --- special floats (T-wire-8) ------------------------------------------
# NaN/Inf cannot be compared with ==; compare the encoded bit pattern of the
# round-tripped value against the original encoding.
my $inf  = 9**9**9;
my $ninf = -9**9**9;
my $nan  = $inf - $inf;

for my $spec (
    [ 'float +Inf', \&encode_float,  \&decode_float,  $inf  ],
    [ 'float -Inf', \&encode_float,  \&decode_float,  $ninf ],
    [ 'float NaN',  \&encode_float,  \&decode_float,  $nan  ],
    [ 'double +Inf', \&encode_double, \&decode_double, $inf  ],
    [ 'double -Inf', \&encode_double, \&decode_double, $ninf ],
    [ 'double NaN',  \&encode_double, \&decode_double, $nan  ],
) {
    my ($label, $enc_fn, $dec_fn, $val) = @$spec;
    my $bits = $enc_fn->($val);
    my ($got, $rest) = $dec_fn->($bits);
    my $rebits = $enc_fn->($got);
    is $rebits, $bits, "$label round-trips by bit pattern";
}

# --- skip_field ---------------------------------------------------------
# skip_field consumes one field's payload given its wire type and returns rest.
{
    # varint payload
    my $rest = skip_field(WIRE_VARINT, "\xac\x02TAIL");
    is $rest, "TAIL", 'skip_field varint';
}
{
    my $rest = skip_field(WIRE_I32, "\x01\x02\x03\x04TAIL");
    is $rest, "TAIL", 'skip_field fixed32';
}
{
    my $rest = skip_field(WIRE_I64, "\x01\x02\x03\x04\x05\x06\x07\x08TAIL");
    is $rest, "TAIL", 'skip_field fixed64';
}
{
    # length-delimited: length 3 then 3 bytes payload
    my $rest = skip_field(WIRE_LEN, "\x03abcTAIL");
    is $rest, "TAIL", 'skip_field len';
}

# Unknown wire type raises a typed Wire exception.
{
    my $err = eval { skip_field(6, "x"); 1 } ? undef : $@;
    ok $err, 'skip_field unknown wire type dies';
    isa_ok $err, 'Proto3::Exception::Wire', 'skip_field unknown wire type is Wire';
}

# Truncated length-delimited payload raises Truncated.
{
    my $err = eval { skip_field(WIRE_LEN, "\x05ab"); 1 } ? undef : $@;
    ok $err, 'skip_field truncated len dies';
    isa_ok $err, 'Proto3::Exception::Wire::Truncated', 'skip_field truncated len type';
}

done_testing;
