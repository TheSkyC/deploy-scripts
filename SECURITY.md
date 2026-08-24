# Security Policy

## Supported versions

Only the latest commit on `master` receives security fixes. The framework
self-update flow (`deploy.sh self-update`) deploys verified release archives;
keep a managed installation current to receive them.

## Reporting a vulnerability

Open a private security advisory via GitHub (Security → Advisories) instead of
a public issue. Include the affected app or framework component, the action
(`install`/`update`/`backup`/`restore`/`uninstall`), and reproduction steps.

Please do not report the following as vulnerabilities; they are documented
deployment characteristics:

- Deployment configs are stored root-owned with mode 600 in plaintext
  (`/etc/<app>-deploy.conf`, systemd environment files). Root is the trust
  boundary; anything root can read is considered non-secret to the host.
- Status JSON redacts secret-looking substrings from operation summaries, but
  the operation log files themselves are root-only (mode 640 under
  `/var/log/deploy-scripts`).

## Design invariants relevant to security review

- Config trust gate: saved-config values that influence status projections are
  only honored when the config file is `root:600`/`root:400`
  (`app_conf_trusted_value`).
- Path safety: all install/data/backup paths pass `is_safe_path`; deletion
  helpers refuse top-level and system directories.
- Atomic writes: binaries, configs, nginx sites, and release archives are
  staged then renamed, never written in place.
- Locking: per-app (fd 9), manager batch (fd 8), and self-update (fd 7) locks
  prevent concurrent mutations.
- Downloads: GitHub archives and toolchains are checksum-verified before use.

## Verification

`bash tools/verify.sh all` runs the full guard suite (~330 checks), including
structural checks for atomic writes, path guards, and config trust gates. CI
runs it on every push.
