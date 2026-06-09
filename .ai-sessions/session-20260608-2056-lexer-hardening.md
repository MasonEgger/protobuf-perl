# Session — Lexer hardening (escapes, BOM, float)

- **Branch**: fix/audit-remediation. Second fix commit. Covers B-004, B-006, B-010, B-016.
- **Model**: claude-opus-4-8.

## Changes (lib/Protobuf/Parser/Lexer.pm)
- B-004: \uXXXX (4 hex) and \UXXXXXXXX (8 hex) escapes decode to UTF-8 bytes via a new
  _read_unicode_escape; fewer than the required hex digits is an error.
- B-016: the unknown-escape catch-all (which silently dropped the backslash) is now a parse
  error — malformed input surfaces instead of hiding.
- B-006: a leading UTF-8 BOM (EF BB BF) is stripped in new() so it is not an "unexpected
  character" at byte 0.
- B-010: an exponent with no digits (1e, 1e+, 1.5e) is a parse error instead of silently
  lexing as the mantissa.

## Tests
- t/parser/lexer_hardening.t (TDD). Full suite 1488 green; perlcritic --gentle clean.
