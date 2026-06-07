# Deploy Scripts

Shared deployment framework for application install scripts. The repository keeps the old top-level commands while moving common behavior into reusable framework libraries.

## Quick Start

Run a script from the repository checkout:

```bash
sudo bash install_newapi.sh install
sudo bash install_sub2api.sh update
sudo bash install_vaultwarden.sh status
sudo bash install_cyberstrikeai.sh backup
sudo bash install_blog.sh install
```

Run without arguments to open the interactive menu:

```bash
sudo bash install_newapi.sh
```

Use generated single-file release scripts when you want to copy only one file to a server:

```bash
sudo bash dist/install_newapi.sh install
```

## Localization

English is the default language. Set `DEPLOY_LANG=zh` to use Chinese framework messages and localized application messages that have been migrated.

```bash
sudo DEPLOY_LANG=zh bash install_newapi.sh install
sudo DEPLOY_LANG=zh bash dist/install_blog.sh update
```

Localization is intentionally layered:

- Framework messages live in `lib/i18n.sh`.
- Application metadata and app-specific messages live in `apps/*.sh`.
- Implementation scripts call `t message.key` for localized text.

Some long operational output is still application-specific and will be migrated incrementally.

## Repository Layout

```text
install_*.sh     Compatibility wrappers for existing user commands.
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
- Logging helpers.
- File and path safety helpers.
- Lock handling.
- Config file loading and saving.
- Service wait helpers.
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

The verification script checks:

- Bash syntax for source scripts.
- Regenerated `dist/` scripts.
- Bash syntax for generated releases.
- English and Chinese dispatch behavior.
- No temporary bundled implementation files are left in `dist/`.
