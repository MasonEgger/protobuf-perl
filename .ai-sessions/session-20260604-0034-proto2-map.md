# Session — V34: proto2 map-entry defaults (all REQUIRED cases pass)

- **Branch**: v1 — V34-PLAN.md.

## Done
- Codec _decode_map default-fills a MapEntry's key+value (a map entry always has
  both; they default to type-zero when omitted on the wire). Fixes the
  ValidDataMap.*.MissingDefault family + the HASH(0x..) value leak.
- JSON _has_explicit_presence delegates to $field->has_presence so a proto2
  explicit field set to zero round-trips through JSON (deleted: optional_* fix).
- t/codec/proto2_map.t, t/json/proto2_presence.t.

## MILESTONE: ALL REQUIRED v34 cases pass
Binary/JSON suite: 2741 successes, 0 unexpected REQUIRED failures.
With --enforce_recommended: 65 RECOMMENDED failures remain (40 proto2, 25 proto3):
FieldMask round-trip/validation, base64url bytes, duplicate JSON keys,
ignore-unknown-enum-string, NullValue-in-oneof, reject-invalid-utf8, Value
reject NaN/Inf. Suite green: 1312 tests.

## Next
Drain the 65 recommended cases to reach a flawless --enforce_recommended pass.
