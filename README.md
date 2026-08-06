# Deploy Scripts

Shared deployment framework for application install scripts. The repository keeps the old top-level commands while moving common behavior into reusable framework libraries.

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
sudo bash install_blog.sh install
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
## Localization

English is the default language. Set `DEPLOY_LANG=zh` to use Chinese framework messages and localized application messages for the bundled scripts.

```bash
sudo DEPLOY_LANG=zh bash install_newapi.sh install
sudo DEPLOY_LANG=zh bash dist/install_blog.sh update
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
- `github_latest_release_tag` — GitHub release lookup shared by release-based apps.

Keep app-specific localized keys, prompts, and summary copy in
`apps/<app>.sh` and pass the key into the shared helper as an argument.
Do not merge per-app keys into shared libraries, and do not move shared
helpers into per-app impl scripts. When extracting a shared helper, update
`tools/verify.sh` so guardrails require the shared form and reject the old
per-app copy, then keep the full verification suite green.

## Adding A New App

1. Create `apps/myapp.sh` with metadata and localized messages.
2. Create `impl/install_myapp.sh` with `do_install` and any supported lifecycle functions.
3. Create `bin/install_myapp.sh` and a top-level `install_myapp.sh` wrapper following the existing pattern.
4. Add the app to `tools/build-release.sh`.
5. Add verification coverage to `tools/verify.sh` when the app has special dispatch or localization behavior. Register each new check in a target arm (`dispatch` or `guards`) as well as `all`; `check_target_groups_cover_all_checks` fails if a check is missing from either.
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
```

The parallel CI jobs run `syntax`, `shellcheck`, `release`, `dispatch`, and
`guards`; the union of those targets covers every check that `all` runs.
`bash tools/verify.sh` (no target) still runs the full suite.

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
