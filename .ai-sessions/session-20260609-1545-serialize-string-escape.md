# Session — Serialize string escaping + numeric-string fidelity (N-008)

- **Branch**: fix/N-008-serialize-string-escape. Closes #37.
- **Model**: claude-opus-4-8.

## Context
"check for more issues": a full-pipeline sweep over the real Temporal graph (parse -> resolve
-> serialize -> reparse). Resolve completeness = 0 dangling refs on 616/658-message graphs;
codec round-trips WorkflowActivation via the PARSER path (not just descriptor-set). One serialize
bug surfaced.

## Fix (lib/Protobuf/Parser.pm)
- N-008: _serialize_option_value escaped only " and \. A string option value carrying a control
  char (newline decoded from \n, common in the openapiv2 swagger `description`) emitted a RAW
  newline inside the literal -> re-parse died "unterminated string literal". Added
  _escape_proto_string: \n/\r/\t named escapes + octal for other control bytes.
- Follow-on idempotence: a numeric-LOOKING string ("1.0") was emitted bare and re-parsed as a
  number (1), breaking byte-idempotence. Now emit bare only when the value is in canonical
  numeric form ("$v" eq $v+0); non-canonical numeric strings stay quoted and round-trip stably.

## Verification
- t/parser/serialize_string_escape.t (TDD): control chars + quotes/backslashes + numeric-string
  preservation + idempotence.
- Real Temporal graph serialize round-trip: 110/111 -> 111/111 byte-idempotent.
- Full suite 1593 green; perlcritic --gentle, xt POD, podchecker clean.
