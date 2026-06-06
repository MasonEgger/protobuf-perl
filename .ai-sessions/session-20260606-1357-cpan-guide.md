# Session — Add cpan.md publishing guide

- **Branch**: v1.
- Wrote cpan.md: step-by-step for publishing the Protobuf dist to CPAN.
- Covers: the reserved-namespace gotcha (Protobuf held by CJCOLLIER, no code) and
  how to get it released via the holder then modules@perl.org; PAUSE account;
  ~/.pause creds; pre-release tidy (version, Changes {{NEXT}}, optional PruneFiles
  for dev docs); the dzil release pipeline ([@Starter::Git] wires
  TestRelease/ConfirmRelease/UploadToCPAN/Git::Tag+Push); post-release steps; a
  checklist.
- Facts verified against dist.ini, the installed Starter bundle source, and spec.md.
