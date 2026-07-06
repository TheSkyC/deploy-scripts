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

For New API, Sub2API, and Vaultwarden automation, `DEPLOY_ASSUME_YES=1` confirms uninstall without prompts while keeping data, config, and backups by default. Add `DEPLOY_DELETE_DATA=1`, `DEPLOY_DELETE_CONFIG=1`, or `DEPLOY_DELETE_BACKUP=1` only when those removals are intended.

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

## Adding A New App

1. Create `apps/myapp.sh` with metadata and localized messages.
2. Create `impl/install_myapp.sh` with `do_install` and any supported lifecycle functions.
3. Create `bin/install_myapp.sh` and a top-level `install_myapp.sh` wrapper following the existing pattern.
4. Add the app to `tools/build-release.sh`.
5. Add verification coverage to `tools/verify.sh` when the app has special dispatch or localization behavior.
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

`tools/verify.sh` rebuilds `dist/` with deterministic metadata before checking syntax and dispatch behavior.

## Validation

Use Git Bash on Windows for Bash validation:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tools\verify.sh
```

For faster local iteration, run a focused verification target:

```bash
bash tools/verify.sh syntax
bash tools/verify.sh release
bash tools/verify.sh dispatch
```

The verification script checks:

- Bash syntax for source scripts.
- Regenerated `dist/` scripts.
- Bash syntax for generated releases.
- English and Chinese dispatch behavior.
- English and Chinese app descriptions.
- No hardcoded Chinese text in implementation scripts.
- No Chinese comments in source or generated release scripts.
- No temporary bundled implementation files are left in `dist/`.
