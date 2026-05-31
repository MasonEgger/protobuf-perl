# Session 2026-05-31 16:55:00 — Step 6: Schema element classes

## What we did

- Implemented Phase 1 Step 6: the `Proto3::Schema::*` element classes under
  `lib/Proto3/Schema/` with construction-time invariants.
- New modules:
  - `Field.pm` — readers + `is_message`/`is_enum`/`is_repeated`/`is_map`
    predicates, `is_packed`, and private `_is_packable_scalar`.
  - `Enum.pm` — rejects duplicate value numbers unless `allow_alias` is set.
  - `Message.pm` — rejects duplicate field numbers AND duplicate field names,
    raising `Proto3::Exception::Schema::DuplicateField`.
  - `Oneof.pm`, `Service.pm`, `File.pm` — value objects with explicit readers.
  - `Util.pm` — shared `assert_unique` duplicate-detection helper.
- New test: `t/unit/schema_elements.t` (T-schema-1, T-schema-2, plus name
  duplication, predicates, packed rules, enum alias, and reader coverage).
- Checked off todo.md items 6.1–6.11.
- Restored `Proto3::Exception::Wire::InvalidWireType` to the exception
  hierarchy. The committed `Proto3::Wire::skip_field` throws this class for
  unknown wire types, but Step 5 never committed the class itself — only left
  it in the working tree. A fresh checkout therefore had `t/wire/wire.t` and
  `t/wire/fuzz.t` red. I initially reverted the uncommitted edit as "stray"
  per the dispatch instructions, then traced the two red wire tests back to
  the missing class and added the one `:isa` declaration. Suite is now green
  (prove -lr t -> 0, 451 tests).

## Why

Codec, JSON, resolver, and codegen layers all consume schema objects, so the
schema model is the central data structure (spec §4.2). Construction-time
invariants (duplicate field number/name, enum aliasing) catch malformed schemas
at build, failing fast and loud.

## Key decisions

- Translated every spec `:reader` to an explicit `method name { $field }` —
  this Perl 5.38.2 build has `:param` but not `:reader`.
- Packable-scalar set kept as a pre-class `my %PACKABLE_SCALAR` lexical to dodge
  the feature 'class' package-scoping trap (a `use constant` or imported sub
  lands in the file package, not the class package, and dies at runtime).
- Shared `assert_unique` lives in `Proto3::Schema::Util` and is always called
  fully-qualified from inside ADJUST blocks, again to avoid the scoping trap.
- `is_packed` is true only when `packed && is_repeated && _is_packable_scalar`;
  enum counts as packable (varint), string/bytes/message never do.
- `is_map` keys off `defined $map_entry`.

## What's next

- Step 7: `Proto3::Schema` facade + fully-qualified-name index
  (add_file/files/file, message/enum lookup, all_messages/all_enums flatten,
  duplicate full_name on add_file -> DuplicateMessage).

## Lessons

- When code in a committed module throws a typed exception class, that class
  must also be committed. Step 5 committed `Proto3::Wire` calling
  `Proto3::Exception::Wire::InvalidWireType->throw`, but left the class itself
  uncommitted in the working tree — so a fresh checkout was red. `->throw` on a
  non-existent class autovivifies a bare package whose `isa` does not chain,
  silently failing `isa_ok`. Always run the suite from a clean tree, not the
  dirty working copy, before declaring a step green.
