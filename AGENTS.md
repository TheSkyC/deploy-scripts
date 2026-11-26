# Agent Guide

- Read `README.md` for supported usage and architecture, then `docs/README.md` to find task-specific references.
- Follow `CONTRIBUTING.md` and the existing `apps/`, `impl/`, `lib/`, and `tools/checks/` patterns when changing code.
- Run the narrowest relevant check; run `bash tools/verify.sh all` for changes affecting shared behavior or release artifacts.
- Treat `dist/` as generated output and rebuild it with the repository tooling when its sources change.
- Local working notes live in `.dev/INDEX.md` when present. `.dev/` is machine-local context, not a repository contract.
