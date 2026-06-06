# Protobuf

A pure-Perl implementation of Protocol Buffers: a wire codec, a schema model, a
`.proto` parser, the canonical JSON mapping, the well-known types, and an
ahead-of-time class generator — with **zero install-time XS** and no compiler
required.

It implements the whole format, not one dialect: it passes the full Google
Protocol Buffers **conformance suite at protobuf v34** — `proto2`, `proto3`, and
**editions 2023**, both Required and Recommended (`--enforce_recommended`) — with
**zero failures**.

```
CONFORMANCE SUITE PASSED: 2806 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
```

It was built to parse, resolve, and round-trip the Temporal
[sdk-core](https://github.com/temporalio/sdk-core) proto graph correctly,
including the innermost-first cross-file type resolution that trips up some
existing dynamic Perl protobuf libraries.

## Requirements

- **Perl 5.38 or newer** (it uses the `feature 'class'` syntax).
- **No XS, no C compiler, no non-core CPAN modules at runtime.** Everything it
  needs (`Math::BigInt`, `Encode`, `JSON::PP`, `MIME::Base64`, `Scalar::Util`,
  `File::Spec`, …) ships with core Perl.

## Install from the GitHub repo

This isn't on CPAN yet, so install straight from the repository.

### Option A — cpanm from the Git URL (simplest)

[`cpanm`](https://metacpan.org/pod/App::cpanminus) can install directly from a
Git remote:

```sh
cpanm git://github.com/MasonEgger/proto3-perl.git
# or a specific branch/tag:
cpanm git://github.com/MasonEgger/proto3-perl.git@v1
```

This builds the distribution and installs `Protobuf`, the `Protobuf::*` modules, and
the `protobuf-gen-perl` / `protobuf-conformance` scripts into your Perl. Because all
prerequisites are core, there is nothing else to fetch.

### Option B — clone and install

```sh
git clone https://github.com/MasonEgger/proto3-perl.git
cd proto3-perl
cpanm --installdeps .   # a no-op on a complete core Perl, but safe to run
cpanm .                 # build + install the distribution
```

### Option C — clone and run in place (no install)

To use it from a checkout without installing anything, just add `lib/` to the
include path:

```sh
git clone https://github.com/MasonEgger/proto3-perl.git
cd proto3-perl
perl -Ilib -MProtobuf -e 'print "Protobuf $Protobuf::VERSION\n"'
```

In your own code: `use lib '/path/to/proto3-perl/lib';` or run with
`perl -I/path/to/proto3-perl/lib …` / set `PERL5LIB`.

### Pin it in a `cpanfile`

A downstream project can depend on the Git checkout from its own `cpanfile`:

```perl
requires 'Protobuf',
    git => 'https://github.com/MasonEgger/proto3-perl.git',
    ref => 'v1';
```

## Features

- **Full wire codec** — encode/decode every field kind across proto2, proto3,
  and editions: scalars, messages, enums, repeated (packed and expanded), maps,
  oneofs, **groups** (delimited messages), **extensions** and **MessageSet**,
  **required** fields, explicit/implicit/`legacy_required` **presence**, **closed
  vs open enums**, and field **defaults** — with unknown-field preservation.
- **Editions feature model** — each file/message/field resolves a feature set
  (presence, enum openness, repeated/message encoding, UTF-8 validation) from the
  edition defaults plus inherited and explicit overrides.
- **`.proto` parser** — a hand-written lexer + grammar with transitive import
  following and cycle detection.
- **Correct resolver** — fully-qualified type resolution that walks scopes
  outward one level at a time, matching `protoc` byte-for-byte.
- **Canonical JSON** — the proto3 JSON mapping, both directions, with
  deterministic key order, the well-known-type special forms, and the proto2
  extension `[fully.qualified.name]` key form.
- **Well-known types** — `Timestamp`, `Duration`, `Any`, `Struct`/`Value`/
  `ListValue`/`NullValue`, `FieldMask`, `Empty`, and the scalar wrappers.
- **Runtime classes** — generate Perl classes from a schema at runtime, or
  **ahead-of-time** with `protobuf-gen-perl` for faster startup and static
  discoverability.
- **`FileDescriptorSet` support** — load a `protoc`-produced descriptor set
  (including v34 sets with proto2/editions) instead of parsing `.proto` text.

## Quickstart

Parse a `.proto`, resolve it, and round-trip a message on the wire and as JSON:

```perl
use v5.38;
use Protobuf::Parser;
use Protobuf::Codec;

# Parse + resolve a .proto into a single schema.
my $parser = Protobuf::Parser->new( include_paths => ['proto'] );
my $schema = $parser->parse_with_imports('hello.proto');
$schema->resolve;

# A codec is the wire + JSON workhorse, bound to the resolved schema.
my $codec = Protobuf::Codec->new( schema => $schema );

# Message values are plain hashrefs keyed by proto field name.
my %greeting = ( text => 'Hello, world!', priority => 1 );

# Encode to wire bytes and decode them back.
my $bytes   = $codec->encode( 'hello.Greeting', \%greeting );
my $decoded = $codec->decode( 'hello.Greeting', $bytes );

# Canonical JSON, both directions.
my $json = $codec->encode_json( 'hello.Greeting', \%greeting );
my $back = $codec->decode_json( 'hello.Greeting', $json );
```

Prefer working with objects instead of hashrefs? Generate a class from any
message in the resolved schema:

```perl
use Protobuf::Class::Generator;

Protobuf::Class::Generator->build(
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

### Loading a compiled descriptor set

If you already have a `protoc`-produced `FileDescriptorSet` (the
`--descriptor_set_out` format), skip the parser entirely:

```perl
use Protobuf::DescriptorSet;
my $schema = Protobuf::DescriptorSet->load_file('all.fds');   # already resolved
my $codec  = Protobuf::Codec->new( schema => $schema );
```

This is the path the conformance testee uses, and it understands proto2 and
editions descriptor sets, not just proto3.

## Ahead-of-time code generation

[`bin/protobuf-gen-perl`](bin/protobuf-gen-perl) reads `.proto` files and emits one
Perl `.pm` per file — compiled, statically-discoverable message classes for
projects that want faster startup, IDE autocompletion, and no runtime
parse-failure surprises.

```sh
protobuf-gen-perl \
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
[`Protobuf::Class::Generator`](lib/Protobuf/Class/Generator.pm) — there is only one
accessor/codec contract, so AOT and runtime classes cannot drift. Generated
modules carry **no** parser or descriptor-set dependency (only the schema, codec,
and WKT layers), and the output is **deterministic**: regenerating an unchanged
`.proto` is byte-identical.

## Conformance

The library passes the full **protobuf v34** conformance suite — `proto2`,
`proto3`, and **editions 2023**, Required and Recommended — with zero failures.

- The testee binary is [`bin/protobuf-conformance`](bin/protobuf-conformance); all of
  its request-handling logic lives in
  [`Protobuf::Conformance`](lib/Protobuf/Conformance.pm).
- The harness [`t/conformance/run_suite.t`](t/conformance/run_suite.t) unit-tests
  the verdict logic on every run, and drives the real Google
  `conformance_test_runner` against the testee **when one is available** (set
  `CONFORMANCE_TEST_RUNNER`, or put `conformance_test_runner` on `PATH`). It
  skips when no runner is present, so the default test run stays green without
  the external toolchain.
- The runner ships prebuilt via the
  [`protobuf-conformance`](https://www.npmjs.com/package/protobuf-conformance)
  npm package (no source build needed):

  ```sh
  npm install protobuf-conformance@34.1.0
  CONFORMANCE_TEST_RUNNER="$PWD/node_modules/protobuf-conformance/bin/conformance_test_runner-linux-x64" \
      prove -lr t/conformance/run_suite.t
  ```

- **CI** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the suite
  as a blocking gate on every push and pull request: any required **or**
  recommended failure across any syntax fails the build, and the full runner
  output is uploaded as an artifact.

What is **not** in scope: gRPC, the reflection API, the `edition_unstable` test
edition, and proto2/editions `.proto`-source parsing (the conformance path uses
descriptor sets, not the source parser).

## Temporal sdk-core

The Temporal sdk-core proto graph is the project's proof of purpose.
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

## Development

Common tasks run through [`just`](https://github.com/casey/just):

```sh
just check       # lint + test — the everyday gate
just test        # prove -lr t
just lint        # perlcritic --gentle lib t
just check-dist  # check + the full Dist::Zilla build (needs the dzil toolchain)
```

Author-only POD tests live under `xt/` and require `Test::Pod` and
`Test::Pod::Coverage`; they `skip_all` cleanly when those are not installed:

```sh
prove -lr xt
```

The authoritative design lives in [`spec.md`](spec.md); the original TDD roadmap
is in [`plan.md`](plan.md) / [`todo.md`](todo.md), and the full-conformance plan
is in [`V34-PLAN.md`](V34-PLAN.md).

## License

MIT. See [`LICENSE`](LICENSE).
