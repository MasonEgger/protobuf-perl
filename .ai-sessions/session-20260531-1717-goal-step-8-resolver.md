---
date: 2026-05-31
time: "17:17"
branch: v1
focus: "Step 8 — Proto3::Resolver: proto3 type-name scoping resolution (spec §4.3)"
---

# Session — Step 8: Proto3::Resolver

## What was done

- Added `lib/Proto3/Resolver.pm` implementing the proto3 type-reference scoping
  rules from spec §4.3 — the component the project exists to get right.
  - `new(schema => $schema)` builds a fully-qualified-name index once from
    `$schema->all_messages` + `$schema->all_enums`.
  - `resolve(type_name, current_package, current_message)`:
    - Leading-dot name → fully qualified: strip the dot, exact lookup.
    - Relative name → innermost-first scope search; first match wins.
    - No match → `Proto3::Exception::Schema::UnresolvedType` carrying the
      ordered `search_path`.
- Extracted `Proto3::Resolver::candidate_names($type_name, $current_package,
  $current_message)` as a PURE sub (not a method) so the exact ordered search
  path is directly assertable in tests (todo 8.8).
- Extended `Proto3::Exception::Schema::UnresolvedType` with `name`,
  `current_package`, `search_path` params + readers (base only had
  message/cause).
- TDD: wrote `t/resolver/resolve.t` first (RED — module absent), then
  implemented to green. 17 assertions covering T-res-1..6 plus enum resolution
  and three direct `candidate_names` order assertions.

## Key decisions

- Starting scope for relative search = `current_message` fq name when present,
  else `current_package`; walk outward by trimming the last dotted component
  down to root. One helper covers both nested-message scope (T-res-5:
  `foo.Outer.Inner.Bar`, `foo.Outer.Bar`, `foo.Bar`, `Bar`) and package-only
  scope (T-res-2/3/4).

## Trap hit (lesson)

- Under feature 'class' the pure helper had to be declared as
  `sub Proto3::Resolver::candidate_names { ... }` with `@_` unpacking. A
  signatured plain sub *before* the class block trips the parser
  ("attributes must come before the signature"); a bare-name `sub
  candidate_names` *before* the block compiles but installs into `main::`, so
  `Proto3::Resolver::candidate_names` was undefined at call time. The
  fully-qualified sub name fixes both.

## Current state

- `prove -lr t` green: 9 files, 446 tests, exit 0.
- `perl -Ilib -c lib/Proto3/Resolver.pm` OK; all lib modules compile.
- T-res-7 (protoc differential) intentionally deferred to Step 22 per plan.

## Next steps

- Step 9: wire resolution into `Schema->resolve` (Resolver iteration +
  idempotency flag; narrow `type_ref` setter on Field).
