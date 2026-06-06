# `Proto3` — Protocol Buffers proto3 implementation for Perl

**Status:** Draft v0.1 — pre-implementation design
**Date:** 2026-05-29
**Repository:** `MasonEgger/protobuf-perl` (CPAN distribution: `Proto3`)

This document specifies the design of a pure-Perl implementation of Google
Protocol Buffers, proto3 dialect. It is the substrate that
`temporalio/sdk-perl` will depend on for protobuf encoding/decoding, but
it is intentionally a general-purpose CPAN library — usable by any Perl
project that needs to speak proto3.

The spec is written at TDD depth: every component has a public API, a
behavioral contract, a failure-mode list, and a numbered test-scenario
list (`T-` IDs). `/bpe:plan` converts this document into a sequenced
todo list.

---

## 0. Why this library exists

In May 2026, the Perl protobuf ecosystem looks like this:

| Distribution | State |
|---|---|
| `Google::ProtocolBuffers::Dynamic` (MBARBON) | Last release 2023-11. Wraps a vendored upb C library. Cross-file type resolver fails on non-trivial proto graphs (verified against Temporal sdk-core protos: `Unknown type 'coresdk.common.WorkerDeploymentVersion'`). Has a separate "DataBlob remap" bug when multiple `temporal/api/v1` files load together. |
| `Google::ProtocolBuffers` (SAXJAZMAN, GARIEV) | Last release 2013-12. Proto2 only. Effectively abandoned. |
| `Protobuf` (CJCOLLIER) | Namespace reservation registered 2025-12. No implementation. |
| `Protobuf::XS` | Does not exist. (Sometimes cited; was never published.) |
| `Google::Protobuf::Loader` | Wrapper around `GPB::Dynamic` — same backend, same bugs. |

Every other modern language has a first-party or first-party-equivalent
protobuf implementation (Python, Go, Java, Ruby ship with Google's
official implementation; Rust has `prost` and `protobuf-rust`; TypeScript
has `protobuf.js` and `@bufbuild/protobuf`). Perl never received that
investment. This library fills the gap.

---

## 0.1 Prior art — `Google::ProtocolBuffers::Dynamic` post-mortem

