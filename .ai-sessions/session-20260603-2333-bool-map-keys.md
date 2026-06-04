# Session — bool map keys + v34 investigation

- **Timestamp**: 2026-06-03 23:33
- **Branch**: v1

## Context
Verifying the proto3 conformance gate against a prebuilt runner (npm
protobuf-conformance, currently v34.1.0 / linux-x64) revealed a real proto3 bug
and a key strategic fact.

## Fixed
- lib/Proto3/JSON.pm _encode_map: a bool map key now JSON-encodes as "true"/"false"
  (was "1"/"0"). t/json/encode.t 28.7d.
- Tidy _reject_value so a null value reports as "null" instead of warning on undef.

## Strategic finding (drives the v34-compliance goal)
The v34 runner SIGABRTs against a proto3-only testee: it CHECK-fails on
Required.Proto2.ProtobufInput.UnknownOrdering because our testee correctly returns
"unknown message type: ...proto2.TestAllTypesProto2". Newer runners assume the
testee is a FULL proto2+proto3 implementation and abort the whole suite when it
isn't. => To pass v34 flawlessly we must add proto2 (and likely editions) support.
User has approved this: goal is full v34 compliance, restructure the package as
needed.

## Next
- Planning agent designs proto2/editions support + package restructuring.
- Divide implementation across subagents; test against a v32+/v34 runner.
- Baseline: proto3 is already 100% (verified vs v21.12); suite green at 1136 tests.
