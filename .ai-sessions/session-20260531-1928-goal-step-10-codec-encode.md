# Session: Step 10 — Codec encode (singular scalars)

**Date:** 2026-05-31
**Branch:** v1
**Commit:** (this step)

## What shipped

Step 10 begins Phase 2 (the high-level codec). It adds `lib/Proto3/Codec.pm`
with `new(schema => ...)` and `encode($full_name, $hashref)` for singular scalar
fields:

- Unknown message type name raises `Proto3::Exception::Codec::UnknownType`.
- Fields are emitted in ascending field-number order.
- proto3 implicit-presence default-omit: a singular (non-optional) scalar at its
  type default (0 / 0.0 / "") is dropped from the wire.
- `optional` fields use explicit presence: a set value is always emitted, even
  at the default (e.g. `optional int32 = 0` -> 2 bytes).
- Wrong-type value raises `Proto3::Exception::Codec::TypeMismatch`, naming the
  field and expected type.

The dispatch is a single pre-class lexical table `%SCALAR_TYPE` mapping each
proto3 scalar type to `{ wire, encode, is_num, default }`. This is the shared
source of truth later codec/JSON/codegen steps reuse (plan note ~L1282). All
wire encoders are called fully-qualified (`Proto3::Wire::encode_varint`, etc.).

## Decisions

- Held the scalar table and all wire calls fully-qualified / as pre-class
  lexicals so nothing trips the `feature 'class'` package-scoping trap.
- Folded the default-value check into a `method _is_default_value` rather than a
  pre-class signatured `my sub`: a file-scope signatured sub placed *before* the
  `class { ... }` block made the parser misread the first `field ... :param;`
  ("Subroutine attributes must come before the signature"). Moving the helper
  inside the class fixed it.
- TypeMismatch accepts `Math::BigInt` objects for numeric fields (legitimate
  large values); any other reference, or a non-numeric string for a numeric
  field, is a mismatch.

## Tasks done
- [x] 10.1-10.10 per todo.md (RED scenarios T-codec-1..4, per-type wire types,
  sint zigzag, bytes LEN, TypeMismatch; GREEN Codec.pm; REFACTOR scalar table;
  POD; verify).

## Tests

- New: `t/codec/encode_scalar.t` (27 tests).
- Full suite: `prove -lr t` -> Result: PASS, 484 tests (was 457 + 27).

## Lessons captured
(see .ai-sessions/lessons.md — the file-scope-signatured-sub-before-class parser
trap is a concrete instance of the existing package-scoping lesson; no new entry
added.)
