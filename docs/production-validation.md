# Production Validation Runbook

Purpose: close the only remaining verification gap — running the scripts on a
real host with real systemd, nginx, and certbot. CI proves the guard suite,
dispatch behaviour, and five container scenarios; it cannot prove that a real
VPS accepts the units, firewall entries, and certificates.

Use a scratch VPS or a disposable snapshot of a real one. Every phase is
read-only until Phase 2.

## Preconditions

- Debian 12 / Ubuntu 22.04+ with root access.
- Two DNS A records you control (for example `cpa.example.com` and
  `panel.example.com`) pointing at the host, if you intend to test HTTPS.
- Outbound HTTPS allowed (GitHub releases, Docker Hub, Let's Encrypt).
- The repository checked out at the commit you intend to validate.

Record the commit under test:

```bash
sudo bash deploy.sh self-version
sudo bash deploy.sh self-version --json
```

## Phase 0 — read-only baseline

```bash
sudo bash deploy.sh list
sudo bash deploy.sh doctor security --json
sudo bash deploy.sh status-all --json
```

Expectations:

- `list` shows sixteen apps and the documented actions.
- `doctor security --json` returns schema version 1, no `error` records, and
  both `tls_renewal` and `tls_expiry` are `ok` or `not_checked` (nothing
  installed yet).
- `status-all --json` is valid JSON with no credential values.

Save all three JSON payloads; they are the "before" snapshot.

## Phase 1 — dry runs

Before touching a real host, run the containerized systemd rehearsal — it boots
a real systemd as PID 1 (privileged container) and runs the shipped release
script against it, so unit enable/start, nginx validation, timer creation,
backup/restore against a running service, and uninstall cleanup are proven
without stubs:

```bash
bash tools/e2e-systemd.sh
```

It prints `SYSTEMD_E2E_OK` on success. Only systemd, nginx, and cron semantics
are still unproven after it — a real VPS, DNS, and certbot remain necessary.

Dry runs must not create files, users, units, or containers.

```bash
sudo bash deploy.sh ntfy --dry-run install
sudo bash deploy.sh ntfy --dry-run update
sudo bash deploy.sh ntfy --dry-run uninstall
sudo bash deploy.sh cpa-stack --dry-run cert
```

`--dry-run` goes before the action; after the action it is not parsed.

Then confirm nothing changed:

```bash
sudo bash deploy.sh doctor security --json
```

## Phase 2 — install one app per lifecycle shape

Non-interactive runs read configuration from the environment; see
`docs/apps.md` for per-app keys. Use `DEPLOY_ASSUME_YES=1` only after a dry run.

| Shape | Command |
|---|---|
| Shared binary lifecycle | `sudo DEPLOY_ASSUME_YES=1 bash deploy.sh ntfy install` |
| Framework app, static site | `sudo DEPLOY_ASSUME_YES=1 bash deploy.sh blog install` |
| Framework app, compose stack | `sudo DEPLOY_ASSUME_YES=1 bash deploy.sh tickflow install` |
| Hand-written multi-component | `sudo DEPLOY_ASSUME_YES=1 bash deploy.sh cpa-stack install` |

For each installed app, capture:

```bash
sudo bash deploy.sh <app> status
sudo bash deploy.sh <app> status-json
sudo bash deploy.sh <app> doctor
```

Expectations: `status` matches `systemctl is-active`; `status-json` parses;
`doctor` reports no blocking issue.

## Phase 3 — backup, restore, update, uninstall drill

Run this on the least valuable app first (for example `ntfy`).

```bash
sudo bash deploy.sh <app> backup
sudo bash deploy.sh <app> verify
sudo bash deploy.sh <app> restore
sudo bash deploy.sh <app> update
```

Between backup and restore, mutate one piece of application data so the restore
is observable. After restore:

```bash
sudo bash deploy.sh <app> status
sudo bash deploy.sh <app> verify
```

Then delete the app while keeping backups, and confirm the managed paths are
gone:

```bash
sudo DEPLOY_ASSUME_YES=1 DEPLOY_DELETE_DATA=1 bash deploy.sh <app> uninstall
systemctl status <service> || true
ls /etc/systemd/system/<service>.service 2>&1 || true
ls /etc/cron.d/ | grep -E 'certbot-renew|<app>' || true
```

Uninstall must either remove a managed artifact or fail loudly with the path it
could not remove. Silent success with leftovers is a bug — record it.

## Phase 4 — TLS and renewal

Only on a host with real DNS:

```bash
sudo DEPLOY_ASSUME_YES=1 bash deploy.sh cpa-stack cert
sudo bash deploy.sh cpa-stack status
sudo bash deploy.sh doctor security --json
```

Expectations:

- `status` prints the TLS section with a positive day count and a renewal
  source (certbot timer or `/etc/cron.d/certbot-renew-cpa-stack`).
- `doctor security --json` reports `tls_renewal` as `ok` and names every
  covered certificate count.
- `doctor security --json` reports `tls_expiry` as `ok` with the same day count
  `status` printed; `DEPLOY_SECURITY_TLS_WARN_DAYS` and
  `DEPLOY_SECURITY_TLS_ERROR_DAYS` move the warning and error thresholds.
- Renewal is actually scheduled:

```bash
systemctl list-timers 'certbot*' --all
cat /etc/cron.d/certbot-renew-* 2>/dev/null
certbot renew --dry-run
```

Negative check: temporarily move a per-app renewal file aside, rerun
`doctor security --json`, and confirm `tls_renewal` becomes a `warning` naming
that certificate. Restore the file afterwards.

## Phase 5 — central commands

```bash
sudo bash deploy.sh check-update --json
sudo bash deploy.sh schedule status
sudo bash deploy.sh notify-config --test
sudo bash deploy.sh export --output /root/deploy-export.tar.gz
sudo bash deploy.sh fleet status-all
```

Expectations: `check-update` distinguishes pinned and moving targets;
`schedule status` reflects the configured timer or cron entry;
`notify-config --test` fails without persisting a broken config;
`export` produces a private archive; `fleet` reports unreachable hosts without
aborting the run.

## Phase 6 — cleanup and record

```bash
sudo bash deploy.sh unschedule
sudo DEPLOY_ASSUME_YES=1 DEPLOY_DELETE_DATA=1 bash deploy.sh <app> uninstall
sudo bash deploy.sh doctor security --json
```

Record results in the table below and attach it to the commit or PR:

| Phase | Command | Result | Notes |
|---|---|---|---|
| 0 | `doctor security --json` | | |
| 1 | dry runs create nothing | | |
| 2 | install per shape | | |
| 3 | backup/verify/restore/update/uninstall | | |
| 4 | TLS + `certbot renew --dry-run` | | |
| 4 | negative renewal check warns | | |
| 5 | central commands | | |
| 6 | cleanup leaves no managed files | | |

Report back: commit hash, host OS version, any command whose output differed
from the expectations above, and any leftover path after uninstall.
