# Session — Codegen DX (keyword mangle, strict new)

- **Branch**: fix/audit-remediation. Covers B-012, B-013.
- **Model**: claude-opus-4-8.

## Changes
- B-012: Protobuf::Class::Accessor %KEYWORD now also covers length/lc/uc/lcfirst/ucfirst/
  sprintf/time/int/abs/sqrt/index/rindex/substr/pos/quotemeta/pack/unpack/vec/ord/hex/oct
  and the generated method names (new/descriptor/to_hashref/encode/decode), so a field named
  e.g. `length` or `encode` gets a `_`-suffixed accessor instead of shadowing.
- B-013: the generated new() now requires a single hashref (or no arg); a bare hash list
  new(a=>1) or a non-hashref scalar raises Protobuf::Exception::Argument instead of silently
  dropping the caller's data.

## Tests
- t/codegen/keyword_and_new.t (TDD). Full suite 1525 green; perlcritic --gentle clean.
