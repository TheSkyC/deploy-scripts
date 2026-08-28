# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for the framework release archives produced by `tools/build-release.sh`.

## [Unreleased]

### Added

- Notifications: ntfy / Gotify backends configured via `deploy.sh
  notify-config` (root:600 trust-gated config, `--test` probe), fail-open
  delivery that can never block an operation, credential redaction before
  messages leave the host, batch summaries for `update-all`/`backup-all`,
  and per-app outcome notifications for install/update/backup/restore/
  uninstall.
- Scheduled batches: `deploy.sh schedule` installs a systemd timer (or
  validated cron.d entry) for `update-all` or `check-only` modes with
  `--at`/`--include`/`--retries` (exponential backoff); the runner re-enters
  `deploy.sh schedule-run` so scheduled runs share the manager lock and the
  notification path; `unschedule` removes timer, cron file, and config.
- Machine migration: `deploy.sh export` bundles app/notification/schedule
  configs plus a backup inventory into a sha256-stamped tarball (`--redact`
  adds a sanitized reference copy); `import` verifies the sidecar and
  installs configs atomically at mode 600.
- Shared Docker Compose layer: `lib/compose.sh` resolves both `docker
  compose` and `docker-compose`, validates project paths, and provides
  `compose_run`/`compose_try`/`compose_up`/`compose_down`/`compose_ps`/
  `compose_health` (fail-closed ps-json health scan); TickFlow delegates its
  probes and unit template to it.
- Fleet management: `deploy.sh fleet [status-all|update-all|backup-all]`
  runs batches across an SSH host inventory with per-host timeouts, bounded
  concurrency, failure isolation, merged JSON results, and a machine-level
  JSONL operation history; the inventory format has no credential surface.
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

### Fixed

- `notify-config --test` now probes the merged in-memory values through a
  staged private config file instead of silently re-reading the stale
  on-disk config; a disabled backend or unreachable URL fails loudly
  (via `NOTIFY_STRICT`) rather than claiming "test delivered", and a
  successful probe persists the merged config so what was tested is
  exactly what later runs use.
- Schedule default calendar for `check-only` mode changed from the
  systemd-only `Mon..Fri *-*-* 09:00` form to a plain `HH:MM` that the
  `/etc/cron.d` fallback can convert, so non-systemd hosts get a working
  schedule instead of an apply-time rejection.
- `operation_run_app_action`'s per-app notification hook now guards on
  `declare -F notify_send`, so isolated/embedded sources of
  `lib/operation.sh` skip the hook instead of hitting `command not found`.
- `deploy.sh schedule` rejects out-of-range `HH:MM` values (e.g. `25:99`)
  before writing the config, validates OnCalendar specs with
  `systemd-analyze calendar` where available, and no longer wraps
  `schedule_apply` failures in a misleading config-write error.
- `deploy.sh import` scans archive members with `tar -tzf` and refuses
  absolute paths, `..`, and backslashes before any byte lands on disk;
  the sha256 sidecar proves integrity but not safety.
- Schedule and fleet configs now use the same root:600/400 trust gate as
  app and notification configs; untrusted files are ignored entirely and
  callers tolerate the refusal.
- Fleet remote records that are not parseable JSON are wrapped as
  `{"error": ...}` instead of corrupting the merged summary.
- Guard fixes: the migration traversal test runs `migrate_main import` in
  a subshell so its `error()` exit cannot kill the whole test process
  (the guard previously never passed), and the registry capabilities
  check now asserts newapi declares `restore` instead of the stale
  pre-D5 negation.
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
