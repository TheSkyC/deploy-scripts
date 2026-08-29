# Deploy Scripts

Shared deployment framework for application install scripts. The repository keeps the old top-level commands while moving common behavior into reusable framework libraries.

Reference documentation:
- [Per-app deployment reference](docs/apps.md) — every app's configuration keys, defaults, and non-obvious operations.
- [Central commands reference](docs/central-commands.md) — status-all/backup-all/update-all/doctor-all, notify-config, schedule, export/import, fleet.

## Quick Start

Run a script from the repository checkout:

```bash
sudo bash deploy.sh newapi install
sudo bash deploy.sh vaultwarden status
sudo bash deploy.sh newapi status-json
sudo bash deploy.sh sub2api doctor
sudo bash deploy.sh list
sudo CPA_DOMAIN=cpa.example.com CPAMP_DOMAIN=cpamp.example.com CERTBOT_EMAIL=admin@example.com bash deploy.sh cpa-stack install
sudo bash install_newapi.sh install
sudo bash install_sub2api.sh update
sudo bash install_vaultwarden.sh status
sudo bash install_tickflow.sh doctor
sudo bash install_newapi.sh --help
sudo bash install_cyberstrikeai.sh backup
sudo bash install_hugo_blog.sh install
```

Central management commands (via `deploy.sh`):

```bash
sudo bash deploy.sh backup-all                 # batch backup every installed app
sudo bash deploy.sh update-all                 # batch update every app
sudo bash deploy.sh status-all --json          # machine-readable fleet-local status
sudo bash deploy.sh newapi verify              # verify newest backup integrity
sudo bash deploy.sh vaultwarden restore        # restore newest backup (or <APP>_RESTORE_ARCHIVE=...)
sudo bash deploy.sh notify-config --enable --backend ntfy --url https://ntfy.example.com --topic deploy
sudo bash deploy.sh schedule --enable --mode update-all --at "04:30" --retries 2
sudo bash deploy.sh export --output /root/migration.tar.gz   # configs + backup inventory
sudo bash deploy.sh import --input /root/migration.tar.gz    # restore configs on the new host
sudo bash deploy.sh fleet status-all           # run status-all across /etc/deploy-hosts.conf
```

Run the central scheduler or an app script without arguments to open the interactive menu:

```bash
sudo bash deploy.sh
sudo bash install_newapi.sh
```

Use generated single-file release scripts when you want to copy only one file to a server:

```bash
sudo bash dist/install_newapi.sh install
```

For New API, Sub2API, Vaultwarden, Blog, CyberStrikeAI, TickFlow, and CPA Stack automation, `DEPLOY_ASSUME_YES=1` confirms uninstall without prompts while keeping data, config, install directories, and backups by default. Add `DEPLOY_DELETE_DATA=1`, `DEPLOY_DELETE_CONFIG=1`, `DEPLOY_DELETE_INSTALL=1`, or `DEPLOY_DELETE_BACKUP=1` only when those removals are intended. Vaultwarden install automation also requires setting `VW_DOMAIN` first, and setting `CERTBOT_EMAIL` when `ENABLE_HTTPS=true`.

## CPA Stack

`cpa-stack` installs CLIProxyAPI (CPA) and CPA Manager Plus (CPAMP) as two systemd services behind Nginx. The public API is served at `https://$CPA_DOMAIN/v1/...`; the management panel is served at `https://$CPAMP_DOMAIN/management.html`. Only Nginx ports `80` and `443` are intended to be public. CPA and CPAMP bind to `127.0.0.1:8317` and `127.0.0.1:18317` respectively.

Both DNS names must resolve to this server before HTTPS can be issued: create A (and AAAA, if needed) records for `$CPA_DOMAIN` and `$CPAMP_DOMAIN` pointing to the server, and allow inbound TCP `80`/`443`. The script keeps HTTP active if certificate issuance fails (for example because DNS is not ready yet); after fixing DNS, retry only the certificate step without re-downloading the releases:

```bash
sudo bash deploy.sh cpa-stack cert
```

Set two distinct DNS names and a Let's Encrypt email before installation:

