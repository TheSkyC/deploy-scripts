# Per-App Deployment Reference

Every app ships as `install_<app>.sh` (source: `impl/install_<app>.sh`) and is
also reachable through the central launcher: `deploy.sh <app> <action>`.
Common actions: `install`, `update`, `backup`, `restore`, `status`,
`status-json`, `doctor`, `verify`, `uninstall`.

Every app supports `--help` (lists configuration keys with current values) and
`--dry-run <action>` (previews what install/update/backup/uninstall would do
without touching the system). Configuration keys are environment variables;
export any key to override its default.

## Binary apps (shared lifecycle)

The following nine apps share `lib/binary_app.sh`: `alist`, `beszel`,
`filebrowser`, `frps`, `gitea`, `gotify`, `meilisearch`, `navidrome`, `ntfy`.

Common keys (defaults in parentheses):

| Key | Purpose |
|---|---|
| `DOMAIN` | Public domain (optional; used in summary) |
| `PORT` | Service port |
| `INSTALL_DIR` | Binary directory |
| `DATA_DIR` | Runtime data |
| `LOG_DIR` | Logs |
| `SERVICE_NAME` / `SERVICE_USER` | systemd unit / OS user |
| `GITHUB_REPO` | Upstream repository |
| `BACKUP_DIR` / `BACKUP_KEEP_DAYS` | Backups (default 30 days) |
| `BA_BIND_ADDR` | Listen address, `127.0.0.1` by default (reverse-proxy friendly). Set `0.0.0.0` only when the app is meant to be public; the install summary warns about plain-HTTP exposure |
| `BA_VERSION` | Pin an exact GitHub release tag (e.g. `v1.2.3`). Unset = latest. `update` upgrades to the pinned tag when set |
| `INSTALLED_VERSION` | Recorded at install; do not edit |

App-specific defaults:

| App | Default port | Notes |
|---|---|---|
| alist | 5244 | First-run admin password: `alist admin --data /var/lib/alist` |
| beszel | 8090 | Health: `/api/health`; admin key in `/etc/beszel.env` |
| filebrowser | 8084 | Serves `FB_ROOT` (`/srv/filebrowser`); default admin `admin/admin` — change on first login |
| frps | 7000 | Public TCP proxy; `BA_BIND_ADDR=0.0.0.0` by design. Auth token in `/etc/frps/frps.toml` |
| gitea | 3000 | First admin: `gitea admin create-user --admin --config /etc/gitea/app.ini` |
| gotify | 8085 | Initial admin password (random) in `/etc/gotify.env` (`GOTIFY_DEFAULTUSER_PASS`) |
| meilisearch | 7700 | Master key (random) in `/etc/meilisearch.env` (`MEILI_MASTER_KEY`) |
| navidrome | 4533 | Music folder `MUSIC_DIR` (`/srv/music`) |
| ntfy | 2586 | Config `/etc/ntfy/server.yml`; listens on `BA_BIND_ADDR` |

## Hand-written apps

### Vaultwarden (`vaultwarden`, port 8081)

- Web Vault, Nginx reverse proxy, Let's Encrypt (certbot), fail2ban, daily
  backups at 03:30 into `/opt/vaultwarden-backups`.
- **Admin panel**: the plaintext Admin Token is generated on install and
  stored at `VW_ADMIN_TOKEN_FILE` (`/root/.vaultwarden-admin-token`, mode
  600). It is never printed to the terminal. View/rotate/delete it with:
  - `install_vaultwarden.sh token` (view)
  - `install_vaultwarden.sh token rotate`
  - `install_vaultwarden.sh token delete`
- **Registration**: `SIGNUPS_ALLOWED` defaults to `false`. To create the
  first account: `install_vaultwarden.sh signups on`, create the account,
  then `install_vaultwarden.sh signups off`. `signups status` shows the
  current value.
- Key config: `VW_DOMAIN`, `VW_PORT`, `VW_ENV_FILE` (`/etc/vaultwarden.env`),
  `VW_IMAGE_TAG`, `ENABLE_HTTPS` (default true, requires `CERTBOT_EMAIL`),
  `VW_ADMIN_TOKEN_FILE`.
- Database is SQLite at `VW_DATA_DIR` (`/var/lib/vaultwarden`); the backup
  script checkpoints and integrity-checks it before archiving.

### Sub2API (`sub2api`, port 8082)

- AI API gateway with PostgreSQL + Redis, nginx reverse proxy, daily backups
  at 03:30.
