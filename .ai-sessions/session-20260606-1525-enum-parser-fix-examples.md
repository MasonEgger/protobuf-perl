# Session — Fix native-parser enum codec bug + broken example scripts

- **Branch**: patch (off freshly-pulled main, squashed conformance commit).
- **Model**: claude-opus-4-8.
- Investigated two bugs flagged in a prior session; confirmed both from a clean checkout.

## Bug 1 — enums broken through the native .proto parser (fixed, TDD)
- Root cause: `Grammar::_parse_field_type` tags every named-type field `type => 'message'`
  (can't distinguish enum from message syntactically). `Schema::_resolve_message` linked the
  resolved `Schema::Enum` via `set_type_ref` but never corrected `type`, so `is_message`
  stayed true and `Codec::_encode_field` sent the enum integer down the embedded-message
  path → dies "unknown message type". Latent because the DescriptorSet/protoc path already
  sets `type => 'enum'` (what conformance exercises); only native-parse → codec was affected.
- Fix: added narrow `set_type($new_type)` to `Schema::Field` (companion to `set_type_ref`);
  `_resolve_message` now corrects the type from the resolved ref's class
  (`$ref->isa('Protobuf::Schema::Enum') ? 'enum' : 'message'`). Idempotent — no-op on the
  DescriptorSet path. Also fixes enum-valued map fields for free (same resolution recursion).
- Tests (red→green): Field unit test for `set_type` (t/unit/schema_elements.t); resolver
  type-correction test (t/resolver/schema_resolve.t); end-to-end native-parse wire + JSON
  round-trip regression (new t/codec/enum_native_parse.t).

## Bug 2 — broken example scripts (fixed)
- `examples/basic/hello.pl` and `examples/temporal/sdk_core_smoke.pl` still used
  `Proto3::Parser/Codec/Schema` — missed in the Proto3 → Protobuf rename. Straight rename.
- Verified: basic runs end-to-end; both compile clean; no `Proto3::` refs remain.

## Verification
- Full suite 1375 green on the new base. Two commits planned: enum fix, then examples.
