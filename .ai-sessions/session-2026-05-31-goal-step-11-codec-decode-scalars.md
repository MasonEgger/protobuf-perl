# Session: Step 11 — Proto3::Codec decode for singular scalars + unknown-field skip

Date: 2026-05-31
Branch: v1
Commit base: d4f8129 (Step 10: Codec encode for singular scalars)

## Goal

Add the decode side of `Proto3::Codec` for singular scalar fields, reusing the
existing `%SCALAR_TYPE` dispatch table (single source of truth) and adding
unknown-field skipping. Step 11 of the BPE plan (`todo.md` 11.1–11.11).

## What changed

- **`lib/Proto3/Codec.pm`**
  - Extended each `%SCALAR_TYPE` entry with a `decode` closure mirroring its
    `encode` closure, so encode and decode share one table. Decoders wrap the
    `Proto3::Wire` decode functions (`decode_varint`, `decode_zigzag32/64`,
    `decode_fixed32/64`, `decode_float/double`) plus a length-delimited reader
    and a bool normalizer (any non-zero varint -> 1).
  - Added `decode($full_name, $bytes)`: looks up the message (UnknownType if
    absent), indexes fields by number, loops `Proto3::Wire::Tag::decode_tag`,
    decodes known singular scalars (last value wins on duplicate tag), and
    skips unknown / not-yet-handled fields via `Proto3::Wire::skip_field`.
  - Added `_apply_defaults`: declared implicit-presence singular scalars absent
    from the wire are set to their proto3 default; `optional` fields stay absent.
  - Documented decode behavior in POD (unknown-field skip, last-wins, defaults,
    propagated wire errors).
- **`t/codec/decode_scalar.t`** (new): decode `\x08\x2a` -> `{f=>42}`;
  round-trip every scalar type incl. float/double; omitted -> default and
  optional-absent stays absent; unknown VARINT/LEN/I64/I32 skipped and absent;
  duplicate singular last-wins; group wire type 3 -> DeprecatedGroup; truncated
  -> Wire::Truncated; unknown message type -> UnknownType.

## Key decisions / traps avoided

- Followed the explicit step directive: omitted implicit-presence fields decode
  to their proto3 default; `optional` (explicit-presence) absent stays absent.
- All Wire calls inside the `class {}` methods are fully qualified
  (`Proto3::Wire::...`) to dodge the Perl 5.38 `feature 'class'` bareword-import
  runtime trap. Decoder closures live as pre-class `my` lexicals in the shared
  table.
- Group wire types (3/4) and truncation propagate naturally because
  `decode_tag` / the fixed-width readers already raise the typed exceptions.

## Verification

Gate run in order, immediately before commit:
1. `perl -Ilib -c lib/Proto3/Codec.pm` -> `syntax OK`
2. `prove -lr t` -> `All tests successful.` / `Files=12, Result: PASS` (exit 0)

## Next

Step 12: Codec repeated fields (packed + unpacked).
