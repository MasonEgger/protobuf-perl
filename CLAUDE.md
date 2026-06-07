# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`Protobuf` is a **pure-Perl** Protocol Buffers implementation: wire codec, schema
model, `.proto` parser, canonical JSON mapping, well-known types, and an
ahead-of-time class generator. **Zero install-time XS, no C compiler, no
non-core CPAN runtime deps.** Despite the legacy `proto3-perl` repo name, it is
not proto3-only: it passes the full Google conformance suite at **protobuf v34**
across proto2, proto3, and editions 2023 (Required and Recommended) with zero
failures.

Requires **Perl 5.38+** (uses `feature 'class'`).

## Commands

```sh
just check       # everyday gate: lint + test (run this to close out any change)
just test        # prove -lr t
just lint        # perlcritic --gentle lib t
just check-dist  # check + full Dist::Zilla build (needs the dzil toolchain)
```

Run a single test file (the `-l` adds `lib/` to `@INC`):

```sh
prove -lv t/codec/maps.t
perl -Ilib -c lib/Protobuf/Codec.pm   # syntax-check one module
```

Conformance suite (skips cleanly when no external runner is present):

```sh
npm install protobuf-conformance@34.1.0
CONFORMANCE_TEST_RUNNER="$PWD/node_modules/protobuf-conformance/bin/conformance_test_runner-linux-x64" \
    prove -lr t/conformance/run_suite.t
```

Author-only POD tests (`skip_all` when `Test::Pod*` absent): `prove -lr xt`.

CI (`.github/workflows/ci.yml`) gates on `just check`, the dzil build, and the
conformance suite (any required **or** recommended failure fails the build).

## Architecture

Two front doors produce the same **resolved `Protobuf::Schema`**; everything
downstream consumes that schema and never the source format:

```
.proto text ─► Parser (Lexer ─► Grammar) ─┐
                                           ├─► Schema ─► Resolver ─► resolved Schema ─► Codec (wire + JSON)
protoc FileDescriptorSet ─► DescriptorSet ─┘                                            └─► Class::Generator ─► runtime/AOT classes
```

- **`Protobuf::Wire`** (`Wire/Varint.pm`, `Wire/Tag.pm`) — lowest layer: varint
  and tag encode/decode. The signed-int and zigzag rules here are subtle; see
  `.ai-sessions/lessons.md` before touching them.
- **`Protobuf::Schema`** + `Schema/{File,Message,Field,Enum,Oneof,Service}.pm` —
  the in-memory type model. `Schema/Features.pm` resolves the editions feature
  set (presence, enum openness, repeated/message encoding, UTF-8 validation) per
  file/message/field — this is how one model spans proto2/proto3/editions.
- **`Protobuf::Resolver`** — fully-qualified type-name resolution that walks
  scopes outward one level at a time to match `protoc` byte-for-byte. This is the
  project's core credibility component; front-load resolver tests.
- **`Protobuf::Parser`** + `Parser/{Lexer,Grammar}.pm` — hand-written lexer +
  grammar (`Parser/grammar.txt` is the reference). `parse_with_imports` follows
  imports transitively with cycle detection. Call `$schema->resolve` after.
- **`Protobuf::DescriptorSet`** (+ `DescriptorSet/Proto.pm`) — loads a
  `protoc`-produced `FileDescriptorSet`, already resolved. This is the path the
  conformance testee uses (proto2 + editions, not just proto3).
- **`Protobuf::Codec`** — the wire + JSON workhorse, bound to a resolved schema.
  `encode`/`decode` (hashrefs keyed by proto field name) and
  `encode_json`/`decode_json`. `Protobuf::JSON` holds the canonical mapping.
- **`Protobuf::WKT::*`** — well-known types (Timestamp, Duration, Any,
  Struct/Value/ListValue, FieldMask, Empty, scalar Wrappers).
- **`Protobuf::Class::*`** — `Generator.pm` builds message classes at runtime;
  `Codegen.pm` + `Schema/Serializer.pm` emit AOT `.pm` files via
  `bin/protobuf-gen-perl`. **AOT and runtime classes share one build path by
  construction** (an AOT module reconstructs its `Schema::File` as static Perl,
  then installs through `Class::Generator->build`) so they cannot drift.
  **Generated classes depend only on the schema + codec + WKT layers** — never
  the parser or descriptor-set layers. Keep it that way.
- **`Protobuf::Conformance`** + `bin/protobuf-conformance` — the conformance
  testee; all request-handling logic lives in the module.

### Layering rule

Dependencies flow one direction: `Wire` ← `Schema`/`Resolver` ← `Codec`/`WKT` ←
`Class`. The parser and descriptor-set are interchangeable producers of a
resolved schema; nothing below them should know which one ran.

## Conventions and gotchas

- **`feature 'class'` quirks (this is Perl 5.38.2):** an imported bareword sub
  (`use Cwd qw(abs_path)`) is invisible inside class methods — fully-qualify it.
  A file-scope `sub (signature)` immediately before a `class` block mis-parses —
  wrap such coderefs in a `do { ... }` block. `:reader` is rejected; write
  explicit `method foo { $foo }` readers. Enable with
  `use feature 'class'; no warnings 'experimental::class';`.
- **Lookup/accessor methods return explicit `undef`** (not bare `return;`) to
  mean "absent" — this is deliberate and `.perlcriticrc` excludes
  `ProhibitExplicitReturnUndef` for it. Don't "fix" these.
- **Native-parse-only type bugs hide from conformance:** the parser tags every
  named-type field `type => 'message'` (enum vs message is undecidable
  syntactically); `Schema::_resolve_message` corrects it from the resolved ref's
  class. Conformance only exercises the DescriptorSet path, so add a
  parser → codec round-trip test for any native-parse type behavior.
- **Test with a protoc differential oracle, both directions** (our-encode →
  `protoc --decode` and `protoc --encode` → our-decode) — positive-only,
  isolated-field round-trip fixtures sail past real wire bugs.
- Every source file starts with a 2-line comment; the first line begins
  `# ABOUTME: `.
- `commit-msg.md` is gitignored — never stage it.

## Reference docs in-repo

- `spec.md` — authoritative design.
- `plan.md` / `todo.md` — the original TDD roadmap.
- `V34-PLAN.md` — the full-conformance plan.
- `.ai-sessions/lessons.md` — accumulated, dated gotchas (read before deep work).
