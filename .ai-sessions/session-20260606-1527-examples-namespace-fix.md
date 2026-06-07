# Session — Update example scripts for the Protobuf namespace

- **Branch**: patch.
- **Model**: claude-opus-4-8.
- Second of two commits this session (the first fixed the native-parser enum codec bug).

## Change
- `examples/basic/hello.pl` and `examples/temporal/sdk_core_smoke.pl` still loaded
  `Proto3::Parser/Codec/Schema`, dead packages after the Proto3 → Protobuf rename — both
  scripts died at use-time and would have shipped broken in the CPAN tarball.
- Renamed all `Proto3::` references to `Protobuf::`. No logic changes.

## Verification
- `examples/basic/hello.pl` runs end-to-end (wire + JSON round-trip).
- `examples/temporal/sdk_core_smoke.pl` compiles and still guards on `SDK_CORE_PROTO_PATH`.
- `grep -rn 'Proto3::' examples/` is clean.
