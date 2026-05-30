# Proto3 — TODO

Checkbox tracker mirroring `plan.md`. `/bpe:execute-plan` checks items off as
work completes. Each step ends by running `just check`.

---

## Phase 0 — Scaffold + Wire

### Step 1: Project scaffold and build system
- [x] 1.1 RED: t/00-load.t — Proto3 loads; VERSION defined/non-empty
- [x] 1.2 GREEN: lib/Proto3.pm (ABOUTME + VERSION + POD stub)
- [x] 1.3 dist.ini ([@Starter::Git], 5.38, MIT, Proto3)
- [x] 1.4 cpanfile (runtime + test deps)
- [x] 1.5 Directory tree (lib/, t/ subdirs, share/proto/google/protobuf/) + .gitkeep
- [x] 1.6 justfile (check / test / lint)
- [x] 1.7 .gitignore (commit-msg.md + Perl artifacts)
- [x] 1.8 .github/workflows/ci.yml skeleton (matrix per §6)
- [x] 1.9 GREEN: t/00-load.t passes
- [x] 1.10 README.md stub
- [x] 1.11 Verify: `just check`

### Step 2: Exception hierarchy
- [ ] 2.1 RED: t/unit/exception.t (T-exc-1 message/throw)
- [ ] 2.2 RED: stringification interpolation (T-exc-2)
- [ ] 2.3 RED: isa hierarchy Wire::Truncated -> Wire -> Exception (T-exc-3)
- [ ] 2.4 RED: cause default + round-trip; throw() dies
- [ ] 2.5 GREEN: lib/Proto3/Exception.pm (base: message/cause/throw/overload)
- [ ] 2.6 GREEN: all subclasses (Argument; Wire::*; Schema::*; Parser::*; Codec::*; JSON::*)
- [ ] 2.7 REFACTOR: throw/overload inherited only
- [ ] 2.8 Document POD (full hierarchy)
- [ ] 2.9 Verify: `just check`

### Step 3: Varint + zigzag (Proto3::Wire::Varint)
- [ ] 3.1 RED: varint round-trip representative values (T-wire-1)
- [ ] 3.2 RED: decode returns (value, rest); known vector varint(300)
- [ ] 3.3 RED: zigzag round-trip signed values (T-wire-2)
- [ ] 3.4 RED: truncated -> Wire::Truncated (T-wire-4); 11-byte -> VarintTooLong (T-wire-5)
- [ ] 3.5 RED: negative -> Argument
- [ ] 3.6 GREEN: lib/Proto3/Wire/Varint.pm (exports + bigint fallback)
- [ ] 3.7 RED: forced-bigint path matches native (T-wire-7)
- [ ] 3.8 GREEN: bigint code path
- [ ] 3.9 REFACTOR: shared group emit/consume helpers
- [ ] 3.10 Document POD (formulas + limits)
- [ ] 3.11 Verify: `just check`

### Step 4: Tag packing (Proto3::Wire::Tag)
- [ ] 4.1 RED: encode_tag vectors 0x08 / 0x12 (T-wire-3)
- [ ] 4.2 RED: decode_tag returns (field, wire, rest); round-trip incl. max field
- [ ] 4.3 RED: wire types 3/4 -> DeprecatedGroup (T-wire-6)
- [ ] 4.4 RED: field number 0 -> Argument
- [ ] 4.5 GREEN: lib/Proto3/Wire/Tag.pm (encode/decode + WIRE_* constants)
- [ ] 4.6 REFACTOR: reuse Varint
- [ ] 4.7 Document POD (wire-type table)
- [ ] 4.8 Verify: `just check`

