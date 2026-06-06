# Session — Fix dzil build/test; make dist gate blocking

- **Branch**: v1, PR #1.
- Installed dzil 6.037 + Starter::Git bundle locally (cpanm/apt) to fix with real output.
- Fixed the dzil collisions/errors that `dzil test` surfaced (first real run):
  1. LICENSE "added multiple times" — dist.ini `regenerate = LICENSE` (Starter bundle
     option: excludes committed LICENSE from gather, plugin-generated one is authoritative,
     copies back on release). (cpanfile collision already handled by removing [CPANFile].)
  2. POD "Non-ASCII before =encoding" across 38 files (em-dashes/é) — added
     `=encoding utf-8` before the first =head1 in every lib .pm + bin script.
  3. Features.pm `=item 2023` numeric-item POD error — wrapped editions items in C<>.
  4. Wire.pm `C<pack 'Q<'>` — the `Q<` parsed as a POD code; reworded to avoid it.
  5. Codegen.pm `L<bin/protobuf-gen-perl|/...>` unescaped `/` link — plain C<>.
- CI: Dist build step is now BLOCKING (was continue-on-error); runs `just check-dist`
  (lint + test + dzil build + author pod/compile tests).
- .gitignore: ignore /Protobuf-*/ dist build dir.
- Verified: just check-dist PASS ("all's well"), suite 1357 green, conformance 2806/0.
