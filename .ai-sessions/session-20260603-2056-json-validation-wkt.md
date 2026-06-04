# Session — proto3 conformance: JSON input validation + Any/Struct/Value

- **Timestamp**: 2026-06-03 20:56
- **Branch**: v1

## Focus

Two parallel work streams (subagent-implemented, orchestrator-verified +
committed) driving down proto3 conformance failures.

## Fixed

### JSON input validation (lib/Proto3/JSON.pm, t/json/input_validation.t)
proto3 JSON decode now REJECTS malformed input protoc rejects, instead of
accepting it: integer fields reject out-of-range / fractional / non-integral
values (both number and string forms) via a BigInt range table; string fields
reject non-string JSON (SV-flag classifier distinguishes "12" from 12); repeated
fields reject wrong element types; top-level null for a message is rejected;
duplicate oneof members are rejected; float/double overflow is rejected.
Lenient behavior the spec REQUIRES is preserved (int64 from string OR number,
enum name OR number, camelCase OR snake_case keys).

### Any/Struct/Value/ListValue/NullValue JSON (WKT/Struct.pm, WKT/Any.pm, JSON.pm)
These were broken: Struct/Value/ListValue were identity pass-throughs that didn't
match the codec's message-field shapes (caused "Can't use string as HASH ref" and
silent field deletion); Any binary-decoded JSON-shaped inner data and never
handled the {"@type":..., "value":<special-form>} wrapper. Now: Value maps to
every JSON kind both directions; Struct <-> JSON object recursively; ListValue
<-> array; Any reads @type in any position, resolves the inner message, routes
special-form WKTs through a "value" wrapper. New t/wkt/struct_value_json.t.

## Conformance progress (live runner)

- proto3 Required failures: 101 -> 49 (combined; each stream independently 101->49
  on its own axis, together 49).
- Overall successes: 1353 -> 1408.
- Full suite green: 1064 tests.

## Remaining ~49 proto3 failures

Wrapper-type ProtobufOutput, Float/Double Infinity/NaN string forms,
Timestamp/Duration offsets + range bounds, IllegalZeroFieldNum + overlong-varint
protobuf input validation, double precision formatting, a few binary-input edges.

## Next

Continue per-bucket against /tmp/run-conf.sh.