### Step 5: Wire facade — fixed/float/fuzz (Proto3::Wire)
- [ ] 5.1 RED: fixed32/fixed64 little-endian round-trip + vectors
- [ ] 5.2 RED: float/double round-trip
- [ ] 5.3 RED: NaN/+Inf/-Inf round-trip (T-wire-8)
- [ ] 5.4 RED: t/wire/fuzz.t 10000 seeded inputs decode-or-typed-raise (T-wire-9)
- [ ] 5.5 GREEN: lib/Proto3/Wire.pm (re-export + fixed/float/double)
- [ ] 5.6 REFACTOR: centralize 32-bit fixed64 fallback
- [ ] 5.7 Document POD (full public API + wire table)
- [ ] 5.8 Verify: `just check`

---

## Phase 1 — Schema model + Resolver

### Step 6: Schema element classes (Proto3::Schema::*)
- [ ] 6.1 RED: Message with 2 fields, readers correct (T-schema-1)
- [ ] 6.2 RED: duplicate field number -> DuplicateField (T-schema-2)
- [ ] 6.3 RED: duplicate field name -> DuplicateField
- [ ] 6.4 RED: Field predicates is_message/is_enum/is_repeated/is_map
- [ ] 6.5 RED: is_packed only for packable repeated scalar
- [ ] 6.6 RED: Enum allow_alias validation
- [ ] 6.7 GREEN: Schema/Field.pm (+ predicates + _is_packable_scalar)
- [ ] 6.8 GREEN: Schema/Oneof.pm, Enum.pm, Message.pm, Service.pm, File.pm
- [ ] 6.9 REFACTOR: shared duplicate-detection helper
- [ ] 6.10 Document POD per class
- [ ] 6.11 Verify: `just check`

### Step 7: Schema facade + index (Proto3::Schema)
- [ ] 7.1 RED: add_file/files/file round-trip
- [ ] 7.2 RED: message/enum lookup by fq name incl. nested
- [ ] 7.3 RED: all_messages/all_enums flatten nested
- [ ] 7.4 RED: duplicate full_name on add_file -> DuplicateMessage
- [ ] 7.5 RED: unknown lookup -> undef
- [ ] 7.6 GREEN: lib/Proto3/Schema.pm (facade + recursive fq index + resolve stub)
- [ ] 7.7 REFACTOR: single recursive walker
- [ ] 7.8 Document POD
- [ ] 7.9 Verify: `just check`

### Step 8: Type resolver (Proto3::Resolver)
- [ ] 8.1 RED: fully-qualified .foo.bar.Baz resolves (T-res-1)
- [ ] 8.2 RED: relative resolves to inner coresdk.common.X (T-res-2)
- [ ] 8.3 RED: relative resolves to root when only root defined (T-res-3)
- [ ] 8.4 RED: innermost wins when both defined (T-res-4)
- [ ] 8.5 RED: nested-message search order (T-res-5)
- [ ] 8.6 RED: unresolvable -> UnresolvedType with ordered search_path (T-res-6)
- [ ] 8.7 GREEN: lib/Proto3/Resolver.pm (index + scoping resolve)
- [ ] 8.8 REFACTOR: pure candidate-list helper (assertable search_path)
- [ ] 8.9 Document POD (scoping rules)
- [ ] 8.10 Verify: `just check`

### Step 9: Wire resolve into Schema (Schema->resolve)
- [ ] 9.1 RED: message field type_ref undef before / set after resolve (T-schema-3)
- [ ] 9.2 RED: enum field type_ref set
- [ ] 9.3 RED: resolve idempotent (identity preserved)
- [ ] 9.4 RED: dangling type_name -> UnresolvedType (T-schema-4)
- [ ] 9.5 RED: respects owning message scope
- [ ] 9.6 GREEN: Schema::resolve (Resolver iteration + idempotency flag)
- [ ] 9.7 GREEN: narrow type_ref setter on Field (only mutable field)
- [ ] 9.8 REFACTOR: keep Field otherwise immutable
- [ ] 9.9 Document POD (idempotency)
- [ ] 9.10 Verify: `just check`

---

## Phase 2 — Codec (hashref)