```bash
sudo CPA_DOMAIN=cpa.example.com \
  CPAMP_DOMAIN=cpamp.example.com \
  CERTBOT_EMAIL=admin@example.com \
  bash deploy.sh cpa-stack install
```
By default the script enables CPA remote management (`CPA_ALLOW_REMOTE=true`) so the CPAMP web panel can reach the CPA management API from a browser; set `CPA_ALLOW_REMOTE=false` only when the panel is never used from a browser.

The script downloads verified native release archives, enables CPA usage publishing for CPAMP monitoring, stores CPAMP secrets in a root-only systemd environment file, creates a consistent backup, and supports `status`, `doctor`, `update`, `backup`, and safe uninstall. OAuth login is intentionally a manual post-install operation because provider flows can require localhost callbacks or device-code authorization.

Use `CPA_STACK_COMPONENT=cpa` or `CPA_STACK_COMPONENT=cpamp` with `update` to update one component; the default is `all`.
## Binary App Deployments

The following self-hosted services ship GitHub-release binaries and are deployed
through the shared binary-app lifecycle (`lib/binary_app.sh`), which installs
the release, sets up a systemd service, backups, firewall rules, and logrotate,
with `install`, `update`, `backup`, `status`, and safe `uninstall` actions:

| App | Default port | Notes |
|---|---|---|
| ntfy | 2586 | Push notification server; config at `/etc/ntfy/server.yml`. |
| Meilisearch | 7700 | Search engine; admin key in `/etc/meilisearch.env` (`MEILI_MASTER_KEY`). |
| Alist | 5244 | File listing service; data under `/var/lib/alist`. |
| Filebrowser | 8084 | Web file manager; served root defaults to `/srv/filebrowser` (`FB_ROOT`). |
| Navidrome | 4533 | Music server; music folder defaults to `/srv/music` (`MUSIC_DIR`). |
| frps | 7000 | frp server; config at `/etc/frps/frps.toml` (client auth token preserved). |
| Gitea | 3000 | Git hosting; config at `/etc/gitea/app.ini`; installs the system `git` package. |
| Gotify | 8085 | Push notification server; generated admin password in `/etc/gotify.env` (user: `admin`). |
| Beszel | 8090 | Monitoring hub; data under `/var/lib/beszel`; open `/api/health` for health checks. |

These apps can be managed through the central scheduler or directly:

```bash
sudo bash deploy.sh ntfy install
sudo bash install_meilisearch.sh status
sudo DEPLOY_LANG=zh bash dist/install_gitea.sh update
sudo bash deploy.sh beszel install
```

Defaults can be overridden per run, for example:

```bash
sudo PORT=8088 FB_ROOT=/srv/files bash install_filebrowser.sh install
sudo MUSIC_DIR=/mnt/music bash install_navidrome.sh install
```

For binary apps, `DEPLOY_ASSUME_YES=1` confirms uninstall without prompts while
keeping data, config, install directories, and backups by default; add
`DEPLOY_DELETE_DATA=1` or `DEPLOY_DELETE_BACKUP=1` only when those removals are
intended.

## Port conflict preflight

Install and update preflights warn when the app port is already bound by
another process. Set `DEPLOY_FAIL_ON_PORT_CONFLICT=1` to make that warning a
hard preflight failure, so an occupied port aborts before downloads and service
changes instead of failing at `systemctl start` (which triggers rollback):

```bash
sudo DEPLOY_FAIL_ON_PORT_CONFLICT=1 bash deploy.sh newapi install
```

## China mirrors (opt-in)

CyberStrikeAI builds from source and needs PyPI and Go module proxies. The
global defaults are the official upstreams (`pypi.org`,
`proxy.golang.org`). Set `DEPLOY_CN_MIRROR=1` to opt in to the China mirror
endpoints (PyPI tuna, goproxy.cn) for servers inside mainland China:

```bash
sudo DEPLOY_CN_MIRROR=1 bash deploy.sh cyberstrikeai install
```

An explicit `PIP_INDEX_URL` or `GOPROXY` environment variable — or a value
saved in the deployment config — always wins over both defaults.

## Managed framework releases

