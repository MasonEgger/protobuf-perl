# Session — Complete the .proto serializer (B-015, B-018)

- **Branch**: fix/audit-remediation. Covers B-015, B-018.
- **Model**: claude-opus-4-8.

## Change
- Rewrote Protobuf::Parser->serialize to emit the FULL grammar, not just trivial messages:
  file/message/enum/service options, file- and nested-scope enums, services + rpc (with
  stream), oneof blocks, map<K,V> fields (recovered from the synthetic entry message, which is
  no longer emitted twice), reserved number ranges + names, and extend blocks (grouped by
  extendee). Option values render as aggregates/numbers/quoted-escaped strings that re-parse
  to the same scalars.
- B-018: the serialize docstring no longer over-promises — full round-trip now holds.

## Test
- t/parser/serialize_roundtrip.t (T-parse-1): a non-trivial proto round-trips. Asserts
  serialize idempotence across a parse cycle AND that every construct (enum, map, oneof, field
  option, nested message/enum, reserved, service, extend) survives parse -> serialize -> parse.

## Verification
- Full suite 1544 green; perlcritic --gentle clean.
