# Lessons Learned

## Recent
<!-- 10 most recent lessons, newest first -->
- A committed module that throws a typed exception class must commit that class too. Step 5 committed `Proto3::Wire` calling `Proto3::Exception::Wire::InvalidWireType->throw` but left the `:isa` declaration uncommitted in the working tree, so a fresh checkout was red (`->throw` on a non-existent package fails with "Can't locate object method"). Run the suite from the committed tree, not the dirty working copy, before declaring a step green (2026-05-31)
- This Perl 5.38.2 build supports the `:param` field attribute but NOT `:reader` (rejected as "Unrecognized field attribute") — write explicit `method foo { $foo }` readers instead of relying on the plan's `field $x :param :reader` (2026-05-30)
- Enable the `class` feature on this box with `use feature 'class'; no warnings 'experimental::class';` — `use v5.38` alone does not enable the field attributes, and the `experimental` pragma module is not installed (2026-05-30)
- Under the 5.38 `class` feature a `method` has no class invocant, so it can't double as a `Foo->throw(message=>...)` constructor; use a plain `sub throw { die ref $_[0] ? $_[0] : $_[0]->new(@_[1..$#_]) }` inside the class block — it works dual-mode and inherits cleanly (2026-05-30)
- This dev box has core Perl 5.38 + `prove` + `just` only — no `Test2::Suite`, `perlcritic`, `dzil`, or `cpanm`. Smoke/unit tests must run on core `Test::More` to be verifiable offline; treat the plan's `Test2::V1` preamble as CI-only or gate it behind availability (2026-05-30)
- When converting a TDD-depth spec to a plan, map each spec `T-` test ID onto exactly one RED sub-step so coverage is traceable to the spec, not invented (2026-05-30)
- Layer a protobuf-library plan strictly bottom-up (Wire → Schema → Resolver → Codec → Parser → Class → JSON/WKT → Conformance → Codegen) so every step stands on a tested foundation with no forward references (2026-05-30)
- Defer protoc differential/oracle tests to the step where the test graph can actually be built two independent ways (e.g. resolver-vs-protoc only after both parser and DescriptorSet exist), and make them `skip_all` when protoc is absent so offline `prove` still works (2026-05-30)
- When a command says "read the reference file," read it once and reuse it from context — re-issuing the same Read in later parallel batches returns "Wasted call" (2026-05-30)

## Perl
- A typed exception thrown via `Class->throw` must have its `:isa` declaration committed alongside the caller; an undeclared package autovivifies but `->throw`/`isa` fail at runtime, so the bug only surfaces on a clean checkout (2026-05-31)
- This box's Perl 5.38.2 takes `:param` but rejects `:reader` on `field`; declare readers as explicit `method foo { $foo }` (2026-05-30)
- Enable new-OO syntax with `use feature 'class'; no warnings 'experimental::class';` (not `use experimental 'class'`, whose module is absent) (2026-05-30)
- For a dual class/instance method (e.g. `throw`) under the `class` feature, use a plain `sub` inside the class block — `die ref $invocant ? $invocant : $invocant->new(@args)` — which inherits to subclasses cleanly (2026-05-30)
- Spec §4.10 wants the whole exception hierarchy in one file (multiple `class` blocks); subclasses are bare `:isa(...)` with zero code — overload, `throw`, and readers live only on the base and inherit (2026-05-30)

## Workflow
- Check for existing `plan.md`/`todo.md` before writing, and don't overwrite pre-existing `LICENSE`/`README.md` — treat an existing README as a stub to flesh out in the release step (2026-05-30)
- Raise soft ordering dependencies (e.g. maps needing embedded-message encoding from a later step) with an inline plan note + a `<CLAUDE_HELP>` flag rather than silently reordering (2026-05-30)

## Proto3 / Protobuf
- The resolver (type-name scoping) is the single component GPB::Dynamic gets wrong; front-load its unit scoping tests early and prove correctness with a protoc differential later — this is the project's core credibility bar alongside the Google conformance suite (2026-05-30)
