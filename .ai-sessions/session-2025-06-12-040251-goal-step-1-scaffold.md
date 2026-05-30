# Session — Step 1: Project scaffold and build system

- **Timestamp (UTC):** 2025-06-12T04:02:51Z
- **Branch:** v1

## Session focus

Implement Step 1 of `plan.md` / `todo.md`: stand up the Proto3 distribution
scaffold so `use Proto3;` loads and the test gate runs green. No application
logic yet.

## Completed

- **RED** `t/00-load.t` — Test2::V0 load test asserting `use_ok('Proto3')` and
  a defined, non-empty `$Proto3::VERSION`. Confirmed failing before the module
  existed.
- **GREEN** `lib/Proto3.pm` — ABOUTME header, `package Proto3`, strict/warnings,
  `$VERSION = '0.1.0'`, `1;`, and a POD stub (NAME / DESCRIPTION / VERSION /
  LICENSE). Load test now passes.
- `dist.ini` — `[@Starter::Git]` bundle, MIT license, author, name `Proto3`,
  version 0.1.0, Perl 5.38 min, `[CPANFile]`.
- `cpanfile` — runtime (Math::BigInt, Encode) + test (Test2::V0) deps, Perl
  5.038000 floor.
- Directory tree with `.gitkeep`: `t/{unit,wire,codec,parser,json,conformance,
  descriptor,resolver,integration}` and `share/proto/google/protobuf/`.
- `justfile` — `default`, `check` (lint + test + dzil-when-present), `test`
  (`prove -lr t`), `lint` (perlcritic --gentle, skipped when not installed).
- `.gitignore` — already carried `commit-msg.md` + Perl artifacts (verified, no
  change needed for 1.7).
- `.github/workflows/ci.yml` — matrix over Perl 5.38/5.40 on ubuntu+macos
  (spec section 6), shogo82148 setup-perl, install deps + Perl::Critic +
  Dist::Zilla, run `just check`.
- `README.md` — pre-alpha stub pointing at `spec.md`, `plan.md`, `todo.md`.
- Checked off todo items 1.1–1.11.

## In progress / next steps

- Next unchecked item: **Step 2 — Exception hierarchy** (`todo.md` 2.1).
  RED tests in `t/unit/exception.t`, then `lib/Proto3/Exception.pm` base class
  (field `$message`/`$cause`, `throw`, stringify overload) plus the full
  subclass tree under `lib/Proto3/Exception/` per plan.md Step 2.

## Lessons learned

None durable this session. (See `.ai-sessions/lessons.md`.)

## Suggested skills for next session

No Perl-specific skill is available in this environment. Step 2 uses Perl's
`class` feature (`field`/`method`); no matching skill to invoke.

## Key files

- `lib/Proto3.pm`
- `t/00-load.t`
- `dist.ini`, `cpanfile`, `justfile`, `.github/workflows/ci.yml`, `README.md`

## Commands / tests

- `prove -lr t` — runs the suite (load test green, exit 0).
- `just check` — full gate (lint + test + dzil); locally `just`, `perlcritic`,
  `dzil` are not installed, so recipes degrade gracefully and CI is the source
  of truth for those.

## Open questions / blockers

- Local toolchain lacks `just`, `perlcritic`, and `dzil`; verification ran via
  `prove -lr t` directly. The CI matrix exercises the full `just check`.

## State of the tree

Dirty before commit (new scaffold files). Branch `v1`. Commit intent: scaffold
the Proto3 distribution and make the load test pass.

## Decisions made

- justfile recipes guard `perlcritic`/`dzil` with `command -v` so `just check`
  is green on partial local toolchains while still enforcing them in CI.
- CI matrix includes `v1` branch on push (current working branch) alongside
  `main`.
