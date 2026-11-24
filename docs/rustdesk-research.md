# RustDesk Server OSS integration research

RustDesk is not currently registered as an application in this repository.
This document records upstream requirements for a future integration; it does
not describe an installer that is already available here.

Sources checked: RustDesk Server source at `680b603` and RustDesk documentation
at `ac92243` (November 2026).

- [RustDesk Server OSS overview](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/)
- [Installation and client configuration](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/)
- [Docker deployment and port guidance](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [Server source and configuration](https://github.com/rustdesk/rustdesk-server)

## Server components and networking

The open-source server runs two processes: `hbbs` provides ID registration and
rendezvous; `hbbr` provides relaying when a direct connection is unavailable.
The upstream documentation recommends Docker for most deployments and also
describes native systemd installations. The OSS server does not include the
Pro web console or API.

Default ports for native clients are TCP 21115 (NAT test), TCP and UDP 21116
(rendezvous and registration), and TCP 21117 (relay). TCP 21118 and 21119 are
for WebSocket clients and should stay closed when that feature is not used.
Upstream warns that directly accessible WebSocket listeners trust forwarded IP
headers; when used, restrict them to a reverse proxy that sets those headers.
Cloud firewall rules may need configuration independently of the host firewall.

The server stores its generated private key as `id_ed25519` and public key as
`id_ed25519.pub` in its working data directory. Persist and protect that data
across upgrades, reinstalls, backups and restores. Never display or publish the
private key. Clients normally need the server address and public key in their
network settings. Losing the private key changes the server identity and can
require updating clients.

## Integration work still required

- Design a two-process lifecycle consistent with the project framework,
  including instance isolation and status for both components. The shared
  binary lifecycle currently models one executable and one service.
- Verify the exact release asset names and supported architectures against the
  chosen upstream release; do not assume options documented on the upstream
  development branch exist in older releases.
- Implement install, update and rollback, backup and restore of persistent
  identity and data, uninstall, health reporting, localization and registration.
- Provide explicit port/firewall behavior and client setup guidance. Test both
  native client registration and relay connectivity on Linux, including failure
  and recovery paths, and regenerate and verify the release artifacts.
