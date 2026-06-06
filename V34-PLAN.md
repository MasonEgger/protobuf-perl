# Implementation Plan: Proto3 → Full Protobuf Conformance (protobuf v34)

**Target:** Pass the protobuf v34.1.0 conformance suite (npm `protobuf-conformance@34.1.0`,
linux-x64 prebuilt) with ZERO failures across proto2, proto3, and editions
Required+Recommended cases.

**Branch:** v1. **Dist:** Proto3 (keep the name). **Perl:** 5.38 `feature 'class'`.

---

## A. Scope — five required test message types (verified from the v34.1.0 tarball)

| Test message type (fully-qualified) | Source file | Syntax/edition |
|---|---|---|
| `protobuf_test_messages.proto3.TestAllTypesProto3` | test_messages_proto3.proto | proto3 |
| `protobuf_test_messages.proto2.TestAllTypesProto2` | test_messages_proto2.proto | proto2 |
| `protobuf_test_messages.editions.proto3.TestAllTypesProto3` | test_messages_proto3_editions.proto | edition 2023, field_presence=IMPLICIT |
| `protobuf_test_messages.editions.proto2.TestAllTypesProto2` | test_messages_proto2_editions.proto | edition 2023, enum_type=CLOSED, repeated=EXPANDED |
| `protobuf_test_messages.editions.TestAllTypesEdition2023` | test_messages_edition2023.proto | edition 2023, message_encoding=DELIMITED |

