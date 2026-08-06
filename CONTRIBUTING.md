# Contributing

Thanks for helping with the deploy scripts. This repository is a set of
self-contained Bash deploy/install scripts for several services, with a shared
`lib/` framework, per-app `apps/` + `impl/install_<app>.sh` pairs, and a
verification suite under `tools/verify.sh`.

## Getting started

- Read `README.md` first: it documents the layout, the shared-library
  conventions, the "Adding A New App" checklist, and the release build flow.
- Make focused changes that follow the existing architecture and naming.
  Prefer the shared `lib/` helpers over copying per-app bodies, and keep
  app-specific localization in `apps/<app>.sh`.

## Localization

User-facing strings are translated through `i18n_register` in `apps/<app>.sh`
and referenced with `t key`. Keep the two registered translations (EN/ZH) in
sync; `check_i18n_keys_are_consistent` enforces registration/reference parity.

## Verification

Run the full suite before submitting:

```bash
bash tools/verify.sh all
```

Useful targets: `syntax`, `shellcheck`, `release`, `dispatch`, `guards`, `help`.
`all` rebuilds `dist/` deterministically, so a change to `lib/`, `apps/`, or an
`impl/` script requires committing the regenerated release scripts too. New
`check_*` functions belong in a `tools/checks/` module and must be registered in
a target arm (for example `guards`) and in the `all` list;
`check_target_groups_cover_all_checks` fails otherwise.

## Commit messages

Use conventional commits, e.g. `fix(scope): subject` / `feat(scope): subject`,
with a concise imperative subject and a body when the change is user-facing or
complex. Commit `dist/` together with the source changes that produce it.
