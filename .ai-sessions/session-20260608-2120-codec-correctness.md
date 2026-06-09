# Session — Codec correctness (range, wire-type, fuzz)

- **Branch**: fix/audit-remediation. Covers B-007, B-008, S-004.
- **Model**: claude-opus-4-8.

## Changes
- New lib/Protobuf/IntRange.pm: the shared inclusive [min,max] table for integer proto3
  types. JSON.pm now sources its %INT_RANGE from it (single source of truth).
- B-007: Codec _assert_value_type now range-checks integer fields and raises
  Protobuf::Exception::Codec::OutOfRange instead of silently truncating to the low bits on
  the wire. Covers singular, repeated (packed+expanded), and map scalars (all route through
  _assert_value_type).
- B-008: Codec decode validates the tag's wire type against the field's declared scalar type
  and raises Protobuf::Exception::Codec::WireTypeMismatch on mismatch, instead of
  mis-segmenting the stream and surfacing a misleading error later.
- New exception subclasses Codec::OutOfRange and Codec::WireTypeMismatch.
- S-004: t/codec/fuzz.t — 5000 random byte strings through Codec::decode of a fixed schema;
  each must decode or raise a typed Protobuf::Exception.

## Test corrections (caused by fixing B-008)
- t/conformance/testee.t: the stdio round-trip decoded the ConformanceResponse AS the test
  message (a type-confused loose decode that only "worked" via the mis-segmentation B-008
  fixes); now decodes ConformanceResponse and its protobuf_payload properly.
- t/codec/decode_scalar.t 11.6: pointed the unterminated-group case at an UNKNOWN field
  number (its documented intent); a known field with group wire type is now a WireTypeMismatch.
- The conformance testee maps decode exceptions to parse_error (Conformance.pm:146), matching
  protoc's rejection of wrong wire types, so external conformance stays aligned.

## Verification
- Full suite 1496 green; perlcritic --gentle clean; podchecker clean.
