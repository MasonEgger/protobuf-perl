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

## Ahead-of-time code generation

[`bin/proto3-gen-perl`](bin/proto3-gen-perl) reads `.proto` files and emits one
Perl `.pm` per file — compiled, statically-discoverable message classes for
projects that want faster startup, IDE autocompletion, and no runtime
parse-failure surprises (spec §4.12).

```sh
proto3-gen-perl \
    --include /path/to/protos \
    --output  /path/to/lib \
    --package-prefix T::Api \
    temporal/api/common/v1/message.proto
# Writes /path/to/lib/T/Api/Common/V1/Message.pm
```

Protobuf packages map to Perl namespaces via `--package-prefix`: each protobuf
path component is PascalCased and the prefix replaces the leading components, so
`temporal.api.common.v1` under `--package-prefix T::Api` becomes
`T::Api::Common::V1`.

The emitted classes share the exact runtime build path of
[`Proto3::Class::Generator`](lib/Proto3/Class/Generator.pm) — there is only one
accessor/codec contract, so AOT and runtime classes cannot drift. Generated
modules carry **no** parser or descriptor-set dependency (only the schema, codec,
and WKT layers), and the output is **deterministic**: regenerating an unchanged
`.proto` is byte-identical.

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
