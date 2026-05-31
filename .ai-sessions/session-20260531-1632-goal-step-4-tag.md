# Session — Step 4: Tag packing (Proto3::Wire::Tag)

**Date:** 2026-05-31
**Branch:** v1
**Plan step:** Step 4 (todo.md 4.1–4.8)

## Goal

Implement proto3 field-tag pack/unpack as `Proto3::Wire::Tag`: `encode_tag` /
`decode_tag` plus the `WIRE_*` wire-type constants, building on
`Proto3::Wire::Varint`.

## What changed

- **`lib/Proto3/Wire/Tag.pm`** (new) — `encode_tag(field, wire)` emits the
  varint `(field << 3) | wire`; `decode_tag(bytes)` returns
  `(field_number, wire_type, rest)`. Exports `WIRE_VARINT=0`, `WIRE_I64=1`,
  `WIRE_LEN=2`, `WIRE_I32=5`. Reuses `encode_varint` / `decode_varint` for the
  varint itself — no varint logic is reimplemented.
- **`t/wire/tag.t`** (new) — wire-type constant values; the `0x08` / `0x12`
  spec vectors (T-wire-3); the `(field, wire, rest)` decode contract; a full
  round-trip across all four wire types and field numbers up to the proto3 max
  `536870911`; wire types 3/4 raising `Wire::DeprecatedGroup` (T-wire-6); and
  field number 0 raising `Argument`.
- **`todo.md`** — checked off 4.1–4.8.

## Key decisions

- Field-number validation lives in `encode_tag` (range `1 .. 2**29-1`); 0 and
  out-of-range raise `Proto3::Exception::Argument`.
- Deprecated proto2 group wire types (3 = group start, 4 = group end) are
  rejected in `decode_tag` with `Proto3::Exception::Wire::DeprecatedGroup`,
  since proto3 never emits groups.
- The DeprecatedGroup test hand-builds the one-byte tag rather than going
  through `encode_tag`, so `encode_tag`'s own validation can't mask the
  decode-path behaviour under test.
- Reused the existing `Proto3::Exception` hierarchy and `Proto3::Wire::Varint`
  rather than adding new error types or varint code.

## Tests

`prove -lr t` → exit 0, 248 tests, Result: PASS (load + exception + varint +
new tag suite all green). `just check` → exit 0 (perlcritic and dzil absent,
so lint/dzil stages skip; test stage green).

## Next

Step 5: Wire facade (`Proto3::Wire`) — re-export tag/varint plus fixed32/64,
float/double, and the seeded fuzz test.