`edition_unstable` is gated behind `--maximum_edition` and is OUT OF SCOPE (don't raise the flag).

**CHECK-fail risk (confirmed):** the runner CHECK-fails / aborts the WHOLE suite if the
testee returns a fatal error (or "unknown message type") for any message type it tests.
Partial coverage = zero-completion abort. So the FIRST milestone is: all five types
parse-or-error gracefully so the suite runs to completion.

**Constructs that must be supported:**
1. proto2 explicit presence (all singular fields)
2. `required` fields + serialize/parse validation (TestAllRequiredTypesProto2)
3. default values `[default = ...]` (read-back/JSON semantics, NOT wire emission)
4. groups (TYPE_GROUP, wire types 3/4) + editions DELIMITED message_encoding
5. extensions (`extend`, extension ranges) + MessageSet wire format
6. closed enums (unknown value → unknown-field set, not the field)
7. packed=false default for proto2 repeated scalars (proto3 defaults packed)
8. editions features model (field_presence, enum_type, repeated_field_encoding,
   message_encoding, utf8_validation, json_format)

---

## B. Package restructuring — KEEP the name

Keep `Proto3` dist + `Proto3::` namespace; treat "proto3" as a brand, add proto2/editions
within it (precedent: Test2, JSON::PP). Renaming churns every file for zero conformance
benefit. Update spec.md §1 non-goals + Proto3.pm synopsis + README scope wording.

Modules that change: Wire/Tag.pm, Wire.pm, Schema.pm, Schema/{File,Field,Enum,Message}.pm,
new Schema/Features.pm, Codec.pm, DescriptorSet.pm, DescriptorSet/Proto.pm, Conformance.pm,
JSON.pm, share/proto/conformance.fds (regenerate). Parser/* deferred (testee uses the FDS).

---

## C. Schema model changes

- **Features** (new Schema/Features.pm): FeatureSet with field_presence
  (EXPLICIT/IMPLICIT/LEGACY_REQUIRED), enum_type (OPEN/CLOSED), repeated_field_encoding
  (PACKED/EXPANDED), message_encoding (LENGTH_PREFIXED/DELIMITED), utf8_validation,
  json_format. Edition defaults: proto2={EXPLICIT,CLOSED,EXPANDED,LENGTH_PREFIXED};
  proto3={IMPLICIT,OPEN,PACKED,LENGTH_PREFIXED}; edition2023={EXPLICIT,OPEN,PACKED,
  LENGTH_PREFIXED}. Schema->resolve gains a feature-resolution pass (file→message→field
  override merge), storing resolved FeatureSet on each Field/Enum.
- **File**: add `edition` + `features`.
- **Field**: `presence` (implicit/explicit/legacy_required), `default_value`,
  `message_encoding`, `is_extension`, `extendee`, resolved `features`; `is_packed`
  becomes feature-driven.
- **Enum**: `closed` flag.
- **Message**: `extension_ranges`, extension field decls, `message_set_wire_format`.
- **Schema**: extension registry (extendee fq-name → [extension fields]).

---

## D. Codec changes (lib/Proto3/Codec.pm)

1. Group wire-type 3/4 encode/decode (delimited messages); skip_field recurses to EGROUP.
2. proto2 required-field validation (encode raises serialize_error; decode raises parse_error).
3. Default application: presence-aware (implicit→type-zero; explicit→absent unless set).
4. Extension round-trip via registry; MessageSet wire format (group items type_id/message).
5. Closed-enum unknown value → unknown-field accumulator.
6. Feature-driven packed encode (lenient decode stays).
7. Presence-driven default-omit: `presence ne 'implicit' || defined oneof_index`.

---

## E. DescriptorSet + testee

- Regenerate share/proto/conformance.fds from v34 protos (local protoc is 3.21.12 and
  CANNOT compile editions — use the npm `conformance_proto_eject` helper OR a v34 protoc
  with --descriptor_set_out --include_imports). Vendor the five .proto files.
- Extend DescriptorSet/Proto.pm bootstrap: FeatureSet, FieldOptions{packed,features},
  extension, extension_range, default_value, edition, message_set_wire_format,
  TYPE_GROUP(10), LABEL_REQUIRED(2), enum closedness.
- DescriptorSet.pm: map group→delimited message, LABEL_REQUIRED→legacy_required, read
  defaults, build extension registry + ranges, compute editions/features, closed enums.
- Conformance.pm: schema() loads the new FDS (all five types); guarantee every path returns
  a ConformanceResponse, never an uncaught die (process crash = runner CHECK-fail).
  Generalize parse_runner_output to proto2/editions test-name prefixes. Add npm-runner discovery.

---

## F. JSON changes (lib/Proto3/JSON.pm)

1. Per-field utf8_validation (proto2 NONE vs proto3/editions VERIFY).
2. proto2 presence: omit unset optionals/defaults.
3. Groups: json_name handling.
4. Extensions: `[fully.qualified.ext_name]` keys.
5. Closed-enum: reject unknown enum string/number.

---

## G. Verification

- v34 runner: `npx --yes protobuf-conformance@34.1.0` → bin/conformance_test_runner-linux-x64.
- Incremental signal via `--failure_list <file>` (known-todo list; runner reports unexpected
  regressions vs expected). BUT suite must run to completion first (all five types graceful).
- Early bring-up ladder per user hint: proto2 against v26/v28, editions against v32/v33,
  full v34 last. `npx protobuf-conformance@<v>`.
- Local protoc 3.21.12 = proto2 differential oracle (NOT editions; skip those diffs).
- Terminal DoD: `--enforce_recommended` reports 0 unexpected failures, empty failure list.

---

## H. Sequenced task list

### Phase 0 — Foundation (SERIAL; gates everything)
- **T0.1 Wire un-reject groups** — Wire/Tag.pm SGROUP=3/EGROUP=4; skip_field recursive group skip.
- **T0.2 Schema features/presence/defaults/closed/extensions scaffolding** — Features.pm +
  File/Field/Enum/Message + Schema resolve pass + extension registry. Existing 1136 tests stay green.
- **T0.3 Bootstrap descriptor schema + FDS regen** — extend DescriptorSet/Proto.pm; regenerate
  conformance.fds; vendor five .proto files. All five types load with correct attributes.
- **T0.4 Testee completes the suite (CHECK-fail killer)** — Conformance.pm graceful responses;
  generalize parse_runner_output; npm-runner discovery; establish failure-list workflow.
  GATE: v34 runner runs to completion (no SIGABRT) → baseline number.

### Phase 1 — Codec by construct (PARALLEL after Phase 0)
- **T1.1** proto2 presence + packed defaults + closed enums
- **T1.2** groups / DELIMITED message_encoding
- **T1.3** required-field validation
- **T1.4** defaults & read-back semantics
- **T1.5** extensions + MessageSet (largest; may split)

### Phase 2 — JSON by construct (PARALLEL with Phase 1; touches JSON.pm)
- **T2.1** per-field utf8_validation
- **T2.2** proto2 presence in JSON
- **T2.3** groups in JSON
- **T2.4** extensions in JSON
- **T2.5** closed-enum JSON

### Phase 3 — Convergence to ZERO
- **T3.1** drain the failure list (long tail: NaN/Inf, large oneof, recursion limits,
  malformed-input rejection, field-number overflow, UTF-8 edges)
- **T3.2** CI: npx protobuf-conformance@34.1.0 --enforce_recommended as blocking gate
- **T3.3** docs/spec reconciliation (P2)

### Deferred (do NOT block)
- Parser editions/proto2 support (testee uses FDS)
- edition_unstable (gated behind --maximum_edition)
- Class/Generator + codegen for proto2/editions
