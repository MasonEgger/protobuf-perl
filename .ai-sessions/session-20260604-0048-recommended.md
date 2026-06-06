# Session — V34: explicit packed + proto3 recommended JSON/WKT (1 failure left)

- **Branch**: v1 — V34-PLAN.md Phase 3 convergence.

## Done (two parallel streams, orchestrator-verified)
### Explicit [packed] override
- DescriptorSet translates FieldOptions.packed -> per-field repeated_field_encoding
  override so the feature pass applies it over the edition default. proto2
  [packed=true] -> packed; proto3/edition stay correct. Cleared 28 recommended proto2.
### proto3 recommended JSON/WKT (25 -> 0, +28 proto2 bonus)
- Invalid-UTF-8 string rejection on binary parse (feature-aware: VERIFY rejects,
  proto2 NONE lenient). Codec.
- Ignore-unknown-enum-string in JSON (category-gated). JSON.
- FieldMask round-trip/char validation. WKT/FieldMask.
- Duplicate JSON field-name rejection. JSON.
- NullValue-in-message/oneof + repeated-null-element. JSON.
- Value rejects NaN/Inf. WKT/Struct.
- base64url bytes input. JSON.
- Tests: string_utf8_reject, conformance_recommended, fieldmask_value_reject.

## Conformance progress (live v34, --enforce_recommended)
2805 successes, 1 failure (was 386). REQUIRED: 0. Recommended: 1.
The last one: Recommended.Proto2.JsonInput.FieldNameExtension (proto2 extension
JSON key form [fq.ext_name]). Suite green: 1351 tests.

## Next: the final case, then flawless.
