# Session — Conformance run: stdio flush + string UTF-8 fixes

- **Timestamp**: 2026-06-03 20:35
- **Branch**: v1

## Focus

Built and ran the real Google conformance_test_runner (libprotoc 3.21.12,
compiled from protobuf v21.12 source) against bin/proto3-conformance for the
first time. The run exposed two genuine bugs that no in-process test caught,
both fixed here with regression tests.

## Fixed

- **stdio deadlock** (`lib/Proto3/Conformance.pm`): `run_stdio` never flushed the
  output handle, so each framed response sat in Perl's block buffer on the pipe;
  the runner blocked forever waiting for it. Fix: autoflush the output handle via
  the `select`/`$|` idiom (no IO::Handle dependency). Regression test in
  `t/conformance/testee.t` drives the real binary over pipes with an alarm —
  deadlocks (times out) without the flush.
- **string UTF-8 encoding** (`lib/Proto3/Codec.pm`): proto3 `string` fields must
  be UTF-8 octets on the wire, but the codec emitted raw Perl codepoints
  ("café" -> `... e9`, length 4) instead of UTF-8 (`... c3 a9`, length 5),
  producing invalid wire data libprotobuf rejected and "Wide character in print"
  warnings that corrupted the byte framing. Split the shared LEN closure: `string`
  now encodes/decodes via Encode UTF-8; `bytes` stays raw octets (downgraded).
  New `t/codec/string_utf8.t` covers string-as-UTF-8, bytes-as-raw, ASCII.

## Conformance result (first real run)

`CONFORMANCE SUITE FAILED: 1307 successes, 0 skipped, 0 expected failures,
422 unexpected failures.` Of the 422, ~509 of the suite total are proto2
(explicit non-goal, spec §1) — the real proto3 to-do is ~126 Required failures
(116 JSON-heavy, ~10 protobuf-input, 4 WKT bounds). Decision: pursue 100% proto3
compliance, ignore proto2 entirely.

## State

- Full suite green: 996 tests, Result: PASS.
- conformance_test_runner built at
  /tmp/protobuf-build/protobuf-3.21.12/cmake-build/conformance_test_runner
  (CMake target needed conformance_test_main.cc + text_format_conformance_suite.cc
  added — a known 21.12 packaging gap).
- Authoritative failure list: failing_tests.txt (422 lines; 126 proto3).

## Next

Wire the real runner into t/conformance/run_suite.t (skip-aware), then drive down
the 126 proto3 Required failures TDD-style: JSON Any/Value/number edges first
(largest bucket), then protobuf-input validation, then WKT range checks.
