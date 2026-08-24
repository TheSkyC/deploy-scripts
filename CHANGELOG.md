# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for the framework release archives produced by `tools/build-release.sh`.

## [Unreleased]

### Fixed

- `status-json` backup projection: newapi now applies the same config trust
  gate as every other app (root-owned, mode 600/400) before honoring a
  `BACKUP_DIR` override from the saved deployment config; binary-app
  projections surface an untrusted config explicitly instead of silently
  ignoring it.
- cpa-stack merged version fields collapse to JSON `null` when both components
  are unknown, restoring the documented legacy `"version":null` contract that
  a literal `"null/null"` string broke for automation consumers.
- CyberStrikeAI update reports an explicit warning when the post-restart health
  check fails, instead of printing only "Update complete" while the service is
  unhealthy.
- Operation-record JSON escaping now covers backslash, quote, and every C0
  control character; step names or error summaries containing control bytes no
  longer produce invalid JSON in operation state and history files.

### Added

- Backup integrity metadata: every binary-app and blog backup now publishes a
  `.sha256` sidecar and a single-line `manifest.json` (schema version, app,
  archive name, sha256, creation time, installed version) next to the archive,
  written atomically after the archive lands. Metadata write failures warn
  without failing the backup itself.
- New per-app `verify` action: recomputes the newest archive's checksum
  against its sidecar/manifest and reports verified / failed / unverified.
  Supported on all 16 apps (shared-lifecycle apps delegate to `bapp_verify`;
  custom-backup apps delegate to the shared verdict renderer with their own
  archive globs).
- Shared restore lifecycle for binary-app data directories (`bapp_restore`):
  picks the newest backup (or `<APP>_RESTORE_ARCHIVE` path inside the trusted
  backup dir), verifies its checksum, rejects unsafe tar members (absolute
  paths, `..`, backslashes), stops the service before swapping `DATA_DIR`
  atomically, restarts, and rolls the previous data back if the service cannot
  start on restored data. All nine shared-lifecycle apps expose it via
  `do_restore`.
- `status-json` backup projection gains an `integrity` field
  (`verified|failed|unverified`) computed from the newest archive's metadata.
- Opt-in strict port-conflict preflight: set `DEPLOY_FAIL_ON_PORT_CONFLICT=1`
  (or pass strict mode to `app_check_port_conflict`) so an occupied port aborts
  before downloads and service changes rather than failing at
  `systemctl start` with heavyweight rollback. Default warn-only behavior is
  unchanged.
- Opt-in China mirrors: CyberStrikeAI's PyPI/Go proxy defaults are the official
  upstreams (`pypi.org`, `proxy.golang.org`); set `DEPLOY_CN_MIRROR=1` to use
  the Tsinghua/goproxy.cn endpoints. Explicit env and saved-config values keep
  precedence.
- Registry capability column: `DEPLOY_APP_SPECS` entries declare capabilities
  (`backup`, `restore`), exposed via `deploy_app_has_capability`; batch backup
  planning reads the registry instead of loading implementations and grepping
  source.
- Community files: MIT LICENSE and SECURITY.md (supported versions, private
  advisory reporting, security-relevant design invariants).

### Changed

- Shared JSON escaper core in `lib/operation.sh`; `app_json_string` and
  `operation_json_escape` delegate to one implementation so status JSON and
  operation records can never disagree about escaping.
- Removed dead explicit `release_lock` calls at the end of mutating actions;
  locks are released by the exit handler registered in `acquire_lock`. The fd
  7/8/9 lock levels and release discipline are now documented in `lib/lock.sh`.
- Design doc `docs/central-status-and-self-update-design.md` marked as
  implemented; the state center, operation records, batch update/backup, and
  self-update flows it proposed have shipped.
- New guard checks: `check_state_backup_config_trust_gate`,
  `check_operation_json_escape_matches_app_json_string`,
  `check_port_conflict_strict_mode_aborts`,
  `check_cyberstrikeai_mirrors_are_opt_in`,
  `check_no_explicit_release_lock_calls`,
  `check_app_registry_capabilities`.
