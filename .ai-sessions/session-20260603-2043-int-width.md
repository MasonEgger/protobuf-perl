# Session — proto3 conformance: 32-bit integer width + JSON bigint

- **Timestamp**: 2026-06-03 20:43
- **Branch**: v1

## Focus

Drive down proto3 conformance failures. This batch targets 32-bit integer
semantics and a JSON serialization crash.

## Fixed

- **32-bit integer width-masking on decode** (`lib/Proto3/Codec.pm`): proto3
  wraps int32/uint32/sint32 to 32 bits even when the wire varint is wider.
  Added `$wrap_i32`/`$wrap_u32` and width-aware decoders (`$d_i32var`,
  `$d_u32var`); int64/uint64 keep full width. For sint32, the raw varint is
  truncated to 32 bits BEFORE the zigzag transform (protoc order), fixing the
  over-width SINT32 case. New `t/codec/int_width.t`.
- **Math::BigInt reaching JSON::PP** (`lib/Proto3/JSON.pm`): a 32-bit number
  field carrying a BigInt serialized as a blessed object (JSON::PP threw
  "allow_blessed"). `_encode_scalar` now numifies a BigInt to a native scalar
  for JSON-number types.

## Conformance progress (live runner)

- proto3 Required failures: 126 -> 108 (int width + JSON bigint) -> 101 (sint32).
- Overall successes: 1307 -> 1353.
- Full suite green: 1004 tests.

## Remaining proto3 buckets (~101)

- 28 "Should have failed to parse, but didn't" — missing protobuf input
  validation (zero field number, overlong varints, etc.).
- 27 "JSON output unparseable" — remaining number/format edges.
- 24 "Failed to parse input or produce output".
- ~15 Any/Struct/Value JSON (nested WKTs deleted from output).
- 4 "Should have failed to serialize".
- double precision formatting (2.2250738585072e-308 should keep full digits).

## Next

Continue TDD per bucket against the live runner at
/tmp/protobuf-build/protobuf-3.21.12/cmake-build/conformance_test_runner via
/tmp/run-conf.sh.
