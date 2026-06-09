# Session — Parser: contextual keywords, extend, options, validation

- **Branch**: fix/audit-remediation (one big PR for the 23-issue audit).
- **Model**: claude-opus-4-8.
- First fix commit of the audit remediation. Covers B-001, B-002, B-003, B-005, B-009, B-011.

## Changes
- **B-001** (contextual keywords): added `_expect_name` (accepts ident OR keyword) and use it
  for field/message/enum-value/service/rpc/oneof/map names; broadened `_parse_dotted_name`
  and `_parse_field_type` to accept keywords as names/type-refs. Enum value vs `option`
  statement disambiguated by a `=` lookahead (`_next_is_punct`).
- **B-002** (custom options + extend): `extend` is now a lexer keyword and dispatched at file
  and message scope into `_parse_extend`; extensions stored on Schema::File (new `extensions`
  field) and Schema::Message (existing). Option names accept `(custom.opt)` + `.path` form.
- **B-009** (string concat) + **B-011** (aggregate options): shared `_parse_option_value`
  handles adjacent string-literal concatenation and `{ a: 1 b: 2 }` aggregates (hashref);
  `:` is now a lexer punct token.
- **B-003** (field-number bounds) + **B-005** (single package): `_parse_field_number` rejects
  0, 19000-19999, >2^29-1 (field + map fields); `_parse_package` rejects a second declaration.

## Tests (TDD, red→green)
- t/parser/keywords_as_names.t, t/parser/custom_options_extend.t,
  t/parser/field_number_and_package.t.

## Verification
- Full suite 1462 green (was 1375). perlcritic --gentle clean on changed files.
