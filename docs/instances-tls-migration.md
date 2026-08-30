# Instances, TLS, and Migration Runbook

This guide separates three related but different workflows:

1. selecting an **instance-specific deployment config and lock**;
2. publishing a loopback-bound service through HTTPS; and
3. exporting deployment metadata and rehearsing a restore on another host.

Treat each workflow as an operations change. A successful command does not by
itself prove that DNS, firewall policy, a reverse proxy, background jobs, and
application data are isolated correctly.

## Instance-qualified app selections

The central launcher accepts an optional suffix:

```bash
sudo bash deploy.sh <app>@<instance> <action>
```

`<instance>` must match `[a-z0-9_-]{1,32}`. For example:

```bash
sudo bash deploy.sh newapi@blue --help
sudo bash deploy.sh newapi@blue --dry-run install
sudo bash deploy.sh newapi@blue status-json
```

The suffix changes the framework-managed paths to:

```text
/etc/<app>-<instance>-deploy.conf
/var/lock/<app>-<instance>-deploy.lock
```

It does **not** rewrite an application's defaults for its systemd unit, port,
user, data directory, log directory, backup directory, Nginx site, cron job,
or fixed helper script. `@blue` is therefore a config/lock namespace, not a
claim that a second runtime is automatically isolated.

Before installing an additional runtime, use `--help` and `--dry-run install`
to identify every colliding resource. At a minimum, give each supported
runtime a distinct port, service name, service user (when appropriate),
install/data/log/backup directories, domain, and reverse-proxy site. Verify
that the application does not also write a fixed `/etc`, `/usr/local/bin`, or
`/etc/cron.d` path. If it does, do not run a second instance until that path is
made instance-aware in the implementation.

The current `status-all`, `backup-all`, `update-all`, and `doctor-all` commands
operate on the registered default app IDs; they do not discover every
`@instance` config automatically. Operate on each additional instance
explicitly and maintain an inventory of its runtime names and paths.

### Legacy config caution

Some hand-written applications retain compatibility with a legacy config path.
When such a legacy file exists, it can take precedence during loading. Migrate
or archive that file deliberately before treating an `@instance` selection as
independent. Never copy a production config into another instance without
reviewing its paths, credentials, port, service name, and domain.

### Current isolation boundary

The hand-written applications (Sub2API, Vaultwarden, CyberStrikeAI, CPA Stack,
and TickFlow) have application-specific services, helper scripts, dependency
state, or reverse-proxy configuration. Their default layouts should be treated
as **one runtime per host** unless an operator has reviewed every fixed
resource and supplied a complete isolation plan. The instance suffix alone is
not sufficient for these applications.

## HTTPS reverse-proxy runbook

Most web services bind to `127.0.0.1` by default. Keep that default and expose
only the reverse proxy on TCP 80/443. Before enabling TLS:

1. Create the DNS A/AAAA record for the chosen domain.
2. Allow inbound TCP 80 and 443 at the cloud/network firewall.
3. Check that no unrelated Nginx site owns the same `server_name`.
4. Provide an address that can receive the ACME registration email.
5. Do not expose the backend port publicly merely to make certificate issuance
   easier.

### Shared binary apps

For an app using the shared binary lifecycle, enable the built-in Nginx/certbot
flow at install time:

```bash
sudo DOMAIN=app.example.com \
  CERTBOT_EMAIL=admin@example.com \
  BA_ENABLE_HTTPS=1 \
  BA_BIND_ADDR=127.0.0.1 \
  bash deploy.sh ntfy install
```

Use the real app ID and domain. The service remains on loopback; Nginx is the
public endpoint. After installation, verify both the local service and the
external name:

```bash
sudo bash deploy.sh ntfy status
curl -I https://app.example.com/
```

For an existing plain-HTTP deployment, first inspect `--help`, the current
Nginx configuration, and the app's saved config. Do not assume that merely
setting an environment variable on `update` will safely replace a manually
managed proxy.

### App-specific TLS paths

- **Vaultwarden** uses `VW_DOMAIN`, `ENABLE_HTTPS=true`, and `CERTBOT_EMAIL`.
  Its install flow owns the Nginx/certbot setup.
- **CPA Stack** needs both `CPA_DOMAIN` and `CPAMP_DOMAIN`, plus
  `ENABLE_HTTPS=true` and `CERTBOT_EMAIL`; both names must resolve before
  issuance.
- **CyberStrikeAI** has its own Nginx/HTTPS configuration. Review its
  `--help` output and ensure the backend remains loopback-bound before
  publishing it.
- **Sub2API** and **TickFlow** should remain loopback-bound behind a reviewed
  reverse proxy. Confirm the app-specific documentation and existing Nginx
  ownership before adding a site.

If a deployment explicitly uses a wildcard listener, set
`DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1` during validation to reject a
plain-HTTP public binding where that guard is supported. This is a compatibility
opt-in, not a substitute for verifying the resulting proxy configuration.

## Export/import and restore rehearsal

`export` transfers deployment configuration and a backup inventory. It does
not transfer application data, binaries, Docker images, PostgreSQL/Redis
state, Nginx certificates, DNS records, or firewall policy.

### Source host

1. Verify the current backup before moving it:

   ```bash
   sudo bash deploy.sh <app> verify
   sudo bash deploy.sh <app> status-json
   ```

2. Create the config export and keep it private:

   ```bash
   sudo bash deploy.sh export --output /root/deploy-migration.tar.gz
   sha256sum /root/deploy-migration.tar.gz /root/deploy-migration.tar.gz.sha256
   ```

3. Copy the export and the app's verified backup archive through an approved
   encrypted transfer method. Preserve ownership/modes where applicable and
   avoid putting exports or secrets in a public object store.

### Target host

1. Prepare the host, DNS plan, ports, package/runtime prerequisites, and any
   intended instance-specific paths. Do not point production DNS at it yet.
2. Verify the export sidecar and import the deployment configs:

   ```bash
   sudo bash deploy.sh import --input /root/deploy-migration.tar.gz
   ```

3. Review the imported paths and secrets before installation. Install the app
   with the intended runtime topology, then place the verified data backup in
   that app's trusted backup directory.
4. Run the app's `restore` action, followed by `verify`, `doctor`, `status`,
   and a functional login/API check. For database-backed applications, include
   a read/write check appropriate to the application.
5. Only after the rehearsal succeeds should DNS, TLS certificates, or public
   traffic be switched. Keep the source host and its verified backup available
   until the rollback window closes.

For a portable inventory-only archive, `--redact` adds a human-readable
reference copy but does not make the primary export safe to publish. Treat the
primary archive as sensitive because it contains deployment configuration.

## Operator checklist

- [ ] The instance suffix, service/unit name, ports, directories, backup path,
      cron/helper path, and Nginx site are all unique.
- [ ] Backend services stay on loopback and only Nginx exposes 80/443.
- [ ] DNS resolves before requesting certificates; renewal is checked after
      installation.
- [ ] The newest backup verifies before migration and after copy.
- [ ] Restore is rehearsed without production traffic before cutover.
- [ ] The old host remains available for rollback until the new runtime is
      confirmed healthy.
