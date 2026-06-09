# Session — Opaque well-known proto2 imports (N-005)

- **Branch**: fix/N-005-opaque-wkt-imports. Closes #34.
- **Model**: claude-opus-4-8.

## Context
N-005 was downgraded from "scope cut" to a real bug: via parse_with_imports, 7/93 real
Temporal entry points failed because their import closure reaches the proto2
google/protobuf/descriptor.proto (custom-option/annotation protos). The library stores options
opaquely and never resolves descriptor's types, so it doesn't need to parse it.

## Fix (lib/Protobuf/Parser.pm)
- Treat standard proto2 well-known imports (google/protobuf/descriptor.proto,
  google/protobuf/compiler/plugin.proto) as built-ins: parse_with_imports satisfies them
  WITHOUT locating or parsing them (matching protoc/buf). The importing file still records the
  import, so serialize round-trips it.
- New `opaque_imports` constructor param to extend the set for a caller's private proto2 dep.
- A user's OWN non-well-known proto2 file is still parsed and still raises UnsupportedSyntax —
  fail-loud preserved (proto3-only is a real constraint), not a silent skip-all-proto2.

## Verification
- t/parser/opaque_wkt_imports.t (TDD): built-in opaque resolves without the file present; custom
  option still captured; user proto2 import still errors; opaque_imports extends the set.
- Against the real Temporal sdk-core graph via parse_with_imports: descriptor.proto failures
  7 -> 0; the full graph now parses+resolves (only proto2 descriptor.proto stays opaque).
- Full suite 1589 green; perlcritic --gentle, xt POD, podchecker all clean.