The closest existing option is **`Google::ProtocolBuffers::Dynamic`**.
We tried it. It does not work for our needs (or, increasingly, for
anyone's). This section documents what we learned so this library
doesn't make the same architectural mistakes.

**Project metadata (as of 2026-05-30):**

| Property | Value |
|---|---|
| Repository | <https://github.com/mbarbon/google-protobuf-dynamic> |
| CPAN | `Google-ProtocolBuffers-Dynamic` |
| Maintainer | Mattia Barbon (MBARBON) |
| Latest CPAN release | v0.43 (2023-11-23) |
| Latest GitHub push | 2024-06-04 (~2 years ago) |
| GitHub stars | 35 |
| Open issues | 8, including very recent ones documenting it no longer building on modern protobuf installs |
| License | Perl Artistic / GPL dual |

The project is effectively in dormant maintenance. The
[#52](https://github.com/mbarbon/google-protobuf-dynamic/issues/52)
("Fails compilation with new protobuf libraries", filed 2026-05-25)
and [#53](https://github.com/mbarbon/google-protobuf-dynamic/issues/53)
("Make codebase work with recent protobuf", filed 2026-05-28) issues
sit unanswered. Real users in 2026 cannot install it on current Linux
distros without rolling back system protobuf, and even then it has
runtime correctness problems on non-trivial schemas (below).

### Architectural choices it made

1. **Wraps libupb (the C "micro-protobuf" runtime) via XS.** The Perl
   side is a relatively thin layer over upb's C++ API. upb itself is
   maintained by Google but historically as an internal experimental
   project, not as a polished public library.

2. **Pulls upb in via `Alien::uPB::Core`.** That Alien distribution
   fetches a specific upb commit from a fork
   (<https://github.com/mbarbon/upb> rather than the official
   `protocolbuffers/upb`). Its `alienfile` hard-codes
   `3e4cd724ea7ac538723a2044878e7af40481fa4b` — a commit from years
   ago. Updating to current upb requires patching the Alien.

3. **System dependency chain is enormous.** To install fresh:
   `libprotobuf-dev`, `libprotoc-dev`, `libssl-dev`, `cmake`,
   `build-essential`, then CPAN's `Net::SSLeay` (because
   `Alien::uPB::Core` fetches the upb tarball over HTTPS),
   `IO::Socket::SSL`, `ExtUtils::XSpp`, `Module::Build::WithXSpp`,
   `ExtUtils::Typemaps::Default`. We hit each of these one at a time
   during the sdk-perl spike on a fresh Ubuntu 24.04 host. That alone
   makes it a difficult dependency to recommend to users.

4. **Mixed Perl/C++ build with cbindgen-ish glue.** The build invokes
   `g++` directly on `.cpp` sources that include both Perl headers
   (`EXTERN.h`) and protobuf's C++ headers — making it sensitive to
   ABI mismatches across protobuf versions (the basis of issues #51,
   #52).

### Specific bugs we hit on the Temporal sdk-core proto graph

The sdk-core proto graph (`temporalio/sdk-rust/crates/protos/protos/`)
consists of ~150 `.proto` files across packages
`temporal.api.*`, `temporal.sdk.core.*` (file packages `coresdk.*`),
and the standard `google.protobuf.*`. The reference `protoc` compiler
parses this graph cleanly. `Google::ProtocolBuffers::Dynamic` did not.

Two concrete failure modes, both empirically reproduced (the scripts
that reproduce them are preserved in
`temporalio/sdk-perl/sdk/t/spike/` for archaeological reference):

**Bug A — Cross-file type resolution failure.** Inside
`temporal/sdk/core/workflow_activation/workflow_activation.proto`
(package `coresdk.workflow_activation`), field 9 reads:

```proto
common.WorkerDeploymentVersion deployment_version_for_current_task = 9;
```

Per the proto3 [type-reference scoping
rules](https://protobuf.dev/reference/protobuf/proto3-spec/#type_references),
this resolves by walking outward from the current package:
`coresdk.workflow_activation.common.WorkerDeploymentVersion`,
`coresdk.common.WorkerDeploymentVersion`, root `common.WorkerDeploymentVersion`
— first match wins. The matching type lives at
`coresdk.common.WorkerDeploymentVersion` (defined in
`temporal/sdk/core/common/common.proto`). The reference `protoc`
resolves this. GPB::Dynamic raises:

```
Unknown type 'coresdk.common.WorkerDeploymentVersion' at
.../Google/ProtocolBuffers/Dynamic.pm line 51.
```

We tried every workaround:

- Manual ordering of `load_file` calls so common.proto loads before its
  consumers — same failure.
- Loading only the top-level proto and letting GPB resolve imports —
  same failure.
- Passing a precompiled `FileDescriptorSet` via
  `load_serialized_string` (produced by `protoc --descriptor_set_out
  --include_imports`, which contains FULLY-QUALIFIED type names in the
  descriptor) — same failure.
- AOT codegen via `protoc-gen-perl-gpd` (the ahead-of-time generator
  GPB::Dynamic itself ships) — same failure (the generated module
  uses the same runtime resolver).
- Rewriting the proto source to use fully-qualified references
  (`coresdk.common.WorkerDeploymentVersion`) — same failure.

The failure is consistent regardless of how the type information
reaches the library. This points to the resolver layer (not the
parser) being unable to link a referenced type to a loaded
definition even when both are present.

**Bug B — "Already mapped" error when loading multiple files
together.** With a fresh Dynamic instance, loading
`temporal/api/common/v1/message.proto` and then
`temporal/api/enums/v1/workflow.proto` (which is an enums-only file
with no `message` declarations and no imports), then calling
`->map({ package => 'temporal.api.common.v1', prefix => 'X::TC' })`,
produces:

```
Package 'X::TC::DataBlob' is being remapped from <file> line N
but has already been mapped from <file> line N at
.../Google/ProtocolBuffers/Dynamic.pm line 35.
```

The "remapped" file/line and "already mapped" file/line are
identical — `->map()` was called exactly once. We did not fully
diagnose the root cause; this is just another symptom of the same
brittleness in the cross-file linking.

### What this informs in our design

Direct lessons baked into this spec:

1. **No upb. No C++. No bundled binary library.** Pure Perl by
   default; optional XS in `Proto3::Wire::XS` only (and only for the
   tight inner loops). The whole reason this library exists is to
   eliminate the libupb dependency chain.

2. **Type resolution is its own component (§4.3) with its own
   exhaustive test suite, including a differential test against
   `protoc`** (T-res-7). The single largest source of trust in
   GPB::Dynamic's failures is that its resolver is buried inside upb's
   C++ code and not testable in isolation. Ours is testable.

3. **Multi-include-path support from day one.** GPB::Dynamic's
   `Google::ProtocolBuffers::Dynamic->new($root_directory)` takes
   exactly one root directory. The Temporal proto layout has two
   roots (`api_upstream/` and `local/`) and we had to symlink-merge
   them into a staging directory just to feed the library. Our
   parser accepts `include_paths => [...]` natively (§4.4).

4. **Tested against the Google conformance suite** (§4.11).
   GPB::Dynamic does not run the conformance suite (as far as we can
   determine from its repo). Without that bar, "fast and complete
   protobuf implementation" is unverifiable.

5. **Differential testing against `protoc`** in CI (§5.3, T-codec-11,
   T-res-7, T-json-7). Every component that touches the wire format
   or schema model has an oracle test: produce a value, encode with
   us / decode with `protoc`, must match byte-for-byte. Catches
   exactly the class of bugs that GPB::Dynamic shipped with.

6. **Aggressive scope discipline.** GPB::Dynamic tried to support
   proto2, proto3, gRPC, dynamic reflection, code generation, and
   custom typemaps — all in one distribution. We do **proto3 only**,
   no gRPC, with a small surface area. Less to maintain, less to
   break.

7. **Active maintenance plan, low bus factor.** Ship to CPAN with
   permissive license; document the design carefully so any future
   maintainer can pick it up. Avoid the dormant-since-2024 fate by
   keeping the surface small.

---

**Design constraints derived from the above:**

- Must handle non-trivial proto graphs (deep imports, relative type
  references, large package counts). The bar is set by Temporal sdk-core
  (~150 .proto files) — but the design must generalize.
- Must pass the [Google Protocol Buffers Conformance Test
  Suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance)
  for the proto3 subset. This is the credibility bar.
- Must be pure Perl by default. Optional XS hot path is acceptable but
  must not be required for installation. (The whole reason we're not
  using `Google::ProtocolBuffers::Dynamic` is that wrapping a C library
  was the source of bugs.)
- Must be **proto3 only**. No proto2 backward-compat. Editions
  ([protobuf "editions" feature](https://protobuf.dev/editions/overview/))
  may be added in v2.

---

## 1. Goals and non-goals

### Goals

- ✅ Pure-Perl proto3 wire-format encode and decode.
- ✅ `.proto` file lexer + parser implementing the [formal proto3
  grammar](https://protobuf.dev/reference/protobuf/proto3-spec/).
- ✅ Correct type-name resolution (relative references like
  `common.WorkerDeploymentVersion` inside `package coresdk.workflow_activation`
  resolve to `coresdk.common.WorkerDeploymentVersion` per scoping rules).
- ✅ Well-known types — `google.protobuf.{Timestamp, Duration, Empty,
  Any, Struct, ListValue, Value, NullValue, FieldMask, BoolValue,
  Int32Value, Int64Value, UInt32Value, UInt64Value, FloatValue,
  DoubleValue, StringValue, BytesValue}`.
- ✅ proto3 JSON mapping per the [JSON Mapping
  spec](https://protobuf.dev/programming-guides/json/) for use in data
  converters / debugging.
- ✅ Load Google `FileDescriptorSet` binary format (the `--descriptor_set_out`
  format produced by `protoc`).
- ✅ Both runtime schema loading AND ahead-of-time code generation
  (`proto3-gen-perl` script — modeled on `protoc-gen-python` etc.).
- ✅ `Proto3::Conformance` runner that drives the Google conformance
  suite against this implementation.
- ✅ Modern Perl (5.38+ with `feature 'class'`).
- ✅ MIT license.

### Scope update (post-v1)

The original v1 spec scoped this library to **proto3 only**. That scope has
since been extended: the library now passes the **full Google conformance
suite at protobuf v34** — proto2, proto3, and editions 2023, both Required
and Recommended (`--enforce_recommended`), with zero failures. The
conformance testee loads a v34 `FileDescriptorSet` covering all five test
message types, and the codec/JSON/schema layers model the syntax/edition
dimension via a resolved FeatureSet (presence, enum openness, repeated
encoding, message encoding, UTF-8 validation). See `V34-PLAN.md` for the
design. The "proto3 only" framing below is retained for historical context;
the brand name `Proto3` is kept (cf. `Test2`, `JSON::PP`).

### Non-goals (still out of scope)

- ❌ gRPC protocol — out of scope; we encode/decode messages, the
  transport is for another library.
- ❌ Protobuf reflection API (the runtime descriptor introspection that
  Python `descriptor_pool` exposes). Schema introspection is exposed
  more narrowly via our schema model.
- ❌ The `edition_unstable` test edition (gated behind
  `--maximum_edition`; not exercised by a default conformance run).
- ❌ `.proto` source parsing for proto2/editions in `Proto3::Parser` — the
  conformance path uses the descriptor set, not the source parser; proto2/
  editions source parsing is deferred until a consumer needs codegen for it.
- ❌ Reflection-based debugging tools (`TextFormat` etc.) — interesting
  but defer.

### Former non-goals, now SUPPORTED

- ✅ Proto2 (`syntax = "proto2";`) — explicit presence, required fields,
  defaults, groups, extensions, MessageSet, closed enums, expanded repeated.
- ✅ Editions (`edition = "2023";`) via the FeatureSet model.

---

## 2. Repository layout

```
protobuf-perl/
├── dist.ini                      # Dist::Zilla config (@Starter::Git)
├── lib/
│   └── Proto3.pm                 # Top-level loader + version
│   └── Proto3/
│       ├── Wire.pm               # Binary wire format encode/decode
│       ├── Wire/Tag.pm           # Tag + wire-type packing
│       ├── Wire/Varint.pm        # Varint + zigzag
│       ├── Schema.pm             # Schema model facade
│       ├── Schema/Message.pm
│       ├── Schema/Field.pm
│       ├── Schema/Enum.pm
│       ├── Schema/Oneof.pm
│       ├── Schema/Service.pm     # Just enough to parse; no RPC dispatch
│       ├── Schema/File.pm        # FileDescriptorProto equivalent
│       ├── Parser.pm             # .proto file parser (lexer + grammar)
│       ├── Parser/Lexer.pm
│       ├── Parser/Grammar.pm
│       ├── Resolver.pm           # Type resolution + import graph
│       ├── Codec.pm              # High-level encode/decode using schemas
│       ├── Class.pm              # Generate Perl classes from schemas
│       ├── Class/Generator.pm    # Class building machinery
│       ├── Class/Accessor.pm     # Field accessor templates
│       ├── DescriptorSet.pm      # Load/parse google.protobuf.FileDescriptorSet
│       ├── DescriptorSet/Proto.pm # Hand-encoded descriptor.proto schema (bootstrap)
│       ├── WKT.pm                # Well-known types facade
│       ├── WKT/Timestamp.pm
│       ├── WKT/Duration.pm
│       ├── WKT/Empty.pm
│       ├── WKT/Any.pm
│       ├── WKT/Struct.pm
│       ├── WKT/FieldMask.pm
│       ├── WKT/Wrappers.pm       # Bool/Int32/Int64/UInt32/UInt64/Float/Double/String/Bytes
│       ├── JSON.pm               # proto3 JSON mapping
│       ├── Exception.pm          # Exception hierarchy
│       └── Conformance.pm        # Conformance suite runner
├── bin/
│   ├── proto3-gen-perl           # AOT codegen: .proto -> .pm
│   └── proto3-conformance        # Conformance runner CLI
├── share/
│   └── proto/
│       └── google/protobuf/      # Vendored google.protobuf.* WKT .proto files
│           ├── any.proto
│           ├── duration.proto
│           ├── empty.proto
│           ├── field_mask.proto
│           ├── struct.proto
│           ├── timestamp.proto
│           ├── wrappers.proto
│           └── descriptor.proto  # For DescriptorSet loading bootstrap
├── t/
│   ├── 00-load.t
│   ├── unit/                     # per-component unit tests
│   ├── wire/                     # wire format round-trips
│   ├── parser/                   # .proto parser tests
│   ├── resolver/                 # type resolution tests
│   ├── codec/                    # end-to-end encode/decode
│   ├── wkt/                      # well-known type tests
│   ├── json/                     # JSON mapping tests
│   ├── descriptor/               # FileDescriptorSet tests
│   ├── codegen/                  # AOT codegen tests
│   └── conformance/              # Google conformance runner
├── xt/
│   ├── pod-coverage.t
│   └── pod-syntax.t
├── examples/
│   ├── basic/                    # Hello-world style proto
│   └── temporal/                 # Smoke test against a few sdk-core protos
├── conformance/                  # Submodule or vendored Google conformance suite
└── README.md
```

CPAN distribution name: `Proto3`. Main module: `Proto3` (provides version
+ a brief synopsis; the work happens in sub-modules). Naming convention:
all modules under `Proto3::*`.

---

## 3. Build & distribution

- **Build system:** Dist::Zilla with the `[@Starter::Git]` bundle (Dan
  Book / Grinnz, the 2026 modern default for Perl distributions).
- **Min Perl:** 5.38.0 (where `feature 'class'` shipped).
- **Recommended Perl:** 5.40+ (for stability of `class` and improved
  field semantics).
- **Pure Perl** by default. Optional XS variants of `Proto3::Wire::Varint`
  and `Proto3::Wire::Tag` may ship as `Proto3::Wire::XS` in a later
  release — pure-Perl path remains canonical and always works.
- **Dependencies (runtime):**
  - `JSON::PP` (core since 5.14) — for JSON mapping
  - `Math::BigInt` (core) — for int64/uint64 on 32-bit Perls
  - `File::ShareDir` — to locate vendored WKT .proto files
  - `Syntax::Keyword::Try` — for cleaner error handling
  - **Zero non-core XS deps required for installation.**
- **Build-time deps:** Dist::Zilla plugins (`@Starter::Git`,
  `[PodSyntaxTests]`, `[Test::ReportPrereqs]`).
- **Test deps:** `Test2::V1` (with explicit `use strict; use warnings;
  use utf8;` preamble — V1 does not auto-import these unlike V0).
- **License:** MIT (matches `sdk-perl` and the broader Temporal
  ecosystem; suitable for ecosystem-wide adoption).

---

## 4. Component specifications

### 4.1 `Proto3::Wire` — binary wire format

**Purpose:** Low-level encode/decode of the proto3 binary wire format.
Operates on tag/wire-type/payload triplets — does not know about message
schemas. The foundational layer.

**Wire types (proto3 spec, exact constants):**

| Numeric | Name | Used for |
|---|---|---|
| 0 | `VARINT` | int32, int64, uint32, uint64, sint32, sint64, bool, enum |
| 1 | `I64`    | fixed64, sfixed64, double |
| 2 | `LEN`    | string, bytes, embedded messages, packed repeated fields |
| 3 | `SGROUP` | deprecated; proto3 must reject |
| 4 | `EGROUP` | deprecated; proto3 must reject |
| 5 | `I32`    | fixed32, sfixed32, float |

**Public API:**

```perl
use Proto3::Wire qw(encode_varint decode_varint encode_zigzag32 decode_zigzag32
                    encode_zigzag64 decode_zigzag64
                    encode_tag decode_tag
                    WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32);

my $bytes = encode_varint($n);           # returns scalar of bytes
my ($n, $rest) = decode_varint($bytes);  # returns value + remaining bytes
my $packed = encode_tag($field_number, WIRE_VARINT);
my ($field_number, $wire_type, $rest) = decode_tag($bytes);
```

**Behavior:**

- `encode_varint($n)`: encode an unsigned 64-bit integer as a variable-
  length sequence of 7-bit-data + 1-bit-continuation bytes (LSB first).
  Up to 10 bytes max for a 64-bit value.
- `decode_varint($bytes)`: dual; raises `Proto3::Exception::Wire` on
  truncated input or >10 bytes without terminator.
- `encode_zigzag32($n)` / `encode_zigzag64($n)`: zigzag-encode a signed
  integer into an unsigned one before varint encoding.
  Formula: `(n << 1) XOR (n >> 31|63)`.
- `decode_zigzag32` / `decode_zigzag64`: reverse.
  Formula: `(n >> 1) XOR -(n & 1)`.
- `encode_tag($field_number, $wire_type)`: `($field_number << 3) | $wire_type`,
  then varint-encoded.
- `decode_tag($bytes)`: reverse, returns the field number and wire type
  separately.
- Fixed32 / Fixed64 encoding: little-endian, 4/8 bytes. Use `pack 'V'`
  and `pack 'Q<'` respectively.
- Float / Double encoding: little-endian IEEE 754. Use `pack 'f<'` and
  `pack 'd<'`.

**Failure modes:**

- Truncated varint → `Proto3::Exception::Wire::Truncated`.
- Varint > 10 bytes → `Proto3::Exception::Wire::VarintTooLong`.
- Unknown wire type (3 or 4 = deprecated groups) → `Proto3::Exception::Wire::DeprecatedGroup`.
- Negative value passed to unsigned encoder → `Proto3::Exception::Argument`.

**Test scenarios:**

- T-wire-1: Encode/decode varint for representative values (0, 1, 127,
  128, 16383, 16384, 2^32, 2^63, 2^64-1).
- T-wire-2: Round-trip zigzag for representative signed values
  (-1, 0, 1, -2147483648, 2147483647, -2^63, 2^63-1).
- T-wire-3: Tag encoding for (field=1, wire=0) → 0x08; (field=2, wire=2)
  → 0x12; round-trip arbitrary field numbers 1..536870911 (max).
- T-wire-4: Truncated varint raises.
- T-wire-5: 11-byte varint raises.
- T-wire-6: Wire type 3 in `decode_tag` raises `DeprecatedGroup`.
- T-wire-7: `pack 'Q<'` on 32-bit Perl falls back to `Math::BigInt`
  encoding (test on `$Config{ivsize} == 4` simulation).
- T-wire-8: Float NaN / +Inf / -Inf round-trip.
- T-wire-9: Random fuzz: 10000 random byte sequences fed to decoder —
  must either decode or raise typed exception, never silently misparse.

---

### 4.2 `Proto3::Schema` — schema model

**Purpose:** In-memory representation of proto3 type definitions. Built
either by the `.proto` parser (§4.4) or by loading a
`FileDescriptorSet` (§4.7). All higher-level layers (codec, JSON,
codegen) consume schema objects.

**Public classes (each in its own file under `lib/Proto3/Schema/`):**

```perl
class Proto3::Schema::File {
    field $name        :param :reader;   # 'temporal/api/common/v1/message.proto'
    field $package     :param :reader;   # 'temporal.api.common.v1' or ''
    field $syntax      :param :reader = 'proto3';
    field $imports     :param :reader = [];  # arrayref of file names
    field $messages    :param :reader = [];  # arrayref of Schema::Message
    field $enums       :param :reader = [];  # arrayref of Schema::Enum
    field $services    :param :reader = [];  # arrayref of Schema::Service
    field $options     :param :reader = {};
}

class Proto3::Schema::Message {
    field $name        :param :reader;        # short name 'Payload'
    field $full_name   :param :reader;        # 'temporal.api.common.v1.Payload'
    field $fields      :param :reader = [];
    field $oneofs      :param :reader = [];
    field $nested_messages :param :reader = [];
    field $nested_enums    :param :reader = [];
    field $reserved_numbers :param :reader = [];
    field $reserved_names   :param :reader = [];
    field $options     :param :reader = {};
}

class Proto3::Schema::Field {
    field $name        :param :reader;       # 'workflow_id'
    field $json_name   :param :reader;       # 'workflowId' (camelCase default)
    field $number      :param :reader;       # 1
    field $label       :param :reader;       # 'singular' | 'repeated' | 'map'
    field $type        :param :reader;       # 'string' | 'int32' | ... | 'message' | 'enum'
    field $type_name   :param :reader = undef;  # for message/enum: 'temporal.api.common.v1.WorkflowType'
    field $type_ref    :param :reader = undef;  # populated by resolver: blessed Schema::Message or Schema::Enum
    field $oneof_index :param :reader = undef;  # if part of a oneof
    field $packed      :param :reader = 1;   # proto3 default: scalar repeated fields packed
    field $options     :param :reader = {};
    method is_message  { $type eq 'message' }
    method is_enum     { $type eq 'enum' }
    method is_repeated { $label eq 'repeated' }
    method is_map      { $label eq 'map' }
    method is_packed   { $packed && $self->is_repeated && $self->_is_packable_scalar }
}

class Proto3::Schema::Enum {
    field $name        :param :reader;
    field $full_name   :param :reader;
    field $values      :param :reader = [];   # [{ name => 'OK', number => 0 }, ...]
    field $allow_alias :param :reader = 0;
    field $options     :param :reader = {};
}

class Proto3::Schema::Oneof {
    field $name        :param :reader;
    field $field_numbers :param :reader = [];  # field numbers in this oneof
    field $options     :param :reader = {};
}

class Proto3::Schema::Service {
    field $name        :param :reader;
    field $full_name   :param :reader;
    field $methods     :param :reader = [];   # [{ name, input_type_name, output_type_name, ... }]
    field $options     :param :reader = {};
}
```

**Top-level facade `Proto3::Schema`:**

```perl
class Proto3::Schema {
    method add_file ($file)        { ... }  # register a Schema::File
    method files                   { ... }  # arrayref
    method file ($name)            { ... }  # lookup by .proto filename
    method message ($full_name)    { ... }  # lookup by fully-qualified name
    method enum ($full_name)       { ... }
    method service ($full_name)    { ... }
    method all_messages            { ... }  # flattened
    method all_enums               { ... }
    method resolve                 { ... }  # walks references, populates $type_ref everywhere
}
```

**Behavior:**

- All schema objects are immutable after construction except for
  `$type_ref` on Field (resolved post-load).
- `Proto3::Schema->resolve` is idempotent. On second call, no-op.
- Resolution walks every Field with `$type ∈ {message, enum}` and sets
  `$type_ref` by following §4.5 scoping rules.

**Failure modes:**

- Duplicate field number in same Message → raise on construction.
- Duplicate field name → raise on construction.
- Duplicate type full_name across the whole Schema → raise on `add_file`.
- `resolve` finds an unresolvable `type_name` → raise
  `Proto3::Exception::Schema::UnresolvedType` listing the dangling
  reference and the search path attempted.

**Test scenarios:**

- T-schema-1: Construct a trivial Message with 2 fields; readers return
  the right values.
- T-schema-2: Construct a Message with duplicate field number → raises.
- T-schema-3: Construct a Message with a field of `type => 'message',
  type_name => 'foo.Bar'`; before resolve, `type_ref` undef; after
  Schema->resolve, `type_ref` is the right Message instance.
- T-schema-4: Schema with a `type_name` that doesn't exist → resolve
  raises `UnresolvedType` with the dangling name in the message.

---

### 4.3 `Proto3::Resolver` — type name resolution

**Purpose:** Implement the proto3 type-name lookup rules. **This is the
single component that GPB::Dynamic gets wrong**; making it correct here
is a primary success criterion.

**The proto3 scoping rules (from the [Language
Spec](https://protobuf.dev/reference/protobuf/proto3-spec/#type_references)
and verified empirically against the reference `protoc`):**

For a type reference `T` written in package `foo.bar.baz`:

1. **If `T` starts with `.`** (e.g. `.foo.Other`): treat as fully
   qualified. Strip the leading dot and look up exactly.
2. **Otherwise** (e.g. `common.X`): search the namespace at each
   enclosing scope, **innermost first**. For `T = common.X` in package
   `foo.bar.baz`:
   - Look up `foo.bar.baz.common.X`
   - Then `foo.bar.common.X`
   - Then `foo.common.X`
   - Then `common.X` (the root scope)
   - First match wins.

This is the rule. Sdk-core protos like
`common.WorkerDeploymentVersion` inside `package coresdk.workflow_activation`
resolve via step 2 to `coresdk.common.WorkerDeploymentVersion` (the
second lookup in the chain).

**Public API:**

```perl
my $resolver = Proto3::Resolver->new(schema => $schema);
my $ref = $resolver->resolve(
    type_name        => 'common.WorkerDeploymentVersion',
    current_package  => 'coresdk.workflow_activation',
    current_message  => undef,           # or 'coresdk.workflow_activation.SomeMessage' for nested
);
# $ref is the Schema::Message or Schema::Enum instance, or dies.
```

**Behavior:**

- Maintains an index keyed by fully-qualified name → schema object,
  built once from `$schema->all_messages` + `$schema->all_enums`.
- Handles nested type scoping correctly: a reference inside a nested
  message has the parent message's name as part of the search prefix.

**Failure modes:**

- No match found → `Proto3::Exception::Schema::UnresolvedType { name,
  current_package, search_path }` — `search_path` is the ordered list
  of fully-qualified names attempted, for easy debugging.

**Test scenarios (all empirically verified against `protoc` behavior):**

- T-res-1: Fully-qualified `.foo.bar.Baz` from any package → resolves
  directly.
- T-res-2: Relative `common.X` from package `coresdk.workflow_activation`
  with `coresdk.common.X` defined → resolves to `coresdk.common.X`.
- T-res-3: Same relative ref with **only** `common.X` defined at root →
  resolves to root `common.X` (innermost-first beats outer matches).
- T-res-4: Relative ref with both `coresdk.common.X` and root
  `common.X` defined — must resolve to `coresdk.common.X` (innermost
  wins, matching protoc).
- T-res-5: Nested-message scope — type ref from inside
  `package foo; message Outer { message Inner { Bar b = 1; } }` —
  search order is `foo.Outer.Inner.Bar`, `foo.Outer.Bar`, `foo.Bar`,
  `Bar`.
- T-res-6: Unresolvable type → exception with full `search_path` listing
  exactly the names attempted, in order.
- T-res-7: **Differential test against `protoc`**: for the sdk-core
  proto graph, every cross-file reference our resolver produces must
  match what `protoc --descriptor_set_out` produces in its
  `FileDescriptorProto.MessageType[].field[].type_name` field. (This
  is the test that proves we don't have GPB::Dynamic's bug.)

---

### 4.4 `Proto3::Parser` — `.proto` file lexer + parser

**Purpose:** Parse `.proto` source files into `Schema::File` instances.

**Files:** `lib/Proto3/Parser.pm` (facade), `lib/Proto3/Parser/Lexer.pm`,
`lib/Proto3/Parser/Grammar.pm`.

**Public API:**

```perl
my $parser = Proto3::Parser->new(
    include_paths => [ '/path/to/protos', '/another/path' ],
);
my $file = $parser->parse_file('temporal/api/common/v1/message.proto');
# $file is a Schema::File instance.

# Or parse a string:
my $file = $parser->parse_string('foo.proto', $proto_source);

# Walk imports automatically:
my $schema = $parser->parse_with_imports('top.proto');
# $schema is a Proto3::Schema with all transitively-imported files added.
```

**Grammar source of truth:** [proto3 formal
grammar](https://protobuf.dev/reference/protobuf/proto3-spec/) — copy
maintained alongside this code in `lib/Proto3/Parser/grammar.txt` for
reference.

**Lexer tokens:**

- Identifier, fullIdent (dot-separated)
- IntLit (dec/hex/oct), FloatLit, StringLit (single/double quoted, with
  escapes), BoolLit (`true`/`false`)
- Keywords: `syntax`, `import`, `weak`, `public`, `package`, `option`,
  `enum`, `message`, `service`, `rpc`, `returns`, `stream`, `repeated`,
  `optional`, `reserved`, `to`, `max`, `oneof`, `map`
- Reserved words for types: `double`, `float`, `int32`, `int64`,
  `uint32`, `uint64`, `sint32`, `sint64`, `fixed32`, `fixed64`,
  `sfixed32`, `sfixed64`, `bool`, `string`, `bytes`
- Punctuation: `{ } ( ) [ ] = , ; < > .`
- Comments: `//` line, `/* */` block — discarded.

**Parser:** Recursive-descent. Hand-written (not a parser-generator
output, to keep the dependency footprint zero).

**Behavior:**

- `parse_file($name)`: searches `include_paths` for the file (first
  match wins), reads it, parses it. Caches by absolute path so repeated
  imports are deduplicated.
- `parse_with_imports($name)`: parse the top file; then for each
  `import` directive, recursively `parse_file` the imported file. Cycle
  detection via in-progress set. Build a `Schema` with all files
  added.
- `syntax = "proto3";` is required as the first non-comment statement.
  Files declaring `proto2` or no syntax → error.
- proto3 forbids: `required`, groups, default-value expressions on
  scalar fields. Parser raises on each.
- `optional` keyword in proto3 (added in protobuf 3.15) IS supported
  and marks a field as having explicit presence.

**Failure modes:**

- Syntax errors → `Proto3::Exception::Parser` with line/column.
- Missing imported file → `Proto3::Exception::Parser::ImportNotFound`.
- Import cycle → `Proto3::Exception::Parser::ImportCycle`.
- `syntax = "proto2";` → `Proto3::Exception::Parser::UnsupportedSyntax`.
- Use of forbidden proto2-only keywords → `Proto3::Exception::Parser`
  with which keyword.

**Test scenarios:**

- T-parse-1: Trivial single-message proto round-trips through parse
  + serialize-to-string + parse → identical schema.
- T-parse-2: All scalar types parse correctly (one field per type).
- T-parse-3: Nested messages parse with correct full names.
- T-parse-4: Enums with `allow_alias = true` accept duplicate numbers;
  without it, they raise.
- T-parse-5: `oneof` block — fields inside get `oneof_index` set.
- T-parse-6: `map<string, Payload> attrs = 1;` parses as a repeated
  field with synthetic MapEntry message (per proto3 spec — maps are
  syntactic sugar over `repeated MapEntry`).
- T-parse-7: `reserved 5, 10 to 15, 20 to max;` correctly populates
  `reserved_numbers`. `reserved "foo", "bar";` populates
  `reserved_names`.
- T-parse-8: `import public "foo.proto";` and `import weak "bar.proto";`
  parse with the right import kind.
- T-parse-9: `parse_with_imports` follows transitive imports; cycle
  detection raises.
- T-parse-10: Comments inside fields don't break parsing.
- T-parse-11: All sdk-core protos parse without errors (smoke).
- T-parse-12: A proto2 file raises `UnsupportedSyntax`.
- T-parse-13: `required string foo = 1;` raises (proto2-only).

---

### 4.5 `Proto3::Codec` — high-level encode/decode

**Purpose:** Use a resolved Schema to encode/decode message values
(plain Perl hashrefs or generated class instances).

**Public API:**

```perl
my $codec = Proto3::Codec->new(schema => $schema);

# Hashref interface (works without code generation):
my $bytes = $codec->encode('temporal.api.common.v1.Payload', {
    metadata => { encoding => 'json/plain' },
    data     => '{"hello":"world"}',
});
my $hash = $codec->decode('temporal.api.common.v1.Payload', $bytes);
# $hash is a plain Perl hashref.

# Class interface (when code generation has run):
my $msg = T::Api::Common::V1::Payload->new({ encoding => ..., data => ... });
my $bytes = $msg->encode;
my $msg2  = T::Api::Common::V1::Payload->decode($bytes);
```

**Encoding behavior (proto3 spec):**

- Singular scalar fields with default value (0, "", false, 0.0, empty
  bytes) are **omitted** from the wire (proto3 implicit-presence
  default). Exception: fields declared `optional` use the
  `explicit-presence` proto3.15+ semantics and ARE serialized when set.
- Singular message fields encoded as length-delimited (wire type 2).
  Omitted entirely if not set (no presence indicator for messages in
  proto3 implicit-presence; explicit-presence message fields use
  per-spec semantics).
- Repeated scalar fields use **packed encoding by default** (proto3
  spec). Each element is varint/fixed-width concatenated, then wrapped
  in one length-delimited tag.
- Repeated message fields are emitted as one tag-prefixed length-
  delimited entry per element.
- Maps are encoded as `repeated MapEntry`. MapEntry has fields `key`
  (field 1) and `value` (field 2). Encoding order is implementation-
  defined; we sort by key for determinism.
- Enums are encoded as varint (the integer value).
- Bytes are encoded as length-delimited (the raw bytes; no
  null-termination, no escaping).

**Decoding behavior:**

- Unknown fields (tag not in schema) are skipped per their wire type
  (varint = drain bytes, length-delimited = skip N bytes, etc.) — NOT
  preserved by default. Optional flag `preserve_unknown_fields => 1`
  on the codec stores them in `$decoded->{__unknown_fields__}` as a
  raw byte string for round-trip purposes.
- Duplicate singular fields: last-write-wins (proto3 spec).
- Repeated fields: append each occurrence.
- Maps: last-write-wins per key.
- Group wire types (3, 4) raise — proto3 forbids groups.

**Failure modes:**

- Unknown message type name → `Proto3::Exception::Codec::UnknownType`.
- Type mismatch (e.g. passing a string where an int32 is expected) →
  `Proto3::Exception::Codec::TypeMismatch` with field name + expected
  type + got type.
- Required field check: proto3 has no required fields, so no required-
  field error path. But `optional` fields with explicit presence: if
  not set, accessor returns undef vs default — codec writes if set.
- Truncated input during decode → propagated `Wire::Truncated`.
- Map key with disallowed type (must be integral or string per spec) →
  `Proto3::Exception::Schema` at codec construction time.

**Test scenarios:**

- T-codec-1: Encode an empty message → 0 bytes.
- T-codec-2: Singular int32 = 0 → 0 bytes (proto3 default-omit).
- T-codec-3: Singular int32 = 42 → tag byte + varint(42) = 2 bytes.
- T-codec-4: `optional int32 = 0` (explicit presence, set) → 2 bytes
  (default-omit does NOT apply).
- T-codec-5: Repeated int32 = [1, 2, 3] → packed: tag + length-3 +
  varint(1) + varint(2) + varint(3) = 5 bytes.
- T-codec-6: Map<string,int32> = { a => 1, b => 2 } → two MapEntry
  encodings, sorted by key.
- T-codec-7: Embedded message round-trips with all field values.
- T-codec-8: Decode message with unknown tag — by default dropped, with
  `preserve_unknown_fields` round-trips.
- T-codec-9: Decode message with duplicate singular tag — last value
  wins.
- T-codec-10: Group wire type (3) in input → raises.
- T-codec-11: **Cross-implementation round-trip:** encode with our
  codec, decode with `protoc --decode`, must match. Encode with
  `protoc --encode`, decode with our codec, must match. Run for 20
  representative messages.

---

### 4.6 `Proto3::Class` — Perl class generation

**Purpose:** Given a `Schema::Message`, dynamically build a Perl class
(at runtime) or write a `.pm` file (ahead-of-time). The class has typed
accessors, an `->encode` / `->decode` interface, and is constructible
from a hashref.

**Public API:**

```perl
# Runtime class generation (used by Proto3::DescriptorSet::map):
my $class_name = Proto3::Class::Generator->build(
    schema   => $schema,
    message  => $message,    # Schema::Message
    target_package => 'T::Api::Common::V1::Payload',
);
# After this, T::Api::Common::V1::Payload->new({...}) works.

# Generated class API (built whichever way):
package T::Api::Common::V1::Payload;
# ... (auto-generated)

T::Api::Common::V1::Payload->new({ encoding => 'json/plain', data => '...' });
T::Api::Common::V1::Payload->new->set_encoding('json/plain')->set_data('...');
$msg->encoding;                   # getter
$msg->set_encoding($s);           # setter
$msg->has_encoding;               # presence check (only for explicit-presence fields)
$msg->clear_encoding;
$msg->encode;                     # bytes
T::Api::Common::V1::Payload->decode($bytes);
T::Api::Common::V1::Payload->descriptor;  # returns Schema::Message
$msg->to_hashref;
$msg->to_json;                    # proto3 JSON form
```

**Behavior:**

- Generated class uses `feature 'class'`. Each Field becomes a
  `field $_name :param :reader`.
- Setter `set_<name>($value)` validates type (raises `TypeMismatch` on
  mismatch), assigns, returns `$self` (chainable).
- Repeated fields: getter returns arrayref. Setter replaces.
  Append helper `add_<name>($element)`.
- Map fields: getter returns hashref. Setter replaces. Per-key helper
  `set_<name>_entry($key, $value)`.
- Oneof: setting one field in the oneof clears all other fields in the
  same oneof (per spec). `which_<oneof_name>` returns the name of the
  currently-set field (or undef).
- Class instance carries its own `Schema::Message` reference (for
  introspection by encoder).

**Failure modes:**

- Constructor with unknown key in hashref → `Proto3::Exception::Argument`
  with the key name.
- Setter with wrong type → `TypeMismatch`.

**Test scenarios:**

- T-class-1: Generated class for a simple message round-trips a hashref.
- T-class-2: Chainable setters return `$self`.
- T-class-3: Oneof — setting one field clears the other.
- T-class-4: Repeated field — `add_` helper appends; `set_` replaces.
- T-class-5: Map field — `set_<n>_entry` updates per-key.
- T-class-6: `has_<n>` only present for explicit-presence fields.
- T-class-7: Round-trip via class → `encode` → `decode` → equal.
- T-class-8: Class with field clash with a Perl keyword (e.g.
  `package`, `print`) — accessor is `package_` (trailing underscore,
  matching `protoc-gen-python`'s pattern).

---

### 4.7 `Proto3::DescriptorSet` — descriptor.proto loading

**Purpose:** Load a binary `google.protobuf.FileDescriptorSet` (what
`protoc --descriptor_set_out` produces) into a `Proto3::Schema`. This
lets users use `protoc` as the parser (avoiding our parser entirely if
desired) — useful as both a productivity tool and a differential
testing oracle.

**The bootstrap problem:** `descriptor.proto` is a normal .proto file
that we'd need our schema model to load — but our schema model doesn't
exist until we can load descriptor.proto. Solution: hand-write the
schema for `google.protobuf.FileDescriptorSet` in
`lib/Proto3/DescriptorSet/Proto.pm` as Perl literals (a one-time
manual implementation matching the upstream descriptor.proto exactly).
Then use that schema to decode incoming `.fds` files via the normal
codec.

**Files:** `lib/Proto3/DescriptorSet.pm`,
`lib/Proto3/DescriptorSet/Proto.pm` (the bootstrap schema —
hand-maintained alongside upstream descriptor.proto releases).

**Public API:**

```perl
my $schema = Proto3::DescriptorSet->load_file('/path/to/all.fds');
my $schema = Proto3::DescriptorSet->load_string($fds_bytes);
# Returns a fully-populated Proto3::Schema, including the resolve() pass.
```

**Behavior:**

- Decodes the FileDescriptorSet using the bootstrap schema +
  `Proto3::Codec`.
- For each `FileDescriptorProto`, builds a `Schema::File` instance.
- For each `DescriptorProto` inside the file, builds a `Schema::Message`.
- For each `FieldDescriptorProto`, builds a `Schema::Field`. The
  protobuf `Type` enum (`TYPE_INT32 = 5` etc.) maps to our string
  type identifiers (`'int32'` etc.).
- Calls `$schema->resolve` before returning.

**Failure modes:**

- Decoding fails (corrupt FDS) → `Proto3::Exception::Codec`.
- A `FieldDescriptorProto` references an unknown `type_name` → resolver
  raises.

**Test scenarios:**

- T-fds-1: Round-trip — start with a `.proto`, run `protoc
  --descriptor_set_out`, load via `DescriptorSet->load_file`, verify
  the resulting Schema matches what `Proto3::Parser` produces from the
  same `.proto` source.
- T-fds-2: Load the sdk-core proto graph as a descriptor set; verify
  every message and field is present.
- T-fds-3: Load a corrupted FDS → typed exception.

---

### 4.8 `Proto3::WKT` — well-known types

**Purpose:** Hand-written specializations for the
`google.protobuf.*` well-known types. The codec is generic, but WKTs
have **special JSON encodings** (per the proto3 JSON spec) that the
generic JSON layer needs to delegate to.

**Files:** `lib/Proto3/WKT/{Timestamp,Duration,Empty,Any,Struct,FieldMask,Wrappers}.pm`.

Each WKT module:
- Defines or imports the canonical `Schema::Message` for that type.
- Provides convenience constructors (e.g., `Proto3::WKT::Timestamp->from_epoch($seconds)`).
- Implements `to_json_value` and `from_json_value` for proto3 JSON
  special-casing (e.g., Timestamp is `"2026-05-29T12:34:56Z"` in JSON
  form, not a `{ seconds, nanos }` object).

**Notable WKT JSON encodings (per spec):**

| Type | JSON form |
|---|---|
| `Timestamp` | RFC 3339 string `"2026-05-29T12:34:56.789Z"` |
| `Duration` | string `"60.5s"` (always seconds, fractional ok, trailing `s`) |
| `Empty` | `{}` |
| `Any` | `{ "@type": "type.googleapis.com/foo.Bar", ...fields... }` |
| `Struct` | JSON object (recursive Value mapping) |
| `Value` | any JSON value (null/bool/number/string/array/object) |
| `ListValue` | JSON array |
| `NullValue` | JSON `null` |
| `FieldMask` | string `"a.b,c.d"` (comma-separated camelCase paths) |
| `Wrappers` (Int32Value etc.) | the inner value directly, NOT wrapped: `42` not `{ "value": 42 }` |

**Test scenarios:**

- T-wkt-1: Timestamp round-trip via binary and via JSON.
- T-wkt-2: Duration with fractional seconds (`1.500s` → 1.5s).
- T-wkt-3: Any with a real inner message — JSON form includes `@type`.
- T-wkt-4: FieldMask round-trip with camelCase paths.
- T-wkt-5: Wrappers — Int32Value(42) JSON-encodes as `42`.
- T-wkt-6: Struct ↔ arbitrary JSON object round-trip.

---

### 4.9 `Proto3::JSON` — proto3 JSON mapping

**Purpose:** Encode/decode messages in proto3 JSON form (per the
[proto3 JSON mapping
spec](https://protobuf.dev/programming-guides/json/)). Used by data
converters, debugging tools, and any consumer that wants
schema-validated JSON.

**Public API:**

```perl
my $json_string = $codec->encode_json('temporal.api.common.v1.Payload', $hashref);
my $hashref     = $codec->decode_json('temporal.api.common.v1.Payload', $json_string);
# Or on generated classes:
$msg->to_json;        # returns JSON string
T::Api::Common::V1::Payload->from_json($json_string);
```

**Encoding rules (the parts that surprise people):**

- Field names are emitted as **camelCase** by default (matching the
  `json_name` calculated from the proto field name). `data_blob` →
  `dataBlob`. Option `preserve_field_names => 1` flips this.
- Int64 / Uint64 / Fixed64 / Sfixed64 are emitted as **strings** (not
  numbers) to avoid JSON precision loss. JSON numbers `> 2^53` are
  unreliable across JSON parsers.
- Enums are emitted as **strings** (the enum value name) by default.
  Option `enums_as_ints => 1` emits the numeric value.
- Bytes are emitted as base64-encoded strings.
- Singular default-valued scalar fields are **omitted** by default
  (matching binary proto3 default-omit semantics). Option
  `emit_defaults => 1` includes them.
- WKTs use their special encodings (see §4.8).
- Maps emit as JSON objects.

**Decoding rules:**

- Accept both camelCase and snake_case field names (lenient input).
- Accept both string and numeric forms for int64/etc.
- Accept both enum string and enum number.
- Unknown fields → silently skip by default; option `reject_unknown_fields
  => 1` raises.

**Failure modes:**

- Invalid JSON → `Proto3::Exception::JSON::Parse`.
- Schema mismatch (e.g., string in int field) → `TypeMismatch`.
- WKT with malformed string form (e.g., bad RFC3339 timestamp) →
  `Proto3::Exception::JSON::WKT`.

**Test scenarios:**

- T-json-1: Round-trip a message with all scalar types.
- T-json-2: Int64 field emits as string; decodes from both string and
  number.
- T-json-3: Enum emits as string; decodes from string AND from number.
- T-json-4: camelCase by default; `preserve_field_names => 1` flips.
- T-json-5: Default-valued field omitted by default; `emit_defaults`
  includes.
- T-json-6: All WKTs have correct JSON forms (delegated to §4.8 tests).
- T-json-7: Differential against `protoc --decode --print_jsonpb`:
  encode-via-protoc + decode-via-us, and vice versa, must produce
  byte-identical canonical form.

---

### 4.10 `Proto3::Exception` — exception hierarchy

**Files:** `lib/Proto3/Exception.pm` (base), `lib/Proto3/Exception/*.pm` (subclasses).

**Base:**

```perl
class Proto3::Exception {
    field $message :param :reader;
    field $cause   :param :reader = undef;

    method throw (%fields) { die $class->new(%fields) }
}
use overload q{""} => sub { $_[0]->message }, fallback => 1;
```

**Subclasses (each a `class :isa(Proto3::Exception)`):**

- `Argument` — caller error (bad input to a public API).
- `Wire`, `Wire::Truncated`, `Wire::VarintTooLong`, `Wire::DeprecatedGroup`.
- `Schema`, `Schema::UnresolvedType`, `Schema::DuplicateField`,
  `Schema::DuplicateMessage`.
- `Parser`, `Parser::ImportNotFound`, `Parser::ImportCycle`,
  `Parser::UnsupportedSyntax`.
- `Codec`, `Codec::UnknownType`, `Codec::TypeMismatch`.
- `JSON`, `JSON::Parse`, `JSON::WKT`.

**Test scenarios:**

- T-exc-1: `Proto3::Exception::Argument->throw(message => 'foo')` is
  catchable via `eval` with the message preserved.
- T-exc-2: Stringification works inside string interpolation.
- T-exc-3: `isa` hierarchy: `Wire::Truncated->isa('Proto3::Exception::Wire')`
  and `->isa('Proto3::Exception')`.

---

### 4.11 `Proto3::Conformance` — Google conformance runner

**Purpose:** Drive the [Google Protocol Buffers Conformance Test
Suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance)
against this implementation. **Passing the proto3 subset of this suite
is the credibility bar for the project.**

**How the suite works:**

The Google conformance runner spawns a "testee" child process that
speaks a simple stdin/stdout protocol:

1. Runner writes a `ConformanceRequest` protobuf to testee's stdin.
2. Testee parses, processes (encode/decode in the requested format),
   writes `ConformanceResponse` to stdout.
3. Repeat until EOF.

Both `ConformanceRequest` and `ConformanceResponse` are themselves
protobuf messages (their .proto lives in
`conformance/conformance.proto` in the upstream repo).

**Files:** `lib/Proto3/Conformance.pm`, `bin/proto3-conformance` (CLI
testee binary).

**Public API:**

```bash
# Run as testee:
proto3-conformance
# (reads ConformanceRequest from stdin, writes ConformanceResponse to stdout, loops)

# Run the suite:
cd conformance/
./conformance_test_runner --enforce_recommended ./bin/proto3-conformance
```

**Behavior:**

- The testee loads the schema for `protobuf_test_messages.proto3` (the
  test message types upstream defines).
- For each request: decode `payload` in the requested input format
  (proto wire / proto JSON), then re-encode in the requested output
  format, return the result.
- Failures return `ConformanceResponse { parse_error | serialize_error |
  runtime_error | skipped }` per the spec.

**Test scenarios:**

- T-conf-1: The conformance runner reports "All required tests passed"
  for proto3.
- T-conf-2: All recommended tests pass too (`--enforce_recommended`).
- T-conf-3: CI runs the conformance suite on every PR.

This is the **single most important credibility test in the project**.
Until it passes, the library is alpha.

---

### 4.12 `proto3-gen-perl` — AOT code generator

**Purpose:** Read one or more `.proto` files and emit `.pm` files
under a chosen output directory. Used for projects (like `sdk-perl`)
that want compiled, statically-discoverable Perl classes for each
protobuf message — better startup time, IDE autocompletion, no
runtime parse-failure surprises.

**File:** `bin/proto3-gen-perl`

**Public CLI:**

```bash
proto3-gen-perl \
    --include /path/to/protos \
    --output  /path/to/lib \
    --package-prefix T::Api \
    temporal/api/common/v1/message.proto \
    temporal/api/failure/v1/message.proto

# Output: writes lib/T/Api/Common/V1/Message.pm (one .pm per .proto file).
```

**Behavior:**

- Uses `Proto3::Parser->parse_with_imports`.
- Maps protobuf packages → Perl namespaces using the `--package-prefix`
  rule: protobuf `temporal.api.common.v1` → Perl `T::Api::Common::V1`
  (each protobuf path component PascalCased).
- For each Message, emits a Perl class file (matching what
  `Proto3::Class::Generator` produces at runtime) into the output
  tree.
- The emitted classes do NOT depend on the parser or descriptor-set
  code — only on `Proto3::Wire`, `Proto3::Codec`, and the WKTs. Keeps
  the runtime deps minimal for generated-only consumers.

**Test scenarios:**

- T-gen-1: Generate code for a trivial .proto, the resulting .pm
  loads and round-trips a message.
- T-gen-2: Generate code for the sdk-core proto graph; resulting
  classes pass the same round-trip tests as the runtime-generated
  versions.
- T-gen-3: Regenerating produces byte-identical output (deterministic
  codegen).

---

## 5. Testing strategy

### 5.1 Test framework

- **`Test2::V1`** everywhere (per the 2026 Perl test-framework consensus).
- Canonical preamble for every test file:

  ```perl
  use v5.38;
  use strict;
  use warnings;
  use utf8;
  use Test2::V1;
  ```

- `Test2::Plugin::DieOnFail` in `xt/` for fast author-test feedback.

### 5.2 Test pyramid

- **Unit tests (`t/unit/`):** per-component, no external deps.
- **Round-trip tests (`t/wire/`, `t/codec/`, `t/wkt/`, `t/json/`):**
  exhaustive coverage of the encoding surface.
- **Differential tests (`t/codec/diff_protoc.t`):** generate test
  messages, encode-with-us / decode-with-protoc and vice versa, assert
  byte equality. `protoc` is the oracle.
- **Conformance tests (`t/conformance/`):** drive the Google
  conformance suite (§4.11). **Mandatory before any v1 release.**
- **sdk-core smoke (`t/integration/sdk_core.t`):** load the
  `temporalio/sdk-rust` proto graph from a configurable path; round-trip
  `WorkflowActivation` and `StartWorkflowExecutionRequest`. This is the
  proof-of-purpose test.

### 5.3 Differential testing setup

The conformance suite needs `protoc` on `$PATH`. CI installs
`protobuf-compiler` and `libprotoc-dev`. Tests that need `protoc` skip
gracefully when it's absent (so casual `prove -lj4` works without it).

---

## 6. CI

GitHub Actions in `.github/workflows/ci.yml`.

**Matrix:**

- **OS:** `ubuntu-22.04`, `ubuntu-24.04`, `macos-13` (Intel), `macos-14`
  (Apple Silicon).
- **Perl:** `5.38`, `5.40`, `5.42`.
- **System deps:** `apt install -y build-essential protobuf-compiler
  libprotoc-dev` (for differential + conformance tests).

**Stages:**

1. Install Perl via `shogo82148/actions-setup-perl@v1`.
2. Install system deps.
3. Install Perl deps via `cpanm`.
4. Run `dzil test --release`.
5. Run conformance suite — must pass all `required` tests; report
   recommended-test count.
6. Run differential tests against installed `protoc`.

A non-blocking Windows job with `strawberry-perl` + Windows protobuf,
allowed to fail, for early portability signal.

---

## 7. Phased roadmap

### Phase 0 — scaffold + bootstrap (3 days)

- Repo structure, `dist.ini`, `cpanfile`, CI skeleton.
- `Proto3.pm` + `Proto3::Exception` hierarchy.
- `Proto3::Wire` complete with full test suite (T-wire-1 through T-wire-9).
- **Goal:** wire format is solid; everything else builds on it.

### Phase 1 — schema model + resolver (3 days)

- `Proto3::Schema::*` classes per §4.2.
- `Proto3::Resolver` per §4.3 with the differential test against
  `protoc` (T-res-7) — that test alone validates we don't have
  GPB::Dynamic's bug.
- `Proto3::Exception::Schema::*`.

### Phase 2 — codec for hashref interface (5 days)

- `Proto3::Codec->encode/decode` for hashref input/output.
- Handles all scalar types, repeated (packed + unpacked), maps, oneofs,
  nested messages, enums.
- `preserve_unknown_fields` round-trip.
- T-codec-1 through T-codec-11 pass.

### Phase 3 — parser (4 days)

- `Proto3::Parser::Lexer` + `Proto3::Parser::Grammar`.
- `Proto3::Parser->parse_file / parse_with_imports`.
- All sdk-core protos parse (T-parse-11).
- `Proto3::DescriptorSet->load_file` lands here too (uses Codec + the
  hand-written bootstrap descriptor.proto schema).

### Phase 4 — class generation (3 days)

- `Proto3::Class::Generator` for runtime class building.
- Generated classes have all accessors + presence + chainable setters.
- `to_hashref`, `to_json` (delegates to Phase 5).
- T-class-* pass.

### Phase 5 — JSON mapping (3 days)

- `Proto3::JSON` per §4.9.
- `Proto3::WKT::*` for all well-known types per §4.8.
- T-json-* and T-wkt-* pass.

### Phase 6 — conformance suite (variable; depends on bugs found)

- Wire up `bin/proto3-conformance`.
- Run the Google conformance suite; fix every required-test failure.
- Track `recommended` test pass count; goal is 100%.
- **Until this passes, the library is alpha.**

### Phase 7 — AOT codegen (2 days)

- `bin/proto3-gen-perl`.
- T-gen-* pass.

### Phase 8 — sdk-core smoke + v0.1 release

- `t/integration/sdk_core.t` loads the entire sdk-core proto graph and
  round-trips `WorkflowActivation` and `StartWorkflowExecutionRequest`.
- POD coverage 100% on public classes.
- README with quickstart.
- Tag v0.1.0, release to CPAN under `Proto3`.

**Total estimated effort: ~3 weeks of focused work for v0.1.**

---

## 8. References

- [Protocol Buffers proto3 Language Spec](https://protobuf.dev/reference/protobuf/proto3-spec/)
- [Protocol Buffers Encoding](https://protobuf.dev/programming-guides/encoding/) — wire format
- [Protocol Buffers proto3 Language Guide](https://protobuf.dev/programming-guides/proto3/)
- [Protocol Buffers JSON Mapping](https://protobuf.dev/programming-guides/json/)
- [Google Conformance Test Suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance)
- [`descriptor.proto`](https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/descriptor.proto) — for `Proto3::DescriptorSet` bootstrap
- [`prost` Rust crate](https://github.com/tokio-rs/prost) — for reference; how a well-designed protobuf library looks
- [`@bufbuild/protobuf` TypeScript](https://github.com/bufbuild/protobuf-es) — another good reference implementation
- [Google Protocol Buffers Python](https://github.com/protocolbuffers/protobuf/tree/main/python) — Google's reference, the gold standard
- `temporalio/sdk-perl/PLAN.md` — downstream consumer this library
  unblocks. The Phase 0 risk spike in that project is what produced
  this library spec.
