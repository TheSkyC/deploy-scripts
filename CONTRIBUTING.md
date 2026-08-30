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

`all` runs independent checks concurrently (defaulting to the CPU count); set
`PARALLEL_JOBS=1` to run serially when debugging a single check.

Useful targets: `syntax`, `shellcheck`, `release`, `dispatch`, `guards`, `help`.

Enable the versioned pre-commit hook once per clone:

```bash
bash tools/install-git-hooks.sh
```

When a staged change touches `lib/`, `apps/`, `impl/`, `dist/`, or
`tools/build-release.sh`, the hook runs `tools/verify.sh release`. It rebuilds
`dist/` but never stages generated files; review and stage any resulting release
updates before retrying the commit. Use `bash tools/install-git-hooks.sh --check`
to confirm the setup.
`all` rebuilds `dist/` deterministically, so a change to `lib/`, `apps/`, or an
`impl/` script requires committing the regenerated release scripts too. New
`check_*` functions belong in a `tools/checks/` module and must be registered in
a target arm (for example `guards`) and in the `all` list;
`check_target_groups_cover_all_checks` fails otherwise.

## Commit messages

Use conventional commits, e.g. `fix(scope): subject` / `feat(scope): subject`,
with a concise imperative subject and a body when the change is user-facing or
complex. Commit `dist/` together with the source changes that produce it.
## Publishing a release

Releases are tag-driven. The repository includes a guarded local publisher and a
GitHub Actions workflow:

```bash
bash tools/publish-release.sh v0.1.0
```

The publisher requires a clean working tree, runs `tools/verify.sh release`,
creates an annotated tag, and pushes it to `origin`. Pushing a SemVer tag such
as `v0.1.0` triggers `.github/workflows/release.yml`, which checks out the exact
tagged commit, rebuilds and verifies `dist/`, creates a source archive and
SHA256 file, and creates or updates the GitHub Release idempotently.

To wait for the remote workflow to finish:

```bash
bash tools/publish-release.sh --wait v0.1.0
```

Existing tags are never overwritten implicitly. To intentionally replace one:

```bash
bash tools/publish-release.sh --replace-existing --wait v0.1.0
```

`--allow-dirty` exists for emergency use but is not recommended: uncommitted
files are not included in the tag or GitHub Release. The workflow publishes a
normal non-draft release by default. Repository variables `RELEASE_DRAFT=true`
and `RELEASE_PRERELEASE=true` can opt into draft or prerelease behavior.
