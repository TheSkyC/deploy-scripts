# Central Commands Reference

The central launcher `deploy.sh` provides batch commands, machine migration,
notification, scheduling, and fleet operations. This page documents every
command's parameters. Per-app commands are documented in `docs/apps.md`.

## Batch commands

### `status-all` / `overview` / `problems` / `health-all`

```text
deploy.sh status-all [--json] [--short] [--strict] [--errors-only]
                     [--only-installed] [--no-probe] [--no-network]
                     [--include id,id,...] [--exclude id,id,...]
```

| Flag | Meaning |
|---|---|
| `--json` | Machine-readable JSON records |
| `--short` | Only warning/critical entries |
| `--strict` | Exit non-zero when errors are found (7 = critical, 4/5 = service/health) |
| `--errors-only` | Only error/critical entries |
| `--only-installed` | Skip not-installed apps |
| `--no-probe` | Skip live health probes |
| `--no-network` | Skip network version checks |
| `--include` / `--exclude` | Comma-separated app id filter |

`problems` implies `--strict`; `health-all` implies `--only-installed`.

### `doctor-all`

```text
deploy.sh doctor-all [--json] [--only-installed] [--include id,...] [--exclude id,...]
```

Runs each installed app's `doctor` and aggregates JSON records.

### `doctor security` / `doctor-security`

```text
deploy.sh doctor security [--json]
deploy.sh doctor-security [--json]
```

Runs a read-only legacy-install security audit. It checks for Vaultwarden
Admin Token temporary files, plaintext Sub2API PostgreSQL DSNs in legacy
backup scripts, wildcard listeners recorded in deployment configs, and
application backup jobs left in root crontab or unmanaged `/etc/cron.d`
drop-ins. It never prints credential contents and never deletes files.
The exit status is non-zero only when the audit cannot safely inspect a
security-sensitive path; findings are reported as `ok`, `warning`, `error`, or
`not_checked`. `--json` emits schema version 1 for automation.

### `backup-all`

```text
deploy.sh backup-all [--dry-run] [--yes] [--json] [--include id,...] [--exclude id,...]
```

`--yes` skips the confirmation prompt (or set `DEPLOY_ASSUME_YES=1`). With
`--json` and pending backups, `--yes` is required.

### `check-update`

```text
deploy.sh check-update [--json] [--refresh|--no-network] [--include id,...] [--exclude id,...]
```

Shows per-app Installed / Latest / Update state (cache-backed; `--refresh`
re-queries GitHub, `--no-network` uses only the cache). `--only-installed`
and `--continue-on-error` are accepted for symmetry.

### `update-all`

```text
deploy.sh update-all [--dry-run] [--yes] [--json] [--refresh|--no-network]
                     [--include id,...] [--exclude id,...]
```

Execution is always serial and never aborts on one app's failure
(`--continue-on-error` is the inherent behavior). `--yes` skips the prompt.

### Other central commands

```text
deploy.sh history [app-id] [--json] [--limit N]
deploy.sh list|apps
deploy.sh self-version [--json]
deploy.sh self-update [--check|--dry-run|--rollback|--list] [--json] [--yes] [--channel NAME]
deploy.sh <app>@<instance> <action>   # per-instance config/lock paths
```

## `notify-config`

```text
deploy.sh notify-config [--enable|--disable] [--backend ntfy|gotify]
                        [--url URL] [--topic TOPIC] [--token TOKEN]
                        [--test] [--clear]
```

Writes `/etc/deploy-notify.conf` (root:600). Config keys:

| Key | Purpose |
|---|---|
| `NOTIFY_ENABLED` | `true`/`false` |
| `NOTIFY_BACKEND` | `ntfy` or `gotify` |
| `NOTIFY_URL` | Service origin, e.g. `https://ntfy.example.com` |
| `NOTIFY_TOPIC` | ntfy topic (ntfy only) |
| `NOTIFY_TOKEN` | Bearer access token |
| `NOTIFY_USERNAME` / `NOTIFY_PASSWORD` | Gotify basic auth (gotify only) |

Notifications are fail-open: failures warn but never block the operation.
`--test` sends a probe message; `--clear` resets the file.

## `schedule`

```text
deploy.sh schedule [--enable|--disable] [--mode update-all|check-only]
                   [--at 'HH:MM' | OnCalendar | 'cron expr'] [--include app1,app2]
                   [--retries N] [--backoff SEC]
deploy.sh schedule status          # show current schedule
deploy.sh schedule run             # run the scheduled batch now (same as schedule-run)
deploy.sh unschedule               # remove the timer/cron + config
```

Scheduling uses a systemd timer (`deploy-scripts-batch`) when possible,
falling back to an `/etc/cron.d/deploy-scripts-batch` entry. The config lives
in `/etc/deploy-schedule.conf` (root:600). An explicit `--at` value is
validated before persisting.

## `export` / `import` (machine migration)

```text
deploy.sh export [--output FILE] [--redact]
deploy.sh import [--input FILE]
```

- `export` bundles every app's deployment config (plus notify/schedule
  settings) into a root:600 tar.gz, with a `backups-inventory.json` listing
  latest backups and an optional `--redact` human-readable reference copy.
  Default output: `/root/deploy-migration-<timestamp>.tar.gz`.
- `import` verifies the archive's sha256 sidecar, unpacks it, and installs
  the config files.
- Binaries/data are not migrated: install the apps on the target, replicate
  the backups, then run per-app `restore`.

## `fleet`

```text
deploy.sh fleet [status-all|update-all|backup-all] [--hosts FILE]
                [--concurrency N] [--timeout SEC] [--remote-dir DIR]
```

Runs the selected batch command on every host in the hosts file with bounded
concurrency, collecting per-host JSON. Hosts file format (default
`/etc/deploy-hosts.conf`, root:600): `alias|user@host[:port]` lines; comments
with `#`. `--concurrency` defaults to 4, `--timeout` to 120s (minimum 10),
`--remote-dir` is required and must be absolute without spaces. Hosts without
a configured target or unreachable hosts are reported as failed without
aborting the run.
