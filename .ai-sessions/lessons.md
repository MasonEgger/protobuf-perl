# Lessons Learned

## Recent
<!-- 10 most recent lessons, newest first -->
- Perl 5.38.2 mis-parses a file-scope `sub (signature)` — named (`my sub f ($x){}`) OR anonymous (`my $f = sub ($x){}`) — when a `class` block follows it, dying "Subroutine attributes must come before the signature". Wrap such helper coderefs in a `do { ...; ($a,$b) }` block (the trick `%SCALAR_TYPE` already uses) to insulate the signatures (2026-05-31)
- proto3 encodes a negative `int32`/`int64` as its full 64-bit two's complement (`2**64 + value`, always a 10-byte varint) — NOT as a plain varint (which rejects negatives) and NOT as zigzag (that's only `sint32`/`sint64`). Decode reverses it: a varint with bit 63 set is `value - 2**64` (2026-05-31)
- `Proto3::Wire::decode_zigzag32/64` return ONLY the value, not `($value, $rest)` like the other `decode_*` — a codec consumer must read the varint separately to recover `$rest`, or the decode loop ends early and every field after a sint silently defaults (2026-05-31)
- A protoc differential oracle catches wire bugs hand-rolled fixtures miss: earlier codec round-trip tests were green despite the negative-int and zigzag-`$rest` bugs because they only used positive ints and tested zigzag as the last field. Build the oracle test BOTH directions (our-encode→`protoc --decode` and `protoc --encode`→our-decode) (2026-05-31)
- `Schema->resolve` must walk `$schema->files` (recursing into each message's nested_messages), NOT the flat `all_messages` index, because a field's resolution scope needs its declaring file's `package` as current_package and its owning message's `full_name` as current_message — the flat index has no back-pointer to the owning file/package (2026-05-31)
- A committed module that throws a typed exception class must commit that class too. Step 5 committed `Proto3::Wire` calling `Proto3::Exception::Wire::InvalidWireType->throw` but left the `:isa` declaration uncommitted in the working tree, so a fresh checkout was red (`->throw` on a non-existent package fails with "Can't locate object method"). Run the suite from the committed tree, not the dirty working copy, before declaring a step green (2026-05-31)
- This Perl 5.38.2 build supports the `:param` field attribute but NOT `:reader` (rejected as "Unrecognized field attribute") — write explicit `method foo { $foo }` readers instead of relying on the plan's `field $x :param :reader` (2026-05-30)
- Enable the `class` feature on this box with `use feature 'class'; no warnings 'experimental::class';` — `use v5.38` alone does not enable the field attributes, and the `experimental` pragma module is not installed (2026-05-30)
- Under the 5.38 `class` feature a `method` has no class invocant, so it can't double as a `Foo->throw(message=>...)` constructor; use a plain `sub throw { die ref $_[0] ? $_[0] : $_[0]->new(@_[1..$#_]) }` inside the class block — it works dual-mode and inherits cleanly (2026-05-30)
- This dev box has core Perl 5.38 + `prove` + `just` only — no `Test2::Suite`, `perlcritic`, `dzil`, or `cpanm`. Smoke/unit tests must run on core `Test::More` to be verifiable offline; treat the plan's `Test2::V1` preamble as CI-only or gate it behind availability (2026-05-30)

## Perl
- Perl 5.38.2 mis-parses a file-scope `sub (signature)` (named or anonymous) immediately before a `class` block ("Subroutine attributes must come before the signature"); wrap the coderefs in a `do {}` block to insulate the signatures (2026-05-31)
- `decode_zigzag32/64` return a single value (not `($value, $rest)`), unlike every other `Proto3::Wire` `decode_*`; a consumer needing the remainder must decode the varint separately for `$rest` (2026-05-31)
- A typed exception thrown via `Class->throw` must have its `:isa` declaration committed alongside the caller; an undeclared package autovivifies but `->throw`/`isa` fail at runtime, so the bug only surfaces on a clean checkout (2026-05-31)
- This box's Perl 5.38.2 takes `:param` but rejects `:reader` on `field`; declare readers as explicit `method foo { $foo }` (2026-05-30)
- Enable new-OO syntax with `use feature 'class'; no warnings 'experimental::class';` (not `use experimental 'class'`, whose module is absent) (2026-05-30)
- For a dual class/instance method (e.g. `throw`) under the `class` feature, use a plain `sub` inside the class block — `die ref $invocant ? $invocant : $invocant->new(@args)` — which inherits to subclasses cleanly (2026-05-30)
- Spec §4.10 wants the whole exception hierarchy in one file (multiple `class` blocks); subclasses are bare `:isa(...)` with zero code — overload, `throw`, and readers live only on the base and inherit (2026-05-30)

## Workflow
- Check for existing `plan.md`/`todo.md` before writing, and don't overwrite pre-existing `LICENSE`/`README.md` — treat an existing README as a stub to flesh out in the release step (2026-05-30)
- Raise soft ordering dependencies (e.g. maps needing embedded-message encoding from a later step) with an inline plan note + a `<CLAUDE_HELP>` flag rather than silently reordering (2026-05-30)

## Proto3 / Protobuf
- A negative `int32`/`int64` serializes as the full 64-bit two's complement (`2**64 + value`, 10 bytes), reversed on decode by subtracting `2**64` when bit 63 is set; only `sint32`/`sint64` use zigzag (2026-05-31)
- Build the protoc differential oracle both directions (our-encode→`protoc --decode` AND `protoc --encode`→our-decode); it catches wire bugs that positive-only, isolated-field round-trip fixtures sail past (2026-05-31)
- The resolver (type-name scoping) is the single component GPB::Dynamic gets wrong; front-load its unit scoping tests early and prove correctness with a protoc differential later — this is the project's core credibility bar alongside the Google conformance suite (2026-05-30)
