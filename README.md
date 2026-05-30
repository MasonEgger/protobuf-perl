# Proto3

A pure-Perl implementation of Protocol Buffers version 3 (proto3): wire codec,
schema model, `.proto` parser, JSON mapping, well-known types, and
ahead-of-time class generation.

> **Status: pre-alpha.** The public API is not yet stable and the build is
> incomplete. This README is a placeholder.

## Specification

The authoritative design lives in [`spec.md`](spec.md) at the repository root.
The TDD roadmap is tracked in [`plan.md`](plan.md) and [`todo.md`](todo.md).

## Development

Common tasks run through [`just`](https://github.com/casey/just):

```sh
just check   # lint + test (the gate every step ends on)
just test    # prove -lr t
just lint    # perlcritic --gentle lib t
```

## License

MIT. See [`LICENSE`](LICENSE).
