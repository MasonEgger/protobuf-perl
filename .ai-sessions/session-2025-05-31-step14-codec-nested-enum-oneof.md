# Session: Step 14 — Proto3::Codec nested messages, enums, oneofs

Date: 2025-05-31
Branch: v1
Commit: (this commit)

## Goal

Complete the `Proto3::Codec` value model (plan Step 14, spec §4.5):
singular embedded messages, enum-as-varint, and oneof fields, and unify
the embedded-message path so maps and nested message fields share one
recursive encode/decode implementation.

## What changed

- `lib/Proto3/Codec.pm`:
  - **Embedded singular messages** already routed through the shared
    `_encode_embedded_message` / `_decode_embedded_message`; confirmed
    unset message fields are omitted (exists/defined guards) and present
    empty hashrefs emit a zero-length LEN entry. Recursion through
    `encode`/`decode` handles arbitrarily deep nesting.
  - **Enum** rides the existing `%SCALAR_TYPE` varint dispatch: encodes as
    the integer value, decodes back to the integer, and an unknown
    enumerator number is preserved as that integer (never rejected).
  - **Oneof** support:
    - `_has_explicit_presence`: oneof members (like `optional`) serialize
      whenever set, even at the type default.
    - Decode builds an oneof-index -> member-names map and calls
      `_clear_oneof_siblings` after each decoded member, so the
      last-seen member wins and clears any earlier sibling.
    - `_apply_defaults` skips oneof members (absent stays absent; filling
      a default would set every member of the group at once).
  - **Refactor (14.7):** unified the embedded-message path — singular
    message fields, repeated-message elements, and map entries all use
    the one writer/reader. Stale "minimal path / Step 14 generalizes it"
    comments updated to reflect the unified state.
  - **POD (14.8):** added ENCODING/DECODING bullets for singular message
    fields, enum, and oneof; refreshed the ABOUTME and DESCRIPTION.
- `t/codec/nested.t` (new): T-codec-7 embedded round-trip + unset-omitted,
  enum-as-varint + default-omit, unknown enum preserved, oneof encode one
  member + default-still-emitted, oneof decode last-wins (both orders)
  clearing the sibling, and a 3-level nested round-trip.

## Tests

`perl -Ilib -c lib/Proto3/Codec.pm` -> syntax OK.
`prove -lr t` -> Result: PASS (Files=19), no failures.

## Notes / Next

- Environment note: this harness duplicates/injects control bytes into
  piped stdout, which corrupts live TAP. Authoritative test results come
  from writing output to a file and from the `prove` `Result: PASS` line.
- Step 15: unknown-field preservation (`preserve_unknown_fields`) and the
  protoc differential harness (T-codec-8b / T-codec-11).
