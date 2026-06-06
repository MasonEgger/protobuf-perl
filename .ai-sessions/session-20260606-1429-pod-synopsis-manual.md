# Session — Add SYNOPSIS sections and Protobuf::Manual

- **Branch**: v1.
- Added a `=head1 SYNOPSIS` to the 10 public modules that lacked one:
  Protobuf, Schema::{Enum,Field,Message,File,Oneof,Service,Util},
  WKT::Util, Class::Accessor. Each example is accurate to the actual
  `:param`/accessor surface; the top-level Protobuf SYNOPSIS shows a
  verified parse→resolve→codec→JSON round-trip and points at the Manual.
- New `lib/Protobuf/Manual.pod`: task-oriented cookbook — data model,
  three ways to get a schema, wire + JSON codec, well-known types,
  generated classes (runtime + AOT), the proto2/proto3/editions feature
  model, error handling, conformance. Renders on metacpan as
  Protobuf::Manual (POD-only, no code).
- Every inline example was executed and verified before being written.
- Validated: podchecker clean on all touched POD; `just check` (lint +
  1357 tests) PASS; `just check-dist` (dzil build + xt pod-syntax/compile)
  PASS — Manual.pod is gathered into the dist and passes pod-syntax.

## Out-of-scope findings (NOT fixed — flagged for Mason)
1. `examples/basic/hello.pl` and `examples/temporal/sdk_core_smoke.pl`
   still `use Proto3::*` (Parser/Codec/Schema) — missed in the rename;
   they will not run. Trivial s/Proto3::/Protobuf::/.
2. Native `.proto` parser tags enum-typed fields as `type => 'message'`
   and the resolver only fills `type_ref` (an Enum) without correcting
   `type`. So Codec's `is_message` branch sends them down the embedded-
   message path → "unknown message type". Enums therefore work only via
   the protoc/DescriptorSet path (type='enum'), which is what conformance
   and t/descriptor/load.t exercise. Latent bug in the Parser→Codec path.
