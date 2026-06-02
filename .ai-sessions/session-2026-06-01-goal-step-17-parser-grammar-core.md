# Session 2026-06-01 — Step 17: Grammar core (Proto3::Parser::Grammar)

Phase 3 continues. The recursive-descent grammar now consumes the Step 16 lexer
token stream and builds the Schema model for the core constructs.

## What changed

- **`lib/Proto3/Parser/Grammar.pm`** (new) — hand-written recursive-descent
  parser. Written as a plain package with a stateful token cursor (same shape
  as the lexer), avoiding the 5.38.2 class-feature bareword traps.
  - `new(source => ..., file_name => ...)` tokenizes via
    `Proto3::Parser::Lexer` and stores the token array + cursor position.
  - **Token cursor (17.7):** one `_peek` / `_next` / `_expect` abstraction
    reused throughout, plus `_is_punct` / `_is_keyword` convenience predicates.
    `_expect($type, $value?)` raises a positioned `Parser` error on mismatch.
  - **`parse`** requires `syntax = "proto3";` as the first statement (missing,
    a different first token, or a non-`proto3` value all raise
    `Proto3::Exception::Parser` with line/col), then loops over `package` and
    `message` at file scope, returning a `Proto3::Schema::File`.
  - **Fields:** `[repeated|optional] type name = number;`. A bare field is
    `singular`; `repeated`/`optional` set the label. Only scalar types
    (table-driven `%SCALAR_TYPE`) are accepted at this stage. The codec already
    treats `label eq 'optional'` as the explicit-presence flag, so no separate
    presence field is needed.
  - **`json_name`** defaults to camelCase of the field name via
    `s/_(.)/\U$1/g` (`data_blob` → `dataBlob`, `a_b_c_d` → `aBCD`).
  - Message `full_name` is `<package>.<Name>` (or bare name when no package).
  - Duplicate field numbers/names are NOT re-checked here — they surface from
    `Proto3::Schema::Message`'s construction-time `ADJUST` as
    `Proto3::Exception::Schema::DuplicateField` (delegated to Step 6).
  - Full POD documenting the API, behavior, and the grammar-reference pointer.
- **`lib/Proto3/Parser/grammar.txt`** (new) — reference copy of the proto3
  formal grammar (spec §4.4 / protobuf.dev), documentation only.
- **`t/parser/grammar_core.t`** (new) — covers 17.1–17.5: all 15 scalar types
  one-per-field with correct type/number/label (T-parse-2); package + message
  full_name; json_name camelCase; missing-syntax and non-syntax-first-statement
  raise `Parser`; labels singular/repeated/optional; field name+number captured;
  duplicate field number surfaces `Schema::DuplicateField`.
- **`todo.md`** — checked off 17.1–17.9.

## Why

Step 17 (spec §4.4) is the core of the parser: it turns lexer tokens into the
Schema model so later steps (nested/enum/oneof/map, imports, services,
restrictions) can extend a working recursive-descent base.

## How / decisions

- Plain package, not `feature 'class'` — matches the lexer and keeps the cursor
  helpers (`_peek`/`_next`/`_advance`-style) natural; also dodges the documented
  5.38.2 bareword-inside-class-method runtime trap.
- The single token-cursor abstraction was baked in from the start (17.7) rather
  than refactored in later; `_expect` centralizes positioned error reporting.
- `optional` maps to `label => 'optional'` (no new Field param) because the
  codec's `_has_explicit_presence` already keys off that label value.
- Duplicate-number detection is intentionally delegated to the Schema layer so
  there's one source of truth for the invariant.

## Verification

- Final gate (single sequential command):
  `perl -Ilib -c lib/Proto3/Parser/Grammar.pm && prove -lr t` →
  Result: PASS, GATE_EXIT=0.

## Next steps

- Step 18: Grammar — nested messages (dotted full_name), enum (allow_alias),
  oneof (oneof_index + Schema::Oneof), map (synthetic MapEntry), reserved
  ranges/names, interleaved comments.
