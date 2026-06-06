# Session — proto3 conformance: float/double JSON output

- **Timestamp**: 2026-06-03 21:02
- **Branch**: v1

## Fixed
- lib/Proto3/JSON.pm float/double JSON output: non-finite values now use the
  proto3 string forms "Infinity"/"-Infinity"/"NaN" (were bare Inf/NaN tokens =
  invalid JSON); finite values keep full IEEE-754 round-trip precision via a
  shortest-round-trip %.Ng search plus a sentinel-substitution trick (JSON::PP
  re-truncates a native double to ~15 digits and has no raw-number injection, so
  the encoder emits a quoted sentinel and encode() swaps in the bare literal).
- t/json/float_output.t covers precision + inf/nan + repeated.

## Conformance progress (live)
- proto3 Required failures: 49 -> 35.
- Overall successes: 1408 -> 1423. Full suite green: 1072 tests.
- Running total this effort: 126 -> 35.

## Remaining ~35
Wrapper-type ProtobufOutput (bytes wrapper base64, bool wrapper), nested-message
JSON field deletion (optional_nested_message.corecursive.*), IllegalZeroFieldNum
+ overlong-varint protobuf input validation, "Should have failed to serialize",
Timestamp/Duration range bounds.