### Step 10: Codec encode — singular scalars
- [ ] 10.1 RED: empty message -> "" (T-codec-1)
- [ ] 10.2 RED: int32=0 -> "" default-omit (T-codec-2)
- [ ] 10.3 RED: int32=42 -> \x08\x2a (T-codec-3)
- [ ] 10.4 RED: optional int32=0 -> 2 bytes (T-codec-4)
- [ ] 10.5 RED: one field per scalar type, correct wire type; sint zigzag; bytes LEN
- [ ] 10.6 RED: TypeMismatch on wrong-type value
- [ ] 10.7 GREEN: lib/Proto3/Codec.pm (new + encode singular scalars + UnknownType)
- [ ] 10.8 REFACTOR: scalar type->(wire,encoder) table
- [ ] 10.9 Document POD (encode + default-omit)
- [ ] 10.10 Verify: `just check`

### Step 11: Codec decode — singular scalars + unknown skip
- [ ] 11.1 RED: decode \x08\x2a -> {f=>42}
- [ ] 11.2 RED: round-trip each scalar type
- [ ] 11.3 RED: omitted -> proto3 default
- [ ] 11.4 RED: unknown tag skipped by wire type, absent from result (T-codec-8a)
- [ ] 11.5 RED: duplicate singular -> last wins (T-codec-9)
- [ ] 11.6 RED: group wire type 3 -> raises (T-codec-10)
- [ ] 11.7 RED: truncated -> Wire::Truncated propagates
- [ ] 11.8 GREEN: Codec::decode (tag loop + skip + defaults)
- [ ] 11.9 REFACTOR: share scalar table with encode
- [ ] 11.10 Document POD (decode + unknown handling)
- [ ] 11.11 Verify: `just check`

### Step 12: Codec — repeated (packed + unpacked)
- [ ] 12.1 RED: repeated int32 [1,2,3] -> packed 5 bytes (T-codec-5)
- [ ] 12.2 RED: decode packed back to [1,2,3]
- [ ] 12.3 RED: decode unpacked form for scalar repeated
- [ ] 12.4 RED: repeated message one entry per element round-trip
- [ ] 12.5 RED: empty repeated omitted
- [ ] 12.6 RED: mixed packed+unpacked concatenate in order
- [ ] 12.7 GREEN: encode packed/unpacked + decode both
- [ ] 12.8 REFACTOR: isolate packed-block reader
- [ ] 12.9 Document POD (packed-by-default + lenient decode)
- [ ] 12.10 Verify: `just check`

### Step 13: Codec — maps
- [ ] 13.1 RED: map<string,int32> sorted-by-key exact bytes (T-codec-6)
- [ ] 13.2 RED: round-trip map<string,int32> and map<int32,Message>
- [ ] 13.3 RED: duplicate key -> last wins
- [ ] 13.4 RED: disallowed key type -> Schema at construction
- [ ] 13.5 RED: empty map omitted
- [ ] 13.6 GREEN: map as repeated synthetic MapEntry encode/decode
- [ ] 13.7 GREEN: map key-type validation at construction
- [ ] 13.8 REFACTOR: reuse embedded-message path
- [ ] 13.9 Document POD (map determinism + key constraints)
- [ ] 13.10 Verify: `just check`

### Step 14: Codec — nested messages, enums, oneofs
- [ ] 14.1 RED: embedded message round-trip (T-codec-7); unset omitted
- [ ] 14.2 RED: enum as varint round-trip
- [ ] 14.3 RED: unknown enum number preserved as int
- [ ] 14.4 RED: oneof encode one member; decode last-wins clears sibling
- [ ] 14.5 RED: 3-level nested round-trip
- [ ] 14.6 GREEN: message/enum/oneof encode+decode
- [ ] 14.7 REFACTOR: unify recursive embedded-message path with maps
- [ ] 14.8 Document POD
- [ ] 14.9 Verify: `just check`