The framework self-update command uses verified release archives and only writes to an
explicit managed installation. A repository checkout and a standalone `dist/deploy.sh`
remain read-only for framework updates. Inspect the detected mode with:

```bash
bash deploy.sh self-version --json
bash deploy.sh self-update --check --json
```

A managed installation uses this layout under `/opt/deploy-scripts`:

```text
/opt/deploy-scripts/
  releases/<version>/
  current -> releases/<version>
  previous -> releases/<version>
  state/
```

To migrate a standalone copy, do not run `self-update` in place. Instead, obtain a
release archive and its manifest over HTTPS, verify the archive SHA-256 and internal
`RELEASE.json`, install the complete archive as a new directory below
`/opt/deploy-scripts/releases/`, then create or update the `current` and `previous`
symlinks atomically. The stable operator entrypoint should point to
`/opt/deploy-scripts/current/deploy.sh`. The repository intentionally does not
automatically migrate checkout or standalone files.

After a managed installation is prepared:

```bash
sudo bash /opt/deploy-scripts/current/deploy.sh self-version
sudo bash /opt/deploy-scripts/current/deploy.sh self-update --check
sudo bash /opt/deploy-scripts/current/deploy.sh self-update --dry-run
sudo bash /opt/deploy-scripts/current/deploy.sh self-update --yes
sudo bash /opt/deploy-scripts/current/deploy.sh self-update --list
sudo bash /opt/deploy-scripts/current/deploy.sh self-update --rollback --yes
```

Self-update configuration is kept separately in
`/etc/deploy-scripts/self-update.conf` and must be root-owned with mode `0600`.
Only the documented allow-listed settings are loaded; release URLs must use HTTPS
and must not contain credentials, queries, or fragments. Failed validation leaves
`current` unchanged, and a post-activation smoke-check failure automatically restores
the previous release.

## Localization

English is the default language. Set `DEPLOY_LANG=zh` to use Chinese framework messages and localized application messages for the bundled scripts.

```bash
sudo DEPLOY_LANG=zh bash install_newapi.sh install
sudo DEPLOY_LANG=zh bash dist/install_hugo_blog.sh update
```

Localization is intentionally layered:

- Framework messages live in `lib/i18n.sh`.
- Application metadata and app-specific messages live in `apps/*.sh`.
- Implementation scripts call `t message.key` for localized text and keep implementation comments in English.

## Repository Layout

```text
install_*.sh     Compatibility wrappers for existing user commands.
deploy.sh        Central scheduler for choosing an app and action.
bin/             Framework entrypoints for each script.
apps/            Application metadata, localization registration, and implementation loading.
impl/            Application-specific install/update/backup/status/uninstall functions.
lib/             Shared framework libraries.
tools/           Build and verification utilities.
dist/            Generated single-file release scripts.
```

## Framework Model

Each application is split into two layers:

- `apps/<app>.sh` declares `APP_ID`, `APP_NAME`, localized app messages, and the implementation path.
- `impl/install_<app>.sh` defines lifecycle functions such as `do_install`, `do_update`, `do_backup`, `do_status`, and `do_uninstall`.

Shared framework behavior includes:

- Menu and action dispatch.
- Shared non-destructive `doctor` diagnostics for identity, config, commands, and service state.
- Shared `status-json` output for automation-friendly application, config, and service state summaries.
- Logging helpers.
- File and path safety helpers.
- Atomic file writes, symlink replacement, and copy-backed backups.
- Lock handling.
- Config file loading and saving.
- Shared binary replacement and rollback helpers.
- Service wait helpers and systemd unit writes.
- Connectivity checks.
- Single-file release bundling.

## Library Conventions

Put behavior in `lib/` only when it is identical across apps apart from
small, app-supplied parameters. Prefer an `app_*` helper in `lib/` over
copying the same body into each `impl/install_<app>.sh`:

- `app_check_connectivity <error_key> <url...>` — connectivity checks with
  per-app endpoints and error keys.
- `app_write_nginx_config_file` / `app_write_nginx_site_link` — atomic Nginx
  site config writes and symlinks, with the per-app error key as an argument.
