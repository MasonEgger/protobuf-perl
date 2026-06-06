# Session — CI fix: dzil authordeps

- **Branch**: v1, PR #1.
- After the perlcritic fix, `just check` still failed in CI on the dzil leg:
  `dzil test` errored because the [@Starter::Git] author plugins weren't installed
  (CI had Dist::Zilla but not its authordeps).
- Fix: added `dzil authordeps --missing | cpanm --notest` to the CI dependency step.
- perlcritic + prove already pass in CI; conformance gate green. This is the last
  known CI gap. Pushing to let CI run dzil for real (local dzil install via cpan was
  unreliable). xt/ POD tests skip when Test::Pod absent and every lib module has POD.