### Step 15: Codec — unknown-field preservation + protoc differential
- [ ] 15.1 RED: preserve_unknown_fields stores raw + re-emits byte-exact (T-codec-8b)
- [ ] 15.2 RED: default drops unknown (assert absent)
- [ ] 15.3 RED: t/codec/diff_protoc.t skip_all unless protoc
- [ ] 15.4 RED: 20 messages encode-us/decode-protoc and reverse match (T-codec-11)
- [ ] 15.5 GREEN: preserve_unknown_fields storage + re-emit
- [ ] 15.6 GREEN: protoc harness helper in t/lib
- [ ] 15.7 REFACTOR: reusable protoc harness module
- [ ] 15.8 Document POD (preserve_unknown_fields)
- [ ] 15.9 Verify: `just check`

---

## Phase 3 — Parser + DescriptorSet

### Step 16: Lexer (Proto3::Parser::Lexer)
- [ ] 16.1 RED: identifiers/fullIdent/int(dec,hex,oct)/float/bool tokens
- [ ] 16.2 RED: string literals + escapes (\n \t \" \\ \xNN octal) decode
- [ ] 16.3 RED: keyword vs identifier (message vs messages)
- [ ] 16.4 RED: punctuation tokens
- [ ] 16.5 RED: // and /* */ comments discarded
- [ ] 16.6 RED: tokens carry line+col; multi-line positions
- [ ] 16.7 RED: unterminated string/comment -> Parser with line/col
- [ ] 16.8 GREEN: lib/Proto3/Parser/Lexer.pm
- [ ] 16.9 REFACTOR: table-driven keywords/punctuation
- [ ] 16.10 Document POD (token kinds)
- [ ] 16.11 Verify: `just check`

### Step 17: Grammar core — message/fields/scalars
- [ ] 17.1 RED: syntax+package+message, field per scalar type (T-parse-2)
- [ ] 17.2 RED: json_name camelCase default
- [ ] 17.3 RED: missing syntax proto3 first stmt -> raises
- [ ] 17.4 RED: labels singular/repeated/optional(explicit presence)
- [ ] 17.5 RED: field number+name; duplicate-number delegates to Schema
- [ ] 17.6 GREEN: lib/Proto3/Parser/Grammar.pm (core constructs)
- [ ] 17.7 REFACTOR: token-cursor abstraction
- [ ] 17.8 Document POD + grammar.txt reference copy
- [ ] 17.9 Verify: `just check`

### Step 18: Grammar — nested/enum/oneof/map/reserved
- [ ] 18.1 RED: nested message dotted full_name (T-parse-3)
- [ ] 18.2 RED: enum allow_alias duplicates accepted/rejected (T-parse-4)
- [ ] 18.3 RED: oneof members get oneof_index + Schema::Oneof (T-parse-5)
- [ ] 18.4 RED: map desugars to synthetic MapEntry key=1/value=2 (T-parse-6)
- [ ] 18.5 RED: reserved numbers (ranges incl. max) + names (T-parse-7)
- [ ] 18.6 RED: interleaved comments don't break parsing (T-parse-10)
- [ ] 18.7 GREEN: Grammar enum/oneof/map/reserved/nested recursion
- [ ] 18.8 REFACTOR: reusable range-list parser
- [ ] 18.9 Document POD
- [ ] 18.10 Verify: `just check`

### Step 19: Parser facade — files/includes/options/services
- [ ] 19.1 RED: include_paths multi-root, first match, abs-path cache
- [ ] 19.2 RED: import / import public / import weak kinds (T-parse-8)
- [ ] 19.3 RED: file + message + field options into hashref
- [ ] 19.4 RED: service + rpc (stream) parse-only into Schema::Service
- [ ] 19.5 RED: parse->serialize->parse equivalent (T-parse-1)
- [ ] 19.6 RED: missing import file -> ImportNotFound
- [ ] 19.7 GREEN: lib/Proto3/Parser.pm (parse_file/parse_string + search + cache)
- [ ] 19.8 REFACTOR: centralize include-path search
- [ ] 19.9 Document POD (SYNOPSIS)
- [ ] 19.10 Verify: `just check`

### Step 20: Parser — transitive imports
- [ ] 20.1 RED: parse_with_imports collects transitive files (T-parse-9)
- [ ] 20.2 RED: diamond imports load once
- [ ] 20.3 RED: import cycle -> ImportCycle (T-parse-9)
- [ ] 20.4 RED: resolved cross-file reference links (parser+resolver)
- [ ] 20.5 GREEN: parse_with_imports (cycle set + dedup + Schema build)
- [ ] 20.6 REFACTOR: in-progress/visited bookkeeping
- [ ] 20.7 Document POD
- [ ] 20.8 Verify: `just check`

### Step 21: Parser — proto3 restrictions
- [ ] 21.1 RED: syntax proto2 -> UnsupportedSyntax (T-parse-12)
- [ ] 21.2 RED: no syntax -> UnsupportedSyntax
- [ ] 21.3 RED: required -> Parser names keyword (T-parse-13)
- [ ] 21.4 RED: group -> Parser error
- [ ] 21.5 RED: scalar default expression -> Parser error
- [ ] 21.6 RED: optional keyword ACCEPTED (no raise)
- [ ] 21.7 GREEN: restriction checks in Lexer/Grammar with line/col
- [ ] 21.8 REFACTOR: forbidden-keyword set
- [ ] 21.9 Document POD (what proto3 rejects)
- [ ] 21.10 Verify: `just check`

### Step 22: DescriptorSet load + resolver differential
- [ ] 22.1 RED: t/descriptor/load.t — FDS load matches parser output (T-fds-1)
- [ ] 22.2 RED: Type enum -> string id mapping table
- [ ] 22.3 RED: corrupt FDS -> Codec (T-fds-3)
- [ ] 22.4 RED: t/resolver/diff_protoc.t resolver matches protoc type_name (T-res-7)
- [ ] 22.5 RED: t/descriptor/sdk_core.t sdk-core FDS all messages/fields (T-fds-2)
- [ ] 22.6 GREEN: lib/Proto3/DescriptorSet/Proto.pm (bootstrap schema)
- [ ] 22.7 GREEN: lib/Proto3/DescriptorSet.pm (load_file/load_string + resolve)
- [ ] 22.8 GREEN: vendor share/.../descriptor.proto
- [ ] 22.9 REFACTOR: reuse protoc harness
- [ ] 22.10 Document POD (bootstrap + Type mapping)
- [ ] 22.11 Verify: `just check`

---

## Phase 4 — Class generation

### Step 23: Class generator — accessors + construction
- [ ] 23.1 RED: build + new + getters + to_hashref round-trip (T-class-1)
- [ ] 23.2 RED: chainable setters return $self (T-class-2)
- [ ] 23.3 RED: unknown ctor key -> Argument
- [ ] 23.4 RED: wrong-type setter -> TypeMismatch
- [ ] 23.5 RED: keyword-clash accessor package_ (T-class-8)
- [ ] 23.6 RED: descriptor returns Schema::Message
- [ ] 23.7 GREEN: lib/Proto3/Class/Generator.pm (build + reader/set/clear/descriptor)
- [ ] 23.8 GREEN: lib/Proto3/Class/Accessor.pm (name computation)
- [ ] 23.9 REFACTOR: per-field accessor spec
- [ ] 23.10 Document POD (generated-class API)
- [ ] 23.11 Verify: `just check`

### Step 24: Class generator — repeated/map/oneof/presence
- [ ] 24.1 RED: repeated getter arrayref; add_ appends; set_ replaces (T-class-4)
- [ ] 24.2 RED: map getter hashref; set_<n>_entry updates key (T-class-5)
- [ ] 24.3 RED: oneof set clears siblings; which_<oneof> (T-class-3)
- [ ] 24.4 RED: has_<n> only explicit-presence; clear_<n> resets (T-class-6)
- [ ] 24.5 GREEN: add_/set_entry/which_/has_/clear_ helper emission
- [ ] 24.6 REFACTOR: table-driven per-kind helpers
- [ ] 24.7 Document POD
- [ ] 24.8 Verify: `just check`

### Step 25: Class generator — encode/decode integration
- [ ] 25.1 RED: instance encode == codec encode of to_hashref
- [ ] 25.2 RED: Class->decode equals codec hashref decode
- [ ] 25.3 RED: new->encode->decode->to_hashref equals original (T-class-7)
- [ ] 25.4 RED: nested message fields decode into nested class instances
- [ ] 25.5 GREEN: instance encode + class decode (thin codec adapters)
- [ ] 25.6 REFACTOR: no codec logic duplication
- [ ] 25.7 Document POD
- [ ] 25.8 Verify: `just check`

---

## Phase 5 — WKT + JSON mapping

### Step 26: WKT schemas + Timestamp/Duration
- [ ] 26.1 RED: Timestamp binary + JSON RFC3339 round-trip (T-wkt-1)
- [ ] 26.2 RED: Timestamp from_epoch
- [ ] 26.3 RED: Duration fractional "1.500s" <-> 1.5s + negatives (T-wkt-2)
- [ ] 26.4 RED: malformed RFC3339/duration -> JSON::WKT
- [ ] 26.5 GREEN: vendor google.protobuf WKT .proto files
- [ ] 26.6 GREEN: WKT/Timestamp.pm + Duration.pm (to/from_json_value)
- [ ] 26.7 GREEN: lib/Proto3/WKT.pm facade
- [ ] 26.8 REFACTOR: shared RFC3339/fractional helpers
- [ ] 26.9 Document POD (JSON-form table)
- [ ] 26.10 Verify: `just check`

### Step 27: WKT — Any/Struct/FieldMask/Wrappers/Empty
- [ ] 27.1 RED: Empty <-> {}
- [ ] 27.2 RED: Any @type + inner fields (T-wkt-3)
- [ ] 27.3 RED: FieldMask "a.b,c.d" camelCase (T-wkt-4)
- [ ] 27.4 RED: Wrappers bare-value JSON (Int32Value(42)->42) (T-wkt-5)
- [ ] 27.5 RED: Struct/Value/ListValue/NullValue round-trip (T-wkt-6)
- [ ] 27.6 GREEN: WKT/{Empty,Any,Struct,FieldMask,Wrappers}.pm + register
- [ ] 27.7 REFACTOR: parametric wrapper handling (9 types)
- [ ] 27.8 Document POD per module
- [ ] 27.9 Verify: `just check`

### Step 28: JSON encode (Proto3::JSON)
- [ ] 28.1 RED: all scalar types serialize
- [ ] 28.2 RED: int64/uint64/fixed64 emit as strings (T-json-2 enc)
- [ ] 28.3 RED: enum as name default; enums_as_ints (T-json-3 enc)
- [ ] 28.4 RED: camelCase default; preserve_field_names (T-json-4)
- [ ] 28.5 RED: bytes base64
- [ ] 28.6 RED: default-omit; emit_defaults (T-json-5)
- [ ] 28.7 RED: WKT special forms delegated (T-json-6 enc); maps as objects
- [ ] 28.8 GREEN: lib/Proto3/JSON.pm + Codec::encode_json
- [ ] 28.9 REFACTOR: scalar->JSON-rep table
- [ ] 28.10 Document POD (encode rules)
- [ ] 28.11 Verify: `just check`

### Step 29: JSON decode + protoc differential
- [ ] 29.1 RED: all scalar round-trip (T-json-1)
- [ ] 29.2 RED: int64 from string AND number (T-json-2 dec)
- [ ] 29.3 RED: enum from name AND number (T-json-3 dec)
- [ ] 29.4 RED: accept camelCase AND snake_case
- [ ] 29.5 RED: unknown skipped; reject_unknown_fields raises
- [ ] 29.6 RED: invalid JSON -> JSON::Parse; string-in-int -> TypeMismatch; bad WKT -> JSON::WKT
- [ ] 29.7 RED: t/json/diff_protoc.t skip_all unless protoc (T-json-7)
- [ ] 29.8 GREEN: Codec::decode_json + JSON decode + WKT delegation
- [ ] 29.9 REFACTOR: shared camel<->snake normalization
- [ ] 29.10 Document POD (decode leniency)
- [ ] 29.11 Verify: `just check`

---

## Phase 6 — Conformance suite

### Step 30: Conformance testee
- [ ] 30.1 RED: ConformanceRequest proto->proto re-encode (t/conformance/testee.t)
- [ ] 30.2 RED: unparseable -> parse_error response
- [ ] 30.3 RED: unsupported -> skipped
- [ ] 30.4 RED: JSON<->proto cross-format paths
- [ ] 30.5 GREEN: vendor conformance.proto + protobuf_test_messages proto3
- [ ] 30.6 GREEN: lib/Proto3/Conformance.pm handle_request
- [ ] 30.7 GREEN: bin/proto3-conformance (stdin/stdout loop)
- [ ] 30.8 REFACTOR: thin bin, logic in module
- [ ] 30.9 Document POD + usage
- [ ] 30.10 Verify: `just check`

### Step 31: Run suite + CI gate
- [ ] 31.1 RED: t/conformance/run_suite.t skip_all unless runner available
- [ ] 31.2 RED: fail on any required proto3 failure; report recommended (T-conf-1/2)
- [ ] 31.3 GREEN: iterate — regression test + fix per required failure until green
- [ ] 31.4 CI: run_suite.t as required stage; recommended non-blocking (T-conf-3)
- [ ] 31.5 REFACTOR: shared fixes + lessons
- [ ] 31.6 Document README conformance status
- [ ] 31.7 Verify: `just check` + suite green

---

## Phase 7 — AOT codegen

### Step 32: proto3-gen-perl
- [ ] 32.1 RED: generate trivial .proto -> loads + round-trips (T-gen-1)
- [ ] 32.2 RED: package mapping temporal.api.common.v1 -> T::Api::Common::V1
- [ ] 32.3 RED: regeneration byte-identical (T-gen-3)
- [ ] 32.4 RED: generated classes pass shared round-trip (T-gen-2 shape)
- [ ] 32.5 RED: generated module does not use Proto3::Parser
- [ ] 32.6 GREEN: bin/proto3-gen-perl (parse_with_imports + render per file)
- [ ] 32.7 REFACTOR: shared accessor/method spec with Class::Generator
- [ ] 32.8 Document POD + bin usage + README
- [ ] 32.9 Verify: `just check`

---

## Phase 8 — sdk-core smoke + release

### Step 33: sdk-core smoke, POD, README, release prep
- [ ] 33.1 RED: t/integration/sdk_core.t skip_all unless graph path set
- [ ] 33.2 RED: load + resolve sdk-core, no UnresolvedType
- [ ] 33.3 RED: round-trip WorkflowActivation + StartWorkflowExecutionRequest (+protoc cross-check)
- [ ] 33.4 RED: xt/pod-coverage.t + xt/pod-syntax.t pass (100% public)
- [ ] 33.5 GREEN: fix sdk-core gaps (regression-test-first)
- [ ] 33.6 GREEN: add missing POD to 100% public coverage
- [ ] 33.7 README quickstart + conformance status + install + MIT
- [ ] 33.8 examples/basic/ + examples/temporal/
- [ ] 33.9 dist.ini metadata + version 0.1.0 + Changes
- [ ] 33.10 REFACTOR: final naming/consistency; remove dead scaffolding
- [ ] 33.11 Verify: `just check` + `dzil test --release` + suite + smoke; tag v0.1.0
