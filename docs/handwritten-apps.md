# Hand-Written Apps: Architecture Decision Record

Status: accepted 2026-11-01. Applies to `sub2api`, `vaultwarden`,
`cyberstrikeai`, and `cpa-stack`.

## Why this document exists

Sixteen apps ship through four different shapes:

| Shape | Apps | Implementation |
|---|---|---|
| Shared binary lifecycle | alist, beszel, filebrowser, frps, gitea, gotify, meilisearch, navidrome, newapi, ntfy | `lib/binary_app.sh` |
| Framework app, compose stack | tickflow | `impl/install_tickflow.sh` |
| Framework app, static site | blog | `impl/install_hugo_blog.sh` |
| Framework app, hand-written lifecycle | sub2api, vaultwarden, cyberstrikeai, cpa-stack | `impl/install_<app>.sh` |

The four hand-written apps look like candidates for `lib/binary_app.sh`, but
each carries a data model the shared lifecycle cannot express. Keeping them
bespoke is a deliberate decision, not an omission. This record states the
decision, the invariants that still apply to them, and the conditions under
which the decision should be revisited.

## Decision

Keep the four apps hand-written, and require them to compose the shared
primitives instead of re-implementing them. "Hand-written" means the app owns
its install/update/restore choreography; it does not mean the app may invent
its own config, locking, backup-publishing, removal, or health semantics.

## Shared primitives these apps must use

| Concern | Helper | Notes |
|---|---|---|
| Config path + persistence | `app_conf_file`, `app_save_config`, `app_load_config` | instance-qualified paths come from the shared resolver |
| Mutual exclusion | `acquire_lock` / `release_lock` | every mutating action |
| Atomic file publication | `atomic_write_file` | units, nginx sites, env files, cron entries |
| HTTP health probing | `app_http_status_code` | keeps retries and status parsing identical |
| Executable staging | `app_install_executable_file` | vaultwarden, cyberstrikeai |
| Archive creation | `backup_create_tar_archive` | unique temp name, private publish, tar diagnostics on stderr |
| Archive integrity | `backup_finalize_archive` | sha256 sidecar + manifest.json |
| Backup verification | `app_verify_latest_backup` | `verify` action contract |
| Rollback snapshot pruning | `app_prune_update_backups` | bounded retention |
| Removal | `app_remove_file_or_error`, `app_remove_dir_or_error` | safe-path guard + localized failure |
| TLS renewal cron | `app_tls_cron_file` | `/etc/cron.d/certbot-renew-<service>` |
| Public-bind policy | `app_enforce_secure_public_bind` | honours `DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND` |
| Version manifests | `version_check_component_json` | sub2api, cpa-stack |
| Restore-aside lifecycle | `backup_restore_data_dir`, `backup_restore_directory` | cyberstrikeai; the other three own multi-artifact transactions |

Current usage, verified by inspecting each impl:

- sub2api: locking, config, atomic writes, HTTP probe, tar publisher,
  integrity finalize, prune, removal helpers, component manifest.
- vaultwarden: the same set plus executable staging and the per-app TLS cron.
- cyberstrikeai: locking, config, atomic writes, executable staging, shared
  data-dir restore, prune, removal helpers.
- cpa-stack: locking, config, atomic writes, HTTP probe, tar publisher,
  integrity finalize, removal helpers, component manifest, per-app TLS cron.

## Why each stays bespoke

**sub2api** — one restore must atomically cover a PostgreSQL database, a data
directory, and a config file. The transaction stages both directories before
stopping the service, takes a private database snapshot, replays the dump with
`psql --single-transaction` and `ON_ERROR_STOP`, and on a failed health check
replays the snapshot and swaps the directories back. `lib/binary_app.sh`
models exactly one data directory and no database.

**vaultwarden** — the runtime image is extracted rather than executed by
Docker, optional web-vault archives replace static assets, and the data
directory plus env file form a two-artifact restore transaction. It also owns
fail2ban filters and an nginx TLS site.

**cyberstrikeai** — the binary is built from a pinned git commit with `go
build`, so install and update cannot be expressed as "download a release
asset". Restore covers the built binary, config, and data directory.

**cpa-stack** — two upstream components with independent repositories,
release-asset naming, and pinned versions (CLIProxyAPI and CPA Manager Plus),
two systemd units, a two-domain nginx front end, and SQLite state. The shared
lifecycle assumes one service and one upstream.

## Invariants the guards enforce

| Invariant | Guard |
|---|---|
| Mutating actions take the lock | `check_mutating_actions_acquire_locks` |
| Config writes are centralized and atomic | `check_config_writes_are_centralized` |
| Backup scripts publish atomically | `check_backup_scripts_are_atomic` |
| Backups go through the shared tar publisher | `check_backup_create_tar_archive_delegates`, `check_blog_backup_writes_integrity_metadata` |
| Backups carry integrity metadata | `check_runtime_backup_finalizes_integrity_metadata` |
| Update snapshots are pruned through the helper | `check_update_rollback_cleanup_uses_shared_helper` |
| Registry capabilities match the impl | `check_registry_restore_capability_matches_impl` |
| Every app exposes `verify`/restore as declared | `check_custom_impls_have_verify_delegate`, `check_shared_impls_have_restore_delegate` |
| Uninstall surfaces removal failures | `check_<app>_uninstall_checks_file_removal_errors`, `check_<app>_uninstall_checks_directory_removal_errors` |
| TLS renewal is scoped per app | `check_tls_renewal_crons_are_scoped_per_app`, `check_cpa_stack_certificate_renewal_is_scoped` |
| Public binds fail closed when requested | `check_security_defaults_and_public_bind_guard` |
| Renewal coverage is auditable | `check_security_doctor_tls_renewal_audit` |

## When to revisit

Fold a hand-written app into `lib/binary_app.sh` only when all of these hold:

1. It installs one executable from one upstream release asset.
2. It owns exactly one data directory and no external database.
3. Restore does not need a multi-artifact transaction or a database snapshot.
4. It needs no per-component version manifest.
5. Its uninstall is the shared set of unit, config, data, backup, and log paths.

If two or more of those fail, keep it hand-written and spend the effort on
composing shared primitives instead.

## Checklist for changes to these apps

1. Reuse an existing helper before writing a new loop, publisher, or remover.
2. Any new restore step must keep the aside copy until the service is healthy.
3. Any new scheduled work must be scoped to this app (`app_tls_cron_file`, a
   dedicated `/etc/cron.d` entry, or a dedicated systemd unit).
4. Any new listener must be loopback by default and routed through
   `app_enforce_secure_public_bind`.
5. Add or extend a guard in `tools/checks/app-<app>.sh` and register it in
   `tools/verify.sh`, then rebuild `dist/` before committing.