- `app_write_logrotate` — atomic per-app logrotate policy for the service log
  directory (target file, log dir, and error/success keys as arguments).
- `app_configure_firewall` — opens the service port through ufw/iptables (and
  opt-in firewalld), with a per-app key prefix and ufw comment label as arguments.
- `github_latest_release_tag` — GitHub release lookup shared by release-based apps.

Keep app-specific localized keys, prompts, and summary copy in
`apps/<app>.sh` and pass the key into the shared helper as an argument.
Do not merge per-app keys into shared libraries, and do not move shared
helpers into per-app impl scripts. When extracting a shared helper, update
the verification suite (`tools/checks/*.sh`) so guardrails require the shared
form and reject the old per-app copy, then keep the full verification suite
green.

## Adding A New App

1. Create `apps/myapp.sh` with metadata and localized messages.
2. Create `impl/install_myapp.sh` with `do_install` and any supported lifecycle functions.
3. Create `bin/install_myapp.sh` and a top-level `install_myapp.sh` wrapper following the existing pattern (wrapper/bin symmetry is enforced by `check_root_wrappers_match_bin_loaders` in the `guards` target).
4. Add the app to `tools/build-release.sh`.
5. Add verification coverage when the app has special dispatch or localization behavior: define new `check_*` functions in a `tools/checks/` module (e.g., `tools/checks/app-myapp.sh`) and register each one in a target arm (`dispatch` or `guards`); the `all` target picks up `check_*` functions automatically, and `check_target_groups_cover_all_checks` fails if a check is missing from a target arm.
6. Run verification:

```bash
bash tools/verify.sh
```

## Build Release Scripts

Build every single-file release script:

```bash
bash tools/build-release.sh all
```

Build one release script:

```bash
bash tools/build-release.sh newapi
```

`tools/verify.sh` rebuilds `dist/` with deterministic metadata before checking syntax and dispatch behavior; commit regenerated `dist/` files together with their source.

## Validation

Use Git Bash on Windows for Bash validation:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh
```

For faster local iteration, run a focused verification target:

```bash
bash tools/verify.sh syntax
bash tools/verify.sh shellcheck
bash tools/verify.sh release
bash tools/verify.sh dispatch
bash tools/verify.sh guards
bash tools/verify.sh prove   # behavioral feature proofs (backup/restore, notify, schedule, migrate, compose, fleet)
```

The parallel CI jobs run `syntax`, `shellcheck`, `release`, `dispatch`, and
`guards`; the union of those targets covers every check that `all` runs.
A nightly scheduled job runs the full `all` suite end-to-end.
`bash tools/verify.sh` (no target) still runs the full suite. The `all`
target runs independent checks concurrently (up to `PARALLEL_JOBS`, which
defaults to the CPU count); set `PARALLEL_JOBS=1` for a serial run.

Check definitions live in `tools/checks/*.sh` modules (per-app, dispatch,
release, and framework guardrails); `tools/verify.sh` sources them and only
holds the runner itself (targets, shared `expect_*` helpers, and `main`).

The verification script checks:

- Bash syntax for source scripts.
- Regenerated `dist/` scripts.
- Bash syntax for generated releases.
- English and Chinese dispatch behavior.
- English and Chinese app descriptions.
- Registered i18n keys match references in apps, implementations, and verification.
- No hardcoded Chinese text in implementation scripts.
- No Chinese comments in source or generated release scripts.
- No temporary bundled implementation files are left in `dist/`.
- Shellcheck static analysis on source scripts (skipped when shellcheck is not installed).
- Release scripts in `dist/` match the current source tree.

Structural guardrails assert against the **source** scripts
(`impl/`, `lib/`, `apps/`) and never duplicate the same assertions against
`dist/` text: `dist/` files are generated from the source, and
`check_dist_is_up_to_date` already proves they match the committed source
tree by rebuilding them deterministically and diffing. Keeping structural
assertions source-only means app functions do not need to dodge substrings
picked up by generated-text regexes, and one framework change rebuilds the
bundle once instead of chasing per-app dist snapshots.

## License

MIT — see [LICENSE](LICENSE).
