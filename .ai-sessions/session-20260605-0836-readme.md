# Session — README update for full-conformance scope + GitHub install

- **Branch**: v1, PR #1.
- Rewrote README.md to reflect reality:
  - Library is full protobuf (proto2 + proto3 + editions), passes v34 conformance
    flawlessly — not "proto3 only / not run locally" as the old README said.
  - Added a "Requirements" section (Perl 5.38+, zero non-core deps).
  - Added "Install from the GitHub repo" with four options: cpanm git URL, clone+
    install, clone+run-in-place (-Ilib), and pinning in a downstream cpanfile.
    (No CPAN publish yet, per user.)
  - Updated Features (groups, extensions, presence, editions, closed enums).
  - Replaced the stale "conformance status: not run locally" caveat with the
    real passing result + the prebuilt npm-runner instructions.
  - Documented just check / check-dist split and V34-PLAN.md.
- Verified locally: Proto3 loads (-Ilib), just recipes exist, runner path + example
  files exist. (cpanm-from-git not locally testable — no cpanm installed.)
