# Proto3

A pure-Perl implementation of Protocol Buffers version 3 (proto3): a wire codec,
a schema model, a `.proto` parser, the canonical JSON mapping, the well-known
types, and an ahead-of-time class generator — with **zero install-time XS** and
no compiler required.

It was built to parse, resolve, and round-trip the Temporal
[sdk-core](https://github.com/temporalio/sdk-core) proto graph correctly,
including the innermost-first cross-file type resolution that trips up some
existing dynamic Perl protobuf libraries (spec §1).

## Features

- **Wire codec** — encode/decode all proto3 scalar, message, enum, repeated,
  packed, map, and oneof field kinds, with unknown-field preservation.
- **`.proto` parser** — a hand-written lexer + grammar for proto3 syntax, with
  transitive import following and cycle detection.
- **Correct resolver** — fully-qualified type resolution that walks scopes
  outward one level at a time, matching `protoc` byte-for-byte (spec §4.3).
- **Canonical JSON** — the proto3 JSON mapping, both directions, with
  deterministic key order.
- **Well-known types** — `Timestamp`, `Duration`, `Any`, `Struct`/`Value`/
  `ListValue`/`NullValue`, `FieldMask`, `Empty`, and the scalar wrappers.
- **Runtime classes** — generate Perl classes from a schema at runtime, or
- **ahead-of-time** with `proto3-gen-perl` for faster startup and static
  discoverability.
- **`FileDescriptorSet` support** — load a `protoc`-produced descriptor set
  instead of parsing `.proto` text.

## Install

This is a Dist::Zilla distribution. From a checkout:

```sh
cpanm --installdeps .   # install prerequisites (all core in modern Perl)
dzil install            # or: dzil test, dzil build
```

Proto3 requires Perl 5.38 or newer (it uses the `class` feature). It depends
only on modules that ship with core Perl — no XS, no compiler.

## Quickstart

Parse a `.proto`, resolve it, and round-trip a message on the wire and as JSON:

```perl
use v5.38;
use Proto3::Parser;
use Proto3::Codec;

# Parse + resolve a .proto into a single schema.
my $parser = Proto3::Parser->new( include_paths => ['proto'] );
my $schema = $parser->parse_with_imports('hello.proto');
$schema->resolve;

# A codec is the wire + JSON workhorse, bound to the resolved schema.
my $codec = Proto3::Codec->new( schema => $schema );

# Message values are plain hashrefs keyed by proto field name.
my %greeting = ( text => 'Hello, world!', priority => 1 );

# Encode to wire bytes and decode them back.
my $bytes   = $codec->encode( 'hello.Greeting', \%greeting );
my $decoded = $codec->decode( 'hello.Greeting', $bytes );

# Canonical proto3 JSON, both directions.
my $json = $codec->encode_json( 'hello.Greeting', \%greeting );
my $back = $codec->decode_json( 'hello.Greeting', $json );
```

Prefer working with objects instead of hashrefs? Generate a class from any
message in the resolved schema:

```perl
use Proto3::Class::Generator;

Proto3::Class::Generator->build(
    schema         => $schema,
    message        => $schema->message('hello.Greeting'),
    target_package => 'Hello::Greeting',
);

my $msg = Hello::Greeting->new({ text => 'Hi', priority => 1 });
my $wire = $msg->encode;
my $obj  = Hello::Greeting->decode($wire);   # a Hello::Greeting instance
```

A complete, runnable version lives in [`examples/basic/`](examples/basic/):

```sh
perl -Ilib examples/basic/hello.pl
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

## Temporal sdk-core

The Temporal sdk-core proto graph is the project's proof of purpose (spec §5.2).
[`examples/temporal/sdk_core_smoke.pl`](examples/temporal/sdk_core_smoke.pl)
parses, resolves, and round-trips the `WorkflowActivation` and
`StartWorkflowExecutionRequest` entry points. The sdk-core protos are large and
not vendored here, so the smoke is **guarded**: point `SDK_CORE_PROTO_PATH` at a
checkout's proto include root to run it.

```sh
SDK_CORE_PROTO_PATH=/path/to/sdk-core/protos \
    perl -Ilib examples/temporal/sdk_core_smoke.pl
```

The same smoke runs as an integration test in
[`t/integration/sdk_core.t`](t/integration/sdk_core.t), which `skip_all`s when
`SDK_CORE_PROTO_PATH` is unset.

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

> **Conformance status.** The conformance runner is not installed in the default
> dev environment, so the live suite has not been run locally — only the
> skip-aware harness and the CI wiring are in place here. The required-proto3 bar
> is enforced in CI.

## Development

Common tasks run through [`just`](https://github.com/casey/just):

```sh
just check   # lint + test (the gate every step ends on)
just test    # prove -lr t
just lint    # perlcritic --gentle lib t
```

Author-only POD tests live under `xt/` and require `Test::Pod` and
`Test::Pod::Coverage`; they `skip_all` cleanly when those are not installed:

```sh
prove -lr xt
```

The authoritative design lives in [`spec.md`](spec.md); the TDD roadmap is in
[`plan.md`](plan.md) and [`todo.md`](todo.md).

## License

MIT. See [`LICENSE`](LICENSE).
