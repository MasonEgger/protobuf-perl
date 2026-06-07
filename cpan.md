# Publishing `Protobuf` to CPAN

This is a step-by-step guide for what **you** (Mason) need to do to publish this
distribution to CPAN. It is written for the current state of the repo: the
distribution is named `Protobuf`, it builds cleanly with Dist::Zilla, and the
`Protobuf` namespace on CPAN is **reserved by another author** — so there is a
one-time permission step before the first upload.

> TL;DR: (1) get a PAUSE account, (2) get the `Protobuf` namespace released to
> you by the PAUSE admins, (3) `dzil release`. Steps 1–2 are people/process;
> step 3 is one command.

---

## 0. The one non-obvious thing: the namespace is reserved

`Protobuf` on CPAN is a **namespace reservation** held by **CJCOLLIER**
(registered 2025-12, no code — just a placeholder). PAUSE will not let you
upload `Protobuf` until you have permission on that name. This is the only thing
standing between "works on GitHub" and "on CPAN", and it is resolved by a short,
polite email to the PAUSE admins — not a legal process.

You do **not** need this to keep using the library from GitHub. It is only
required to publish to CPAN.

---

## 1. Get a PAUSE account (once, ~1–2 days)

PAUSE (the Perl Authors Upload Server) is the gateway to CPAN.

1. Register at <https://pause.perl.org/pause/query?ACTION=request_id>.
2. Pick a PAUSE ID (your author handle — e.g. `MEGGER`). It becomes part of
   your CPAN URLs forever, so choose deliberately.
3. A human approves it, usually within a day or two.

Once approved you have an author directory like
`https://cpan.org/authors/id/M/ME/MEGGER/`.

---

## 2. Get the `Protobuf` namespace (the gatekeeping step)

Because `Protobuf` is reserved by someone else, you need permission before the
first upload. There are two paths; do them in this order.

### 2a. Ask the current holder (courtesy first)

Email CJCOLLIER (the reservation holder) explaining that you have a complete,
working, conformance-passing implementation and would like to take over or
co-maintain the `Protobuf` namespace. Reservation holders frequently grant this
when someone actually ships code. Keep it short and factual; link the repo and
the CI showing full v34 conformance.

### 2b. If no response, ask the PAUSE admins

The PAUSE admins (the `modules` list, **modules@perl.org**) can reassign a
**dormant reservation** to a real implementation. Their documented policy is
that a name reservation does not block a working module indefinitely. Write to
modules@perl.org with:

