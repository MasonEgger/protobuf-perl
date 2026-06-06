# Session — Rename Proto3 -> Protobuf

- **Branch**: v1, PR #1.
- Renamed the distribution + namespace from Proto3 to Protobuf (decision: name
  should reflect full proto2/proto3/editions support; Protobuf is CPAN
  namespace-reserved by another author but Mason will file a takeover with a
  real implementation).
- Mechanics:
  - git mv lib/Proto3.pm -> lib/Protobuf.pm, lib/Proto3/ -> lib/Protobuf/,
    t/lib/Proto3Test -> t/lib/ProtobufTest, bin/proto3-* -> bin/protobuf-*.
  - Safe transforms: Proto3:: -> Protobuf:: (2120), Proto3Test -> ProtobufTest,
    proto3-conformance/proto3-gen-perl -> protobuf-* in lib/t/bin/.github.
  - package Proto3; -> package Protobuf;; use_ok/VERSION; POD/ABOUTME prose.
  - dist.ini name = Protobuf; README title + examples + install + cpanfile pin;
    Changes new entry.
  - CAREFULLY LEFT untouched: the proto3/proto2 DIALECT terms — syntax="proto3",
    Required.Proto3.*/Recommended.Proto3.*, TestAllTypesProto3,
    protobuf_test_messages.proto3.*, "Proto2, Proto3, editions" prose, and the
    "Proto3 uses four wire types" dialect note. .ai-sessions/ + plan.md/todo.md
    left as historical record. GitHub repo name stays proto3-perl (deferred).
- Verified: no functional Proto3:: left in lib/t/bin/.github; lint clean; 1357
  tests pass; live v34 conformance still 2806/0 flawless.
