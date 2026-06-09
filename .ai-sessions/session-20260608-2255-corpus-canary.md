# Session — Real-world .proto corpus canary (S-001, S-002, S-003)

- **Branch**: fix/audit-remediation. Covers S-001, S-002, S-003.
- **Model**: claude-opus-4-8.

## Change
- New t/corpus/: real Google proto3 WKT files (any/timestamp/duration/struct/wrappers/empty/
  field_mask, copied from share/proto, BSD-3 headers intact) under standalone/, plus authored
  feature files under parse_only/ (gRPC aggregate options, custom options + extend, keyword
  field names, a BOM-prefixed file) that lock B-001/B-002/B-006/B-009/B-011 against regression.
- New t/parser/corpus.t (UNGATED, runs in default `prove -lr t`): every corpus file must parse;
  every standalone file must parse_with_imports and come back fully resolved (no dangling
  type_refs). This is the cheap real-world parser canary the audit's root-cause analysis called
  the single highest-leverage change — the parser is no longer tested only against bespoke
  fixtures.
- The env-gated sdk_core stress tests remain for full-graph runs; the corpus is the
  unconditional realization (closing S-001/S-002/S-003).

## Verification
- Full suite 1569 green; perlcritic --gentle clean.
