# Session — Parser: real-world constructs from the Temporal graph

- **Branch**: fix/parser-realworld-N001-N004. Closes #27 #28 #29 #30 (N-001..N-004) + #31 #32 (N-006/N-007).
- **Model**: claude-opus-4-8.

## Context
Post-fix verification (verification-2026-06-09.md) ran the parser against the real Temporal
sdk-core proto graph and found constructs the audited corpus didn't exercise. Started at
67/73 parsing; ended at 92/93 (the 1 remaining is descriptor.proto = proto2, the known N-005
scope cut).

## Fixes (lib/Protobuf/Parser/Grammar.pm + Parser.pm + Schema/Enum.pm)
- N-001: enum value options `B = 1 [deprecated = true]` — parsed via _parse_field_options,
  stored on the value hashref, serialized.
- N-002 / N-004: bare `;` empty statements at file / message / enum / service scope (e.g.
  after a oneof block) are skipped.
- N-003: map field options `map<...> m = 3 [deprecated = true]` — parsed and attached.
- N-006 (found here): enum-body `reserved` ranges/names — new reserved_numbers/reserved_names
  on Schema::Enum, parsed via the shared _parse_reserved, serialized.
- N-007 (found here): list option values `tags: [ {..}, {..} ]` — new _parse_list_value
  (arrayref, elements recurse), serialized. Unblocks the openapiv2 swagger option.
- The nested no-colon aggregate form `additional_bindings { ... }` already worked.

## Tests
- t/parser/realworld_constructs.t (TDD, all constructs). t/corpus/parse_only/
  temporal_constructs.proto adds the patterns to the ungated corpus canary.
- Full suite 1584 green; perlcritic --gentle clean; xt POD pass; podchecker clean.
- Verified: 92/93 of the real Temporal graph now parses (only proto2 descriptor.proto remains).
