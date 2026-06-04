# Session — proto3 conformance: signed sfixed32/sfixed64

- **Timestamp**: 2026-06-03 21:10
- **Branch**: v1

## Fixed
- lib/Proto3/Codec.pm: sfixed32/sfixed64 are SIGNED fixed-width integers but were
  decoded/encoded as unsigned (sfixed64(-1) came back as 18446744073709551615).
  Added signed decoders (high bit -> negative two's complement) and encoders
  (negative -> two's complement before the unsigned fixed writer); fixed32/fixed64
  stay unsigned. t/codec/sfixed_signed.t.

## Conformance progress (live)
- proto3 Required failures: 35 -> 27. Successes: 1423 -> 1431. Suite green: 1078.
- Running total: 126 -> 27.

## Remaining ~27
ENUM (out-of-range storage ~6), Timestamp/Duration offset+range (~7),
message-merge for repeated/oneof submessages (~4), wrapper types JSON (~4),
IllegalZeroFieldNum + UnknownVarint protobuf input validation (~4), BoolMap (~1).