- The namespace: `Protobuf` (and note you'll own `Protobuf::*` under it).
- That it is currently a bare reservation by CJCOLLIER with **no released code**.
- That you have a complete implementation: link
  <https://github.com/MasonEgger/protobuf-perl>, point at the green CI, and note
  it passes the Google protobuf **v34 conformance suite** (proto2 + proto3 +
  editions, required and recommended, zero failures).
- That you attempted to contact the holder first (2a).

Admins are volunteers; give it a week or two. The outcome is they either grant
you primary (`m`) permission on `Protobuf` or set up co-maintainership.

> You can verify your permissions any time at
> <https://pause.perl.org/pause/authenquery?ACTION=peek_perms> — search for
> `Protobuf`. You need at least "first-come" or an explicit grant on the
> top-level `Protobuf` package before uploading.

### What about the sub-modules?

`Protobuf::*` (Codec, Wire, Schema, …) are **not** separately reserved — owning
or being granted `Protobuf` covers uploading the whole tree. No per-module
requests needed.

---

## 3. Configure the upload credentials (once)

Dist::Zilla uploads via your PAUSE login. Put your credentials in
`~/.pause` (chmod 600):

```
user     MEGGER
password your-pause-password
```

(`~/.pause` is the standard file `[UploadToCPAN]` reads. Never commit it.)

---

## 4. One-time pre-release tidy of the repo

A couple of things in the repo today are GitHub-development conveniences that
should be reconsidered before a CPAN release. None are blockers, but decide on
each:

- **`version = 0.1.0` in `dist.ini`.** Fine for a first release. The
  `[@Starter::Git]` bundle's `RewriteVersion`/`BumpVersionAfterRelease` will
  manage it after the first `dzil release`.
- **The `Changes` file** has a `{{$NEXT}}` placeholder block — the bundle's
  `NextRelease` plugin turns that into a dated `0.1.0` heading at release time.
  Make sure the bullet list under it reads the way you want the changelog to
  read, because it becomes permanent.
- **Development docs** (`spec.md`, `plan.md`, `todo.md`, `V34-PLAN.md`,
  `cpan.md`, `.ai-sessions/`) ship inside the tarball by default. That's
  harmless but noisy. If you want a leaner dist, add a `[PruneFiles]` stanza to
  `dist.ini`, e.g.:

  ```ini
  [PruneFiles]
  filename = spec.md
  filename = plan.md
  filename = todo.md
  filename = V34-PLAN.md
  filename = cpan.md
  match    = ^\.ai-sessions/
  ```

  (Optional — purely cosmetic for the tarball.)
- **Vendored conformance data** under `share/proto/` (the `.fds` and test
  `.proto` files) ships too. That's intended — the conformance testee needs the
  FDS at runtime via `File::ShareDir`. Leave it.

---

## 5. Release with Dist::Zilla

The `[@Starter::Git]` bundle already wires the full release pipeline:
`Git::Check` (clean working tree) → `TestRelease` (build + run the test suite in
a clean tree) → `ConfirmRelease` (interactive y/n) → `UploadToCPAN` →
`Git::Commit` + `Git::Tag` + `Git::Push` (tags the release and pushes).

### Prerequisites on your machine

```sh
# Dist::Zilla + this dist's author plugins (one time):
cpanm Dist::Zilla
dzil authordeps --missing | cpanm
```

### Dry run first (uploads nothing)

```sh
dzil build           # produces Protobuf-0.1.0.tar.gz; inspect it
dzil test            # runs the full suite + author (xt) tests in a clean build
```

Optionally inspect the tarball contents:

```sh
tar tzf Protobuf-0.1.0.tar.gz
```

### The actual release

```sh
dzil release
```

This will: re-run the tests, ask you to confirm, upload `Protobuf-0.1.0.tar.gz`
to PAUSE, then commit the changelog, create a `v0.1.0` git tag, and push. Within
an hour or so PAUSE indexes it and it appears on
<https://metacpan.org/dist/Protobuf>.

> If you'd rather not let dzil touch git/upload automatically, you can
> `dzil build` and upload the tarball manually via
> <https://pause.perl.org/pause/authenquery?ACTION=add_uri>, then tag/push by
> hand. `dzil release` just automates that.

---

## 6. After the first release

- `metacpan.org/dist/Protobuf` and `metacpan.org/pod/Protobuf` go live; the POD
  you see in CI's pod-syntax check is what renders there.
- `cpanm Protobuf` now works for everyone — you can simplify the README's
  install section from "install from GitHub" to a plain `cpanm Protobuf` (keep a
  GitHub-install note for the bleeding edge if you like).
- Subsequent releases are just `dzil release` again; the version auto-bumps.

---

## Checklist

- [ ] PAUSE account approved (step 1)
- [ ] Contacted CJCOLLIER about the `Protobuf` reservation (step 2a)
- [ ] If needed, emailed modules@perl.org for the namespace (step 2b)
- [ ] Permission on `Protobuf` confirmed at PAUSE `peek_perms`
- [ ] `~/.pause` credentials in place (step 3)
- [ ] Reviewed `Changes` / version / optional `[PruneFiles]` (step 4)
- [ ] `dzil build` + `dzil test` clean locally (step 5)
- [ ] `dzil release`
- [ ] Verified on metacpan.org and `cpanm Protobuf` (step 6)
