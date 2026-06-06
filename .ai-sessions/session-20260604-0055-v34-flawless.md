# Session — V34 conformance: FLAWLESS (0 failures) + CI gate

- **Branch**: v1 — V34-PLAN.md goal COMPLETE.

## MILESTONE: 100% v34 conformance
CONFORMANCE SUITE PASSED: 2806 successes, 0 skipped, 0 expected failures,
0 unexpected failures. proto2 + proto3 + editions, Required AND Recommended
(--enforce_recommended). Verified via the live npm protobuf-conformance@34.1.0
runner through t/conformance/run_suite.t (the exact CI path).

## Final fixes this session
- proto2 extension JSON round-trip: a "[fq.extension_name]" JSON key decodes to a
  sidecar and re-encodes verbatim. Cleared the last failure (FieldNameExtension).
  t/json/proto2_extension_json.t.
- parse_runner_output generalized: every Required.* failure (proto2/proto3/editions)
  is fatal, every Recommended.* is reported — not just proto3.

## CI wired
- .github/workflows/ci.yml: conformance job installs the PREBUILT runner via
  npm protobuf-conformance@34.1.0 (no source/Abseil build), runs run_suite.t as a
  blocking gate, uploads the full log + summary as an artifact, writes a summary to
  the job page. Triggers on any push to any branch + all PRs (incl. forks).
- run_suite.t now fails on ANY required OR recommended failure (the flawless bar).

## State
Suite green: 1357 tests. Goal exit criterion met.