- **PostgreSQL setup**: on install the script creates `PG_USER`/`PG_DB`
  (default `sub2api`/`sub2api`) with a random password. The connection DSN is
  written to `CONFIG_DIR/.pg_dsn` (`/etc/sub2api/.pg_dsn`, mode 600) and the
  backup script reads it from there — there is no second credential copy.
  Set `PG_PASS` to pin the password; identifiers are validated (letters,
  digits, underscore only).
- **Bind**: `SUB2API_BIND_ADDR` defaults to `127.0.0.1` (nginx is the public
  entry point). `SUB2API_TZ` replaces the old hardcoded `Asia/Shanghai`
  (empty = server local time).
- Restore: `install_sub2api.sh restore` loads the DB dump via `psql`.

### New API (`newapi`, port 8080)

- LLM API aggregation gateway (SQLite by default), systemd-managed, nightly
  backups. `SESSION_SECRET` is generated into the env file
  (`/etc/newapi.env`, mode 600).
- **First login uses the application's built-in default admin credentials —
  change the password immediately.** The install summary warns about this but
  does not print the credentials.
- Key config: `DOMAIN`, `PORT`, `BACKUP_CRON` (default daily 03:30), `TZ`.

### CyberStrikeAI (`cyberstrikeai`, backend port 8083, public `PUBLIC_PORT` 80)

- Python/Go AI gateway with optional nginx (`ENABLE_NGINX`), optional HTTPS
  (`CSAI_HTTPS`), pip index / Go proxy mirrors (`PIP_INDEX_URL`, `GOPROXY`).
- The backend binds `127.0.0.1`; nginx (when enabled) is the public entry.
- `OPEN_FIREWALL` controls firewall port opening (default off).

### CPA Stack (`cpa_stack`)

- Dockerized CPA + CPAMP deployment. Config: `CPA_DOMAIN`, `CPAMP_DOMAIN`,
  `ENABLE_HTTPS`, `CPA_ALLOW_REMOTE`, `CERTBOT_EMAIL`, install/data/env
  directories for both components.

### TickFlow (`tickflow`, port 3018)

- Docker compose stock panel.
- **Authentication**: `TICKFLOW_AUTH_PASSWORD` is generated randomly when
  neither the config nor an existing `.env` provides one (no more
  unauthenticated public panel). An explicitly set password must be ≥ 6
  characters. The panel password lives in `TICKFLOW_ENV_FILE`
  (`/opt/tickflow-stock-panel/.env`, `AUTH_PASSWORD`).
- **Bind**: `TICKFLOW_BIND_ADDR` defaults to `127.0.0.1`; the compose port
  mapping follows it. Put the panel behind an HTTPS reverse proxy to publish
  it.
- Other keys: `TICKFLOW_REPO`, `TICKFLOW_BRANCH`, `TICKFLOW_BACKEND_EXTRAS`,
  `TICKFLOW_DOMAIN` (summary only).

### Hugo blog (`hugo_blog`)

- Static blog with optional CMS backend. Config: `BLOG_TITLE`, `BLOG_AUTHOR`,
  `BLOG_LANG`, `SITE_DIR`, `PUBLIC_DIR`, `NGINX_ROOT`, `THEME_NAME`,
  `THEME_REPO`, `ENABLE_CMS`, `CMS_REPO`, `CMS_BRANCH`, `CMS_SITE_URL`, and
  optional `HUGO_VERSION`.
- Leave `HUGO_VERSION` unset to install the latest Hugo release. Set an exact
  semantic version without a leading `v` (for example `HUGO_VERSION=0.150.1`)
  to pin both `install` and `update`; the successful package version is saved
  as `INSTALLED_VERSION`. `check-update` reports the pinned target without a
  network lookup, while unpinned deployments compare against GitHub Releases.
- The Hugo `.deb` is verified against the SHA-256 digest published in the
  GitHub release metadata before `dpkg -i`.
- Publishing: `blog-publish` (installed to `/usr/local/bin`).

## Security defaults (all apps)

- Web apps bind `127.0.0.1` by default; publish through an HTTPS reverse
  proxy.
- No firewall ports are opened automatically for the binary apps
  (`BA_FIREWALL=0` default; frps opts in with `BA_FIREWALL=1`).
- Secrets (admin tokens, DB passwords, master keys) live in root-only files,
  never in the terminal output or operation logs.
- Installing blog or vaultwarden moves `/etc/nginx/sites-enabled/default`
  aside recoverably (`.default.deploy-bak` in sites-available) and restores
  it on uninstall.
- Uninstall exports the deployment config first (see the printed hint).
