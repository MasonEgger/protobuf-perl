# Proto3

A pure-Perl implementation of Protocol Buffers version 3 (proto3): wire codec,
schema model, `.proto` parser, JSON mapping, well-known types, and
ahead-of-time class generation.

> **Status: pre-alpha.** The public API is not yet stable and the build is
> incomplete. This README is a placeholder.

## Specification

The authoritative design lives in [`spec.md`](spec.md) at the repository root.
The TDD roadmap is tracked in [`plan.md`](plan.md) and [`todo.md`](todo.md).

## Development

Common tasks run through [`just`](https://github.com/casey/just):

```sh
just check   # lint + test (the gate every step ends on)
just test    # prove -lr t
just lint    # perlcritic --gentle lib t
```

## Conformance

Passing the proto3 subset of [Google's Protocol Buffers Conformance Test
Suite](https://github.com/protocolbuffers/protobuf/tree/main/conformance) is the
credibility bar for this project (spec §4.11).

- The testee binary is [`bin/proto3-conformance`](bin/proto3-conformance); all of
  its request-handling logic lives in
  [`Proto3::Conformance`](lib/Proto3/Conformance.pm).
- The harness [`t/conformance/run_suite.t`](t/conformance/run_suite.t) unit-tests
  the runner-output verdict logic on every run, and drives the real Google
  `conformance_test_runner` against the testee **when one is available** (set the
  `CONFORMANCE_TEST_RUNNER` environment variable, or put `conformance_test_runner`
  on `PATH`). When no runner is present it skips, so `just test` stays green
  without the external toolchain installed.
- **CI** (the `conformance` job in
  [`.github/workflows/ci.yml`](.github/workflows/ci.yml)) builds
  `conformance_test_runner` from the protobuf source and runs the suite as a
  **required** stage: any failing `Required.Proto3.*` test fails the build
  (T-conf-1). Failing `Recommended.Proto3.*` tests are reported but
  non-blocking (T-conf-2/3).

> **Status: not yet certified locally.** The conformance runner is not installed
> in the default dev environment, so the live suite has not been run here — only
> the skip-aware harness and the CI wiring are in place. The required-proto3 bar
> is enforced in CI.

## License

MIT. See [`LICENSE`](LICENSE).
