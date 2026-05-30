# Lessons Learned

## Recent
<!-- 10 most recent lessons, newest first -->
- This dev box has core Perl 5.38 + `prove` + `just` only — no `Test2::Suite`, `perlcritic`, `dzil`, or `cpanm`. Smoke/unit tests must run on core `Test::More` to be verifiable offline; treat the plan's `Test2::V1` preamble as CI-only or gate it behind availability (2026-05-30)
- When converting a TDD-depth spec to a plan, map each spec `T-` test ID onto exactly one RED sub-step so coverage is traceable to the spec, not invented (2026-05-30)
- Layer a protobuf-library plan strictly bottom-up (Wire → Schema → Resolver → Codec → Parser → Class → JSON/WKT → Conformance → Codegen) so every step stands on a tested foundation with no forward references (2026-05-30)
- Defer protoc differential/oracle tests to the step where the test graph can actually be built two independent ways (e.g. resolver-vs-protoc only after both parser and DescriptorSet exist), and make them `skip_all` when protoc is absent so offline `prove` still works (2026-05-30)
- When a command says "read the reference file," read it once and reuse it from context — re-issuing the same Read in later parallel batches returns "Wasted call" (2026-05-30)
- For `/bpe:session-summary` setup, one combined bash call (mkdir + date + existence checks) and a single `date` for the timestamp is enough — don't duplicate them across a parallel block (2026-05-30)

## Workflow
- Check for existing `plan.md`/`todo.md` before writing, and don't overwrite pre-existing `LICENSE`/`README.md` — treat an existing README as a stub to flesh out in the release step (2026-05-30)
- Raise soft ordering dependencies (e.g. maps needing embedded-message encoding from a later step) with an inline plan note + a `<CLAUDE_HELP>` flag rather than silently reordering (2026-05-30)

## Proto3 / Protobuf
- The resolver (type-name scoping) is the single component GPB::Dynamic gets wrong; front-load its unit scoping tests early and prove correctness with a protoc differential later — this is the project's core credibility bar alongside the Google conformance suite (2026-05-30)
