# Session — API + WKT + docs hardening

- **Branch**: fix/audit-remediation. Covers B-014, B-017, B-019.
- **Model**: claude-opus-4-8.

## Changes
- B-014: parse_with_imports now resolves the returned schema by default (resolve => 0 opt-out),
  so callers get an immediately-usable schema. POD updated.
- B-017: confirmed already-fixed (Duration sign-mismatch throws Protobuf::Exception::JSON::WKT);
  added t/wkt/duration_typed_error.t to lock it.
- B-019: CI now installs develop deps (--with-develop) and runs `prove -lr xt`, so the author
  POD tests actually execute instead of skipping silently. Fixed xt/pod-coverage.t's config bug
  (it used `private => [qr/^new$/]` which REPLACED Pod::Coverage's default ^_ private rule,
  wrongly counting every internal helper); switched to also_private. Then documented the ~29
  genuinely-public-but-naked methods the now-running test surfaced across Codec, JSON, Wire,
  Schema, Class::Codegen, Schema::{Field,File,Message,Enum}.

## Tests
- t/parser/parse_with_imports_resolve.t, t/wkt/duration_typed_error.t. xt now PASSES
  (pod-syntax + pod-coverage). Full suite 1530 green; perlcritic --gentle + podchecker clean.
