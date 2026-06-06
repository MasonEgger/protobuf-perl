# Session: Step 2 - Exception hierarchy

ABOUTME: Per-step session summary for plan Step 2, the typed exception
hierarchy rooted at Proto3::Exception.

- Date: 2026-05-31
- Branch: v1
- Plan step: Step 2 - Exception hierarchy (todo items 2.1-2.9)

## Goal

Build the typed exception hierarchy every Proto3 component raises through, with
a single base class that owns stringification and throwing, and a tree of
family + leaf subclasses for Wire, Schema, Parser, Codec, and JSON errors.

## What was done (TDD)

1. RED: wrote `t/unit/exception.t` covering
   - T-exc-1: `message` reader and `throw` constructing-and-dying.
   - T-exc-2: `""` overload interpolates the message in string context.
   - T-exc-3: isa chain `Wire::Truncated -> Wire -> Exception`.
   - cause defaults to undef, round-trips a supplied cause, `throw()` dies.
   - every documented subclass exists and descends from its family + base.
   Confirmed it failed (module absent).
2. GREEN: wrote `lib/Proto3/Exception.pm` using the `class` feature.
   - Base `Proto3::Exception` with `field $message :param`, `field $cause
     :param = undef`, explicit `method message` / `method cause` readers
     (this Perl 5.38.2 lacks the `:reader` field attribute).
   - `use overload '""'` and `sub throw` defined once inside the base block.
   - Subclasses declared with `:isa(...)` only; no behaviour overrides.
3. REFACTOR: verified throw/overload live solely on the base and are inherited.
4. POD: documented attributes, methods, behaviour, and the full hierarchy.
5. Checked off todo items 2.1-2.9.

## Key decisions / gotchas

- `use overload` must live INSIDE the `class` block; at file scope it binds to
  `main` and the class stringifies as a bare ref. Verified empirically.
- A `class`-feature `method` cannot be invoked as a class method, so `throw`
  is a plain `sub` inside the base block (callable as class-or-instance, and
  inherited by every `:isa` subclass).
- Overload and a plain `sub` defined on the base ARE inherited by `:isa`
  subclasses - verified before writing the module.

## Verification

- `prove -lr t` -> exit 0 (00-load.t + unit/exception.t, all pass).
- `perl -Ilib -c lib/Proto3/Exception.pm` -> exit 0.
- `just check` (lint + test) -> exit 0.

## Next

Step 3: Varint + zigzag (`Proto3::Wire::Varint`).
