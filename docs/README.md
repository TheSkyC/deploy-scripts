# Documentation Index

Start with the root [README](../README.md) for supported platforms, installation commands, and framework conventions. This index groups the remaining documentation by task.

## Deploy and Configure

- [Per-app deployment reference](apps.md): supported applications, configuration keys, defaults, ports, and app-specific behavior.
- [Central commands reference](central-commands.md): fleet status, batch operations, notifications, scheduling, migration, and self-update commands.

## Operate and Recover

- [Instances, TLS, and migration runbook](instances-tls-migration.md): instance boundaries, reverse-proxy TLS, and export/import restore rehearsal.
- [Production validation runbook](production-validation.md): staged validation on a real Debian/Ubuntu host.
- [Security policy](../SECURITY.md): supported versions, vulnerability reporting, and security invariants.

## Maintain the Framework

- [Contributing guide](../CONTRIBUTING.md): localization, verification, platform assumptions, and release workflow.
- [Hand-written apps architecture decision](handwritten-apps.md): why selected apps retain bespoke lifecycle code and the shared invariants they must follow.
- [Expansion plan](../PLAN.md): archived goals and implementation notes for the shared binary-app expansion phase.
- [Central status and self-update design](central-status-and-self-update-design.md): historical design proposal; consult the live command reference and implementation for current behavior.

## Documentation Boundaries

`README.md`, `CONTRIBUTING.md`, `SECURITY.md`, and this directory describe supported behavior and repository workflows. Machine-local progress, audit history, and background research belong in `.dev/` and are intentionally excluded from Git. The `.dev/` directory is not shipped to other clones.
