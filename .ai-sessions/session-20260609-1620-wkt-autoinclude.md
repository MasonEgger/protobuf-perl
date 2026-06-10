# Session — Parser auto-includes bundled WKTs (E-001)

- **Branch**: feat/E-001-parser-wkt-autoinclude. Closes #36.
- **Model**: claude-opus-4-8.

## Change (lib/Protobuf/Parser.pm)
- New `include_wkt` constructor param (default 1): auto-includes the distribution's vendored
  share/proto WKT root so a .proto importing google/protobuf/timestamp.proto, field_mask.proto,
  struct.proto, etc. resolves with no caller-configured include path (matching protoc/prost/
  protobuf.js). Appended AFTER include_paths so a user's own copy wins; set include_wkt => 0 for
  hermetic parsing.
- Located via the same __FILE__-relative approach Protobuf::Conformance already uses — NO
  File::ShareDir runtime dep (the issue's suggestion to use it was based on a wrong premise that
  it's already a dep; it isn't, and adding it would violate the zero-runtime-dep goal). No-op
  when the share tree isn't present.
- descriptor.proto stays an opaque proto2 built-in (N-005) regardless.

## Tests
- t/parser/wkt_autoinclude.t (TDD): all 7 proto3 WKTs resolve with no explicit path; descriptor
  still opaque; include_wkt => 0 opts out (ImportNotFound); user copy wins.
- t/corpus/standalone/uses_wkt.proto folds WKT-import resolution into the ungated corpus canary.

## Verification
- Full suite 1606 green; perlcritic --gentle, xt POD, podchecker clean.
- Real Temporal entry points (request_response, workflow_activation) now parse_with_imports +
  resolve with NO manual share/proto on the path (616 / 658 messages).
