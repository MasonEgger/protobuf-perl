# Session — CI lint fix (perlcritic)

- **Branch**: v1. PR #1 (v1 -> main).
- CI's `just check` was failing on `perlcritic --gentle lib t` (every run, pre-existing).
  Conformance gate + prove both passed; only lint failed.
- Fixed the real smell: 3 `return sort ...` -> assign-then-return (Codec _sorted_map_keys,
  Wrappers full_names).
- Added .perlcriticrc excluding Subroutines::ProhibitExplicitReturnUndef — the 24
  `return undef` sites are intentional scalar-context "absent" returns on lookup/accessor
  methods where a bare `return;` (empty list) would be a subtle bug.
- Installed perlcritic 1.156 locally (~/perl5 via cpan) and verified `perlcritic --gentle
  lib t` exits 0. Suite still green: 1357 tests.
