# Session 2026-05-31-004 — Step 12: Codec repeated fields (packed + unpacked)

## What changed

- **`lib/Proto3/Codec.pm`** — extended encode and decode to handle repeated
  fields, reusing the existing `%SCALAR_TYPE` table:
  - **Encode:** `_encode_field` now dispatches repeated fields to
    `_encode_repeated`. A packable scalar (numeric/bool/enum) is emitted as a
    single packed `WIRE_LEN` block of concatenated element payloads
    (`[1,2,3]` int32 → `\x0a\x03\x01\x02\x03`). Repeated string/bytes/message
    are emitted one tag-prefixed entry per element. An empty/absent repeated
    field is omitted. Singular-scalar logic was factored into
    `_encode_singular_scalar`.
  - **Decode (lenient):** the tag loop now routes repeated fields to
    `_decode_repeated`, which appends to the field's arrayref in wire order. A
    packable scalar accepts BOTH the packed `WIRE_LEN` block (expanded via
    `_decode_packed_elements`) AND the unpacked form (one element per tag),
    distinguished by wire type; mixed occurrences concatenate in order. Message
    elements decode recursively. The packed-block reader is isolated as
    `_read_packed_block` (varint length prefix + raw bytes, raising
    `Wire::Truncated` on shortfall).
  - `_apply_defaults` now defaults a never-seen repeated field to `[]`.
  - Helpers added: `_is_packable`, `_field_message_name` (prefers resolved
    `type_ref`, falls back to raw `type_name`), `_encode_repeated_element`.
  - POD updated for packed-by-default encode and lenient decode.
- **`t/codec/repeated.t`** — new test file: T-codec-5 packed exact bytes,
  decode packed → list, decode unpacked scalar form, repeated message
  one-entry-per-element round-trip, empty-repeated omit, omitted→`[]`, and mixed
  packed+unpacked concatenation.
- **`todo.md`** — checked off 12.1–12.10.

## Why

Step 12 of the Phase-2 codec plan (spec §4.5): repeated fields must pack scalars
by default, emit one entry per element for messages/strings/bytes, and decode
leniently (accepting both packed and unpacked scalar encodings) to interoperate
with any conformant producer.

## How / decisions

- "Packable" is decided by the scalar type (numeric/bool/enum via the table's
  `is_num`), not the `Field` `$packed` flag — directly-constructed test schemas
  don't set `$packed`, and proto3 packs scalars by default regardless.
- Decode disambiguates packed vs unpacked purely by the occurrence's wire type:
  `WIRE_LEN` on a packable scalar means a packed block; the native scalar wire
  type means a single unpacked element. This is what makes mixed streams work.
- All cross-module calls inside the `class` block stay fully qualified
  (`Proto3::Wire::*`, `Proto3::Wire::Tag::*`) to avoid the `feature 'class'`
  bareword-at-runtime trap.

## Verification

- `perl -Ilib -c lib/Proto3/Codec.pm` → syntax OK
- `prove -lr t` → Result: PASS (Files=18, Tests=534), exit 0.

## Next steps

- Step 13: maps (`repeated MapEntry`, sorted-by-key, last-wins, key-type
  validation at construction) — reuses the embedded-message path landed here.
