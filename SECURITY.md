# SECURITY.md — exposure and hardening

_Last updated (UTC): 2026-08-22._

## Port map

| Port | Proto | Binding | Purpose |
|---|---|---|---|
| `2456` | UDP | `0.0.0.0` | Valheim game traffic — **must** be public |
| `2457` | UDP | `0.0.0.0` | Steam query / server browser — **must** be public |
| `9080` | TCP | `127.0.0.1` | Container status page — host-local only |
| `22` | TCP | `0.0.0.0` | SSH, key-only after bootstrap |

Port `2458` is **not** used by current Valheim versions. Do not open it.

## Why the game ports are public

The workspace baseline says container ports should not be published on
`0.0.0.0`, with an authenticating proxy in front. **A Steam game server cannot
comply:** the Valheim protocol is raw UDP, and an HTTP-layer access proxy cannot
front it. No reverse proxy in the stack speaks the Steam protocol.

So this is a deliberate, recorded exception — kept as narrow as possible:

- **only** the two UDP game ports are public
- the HTTP status/admin port stays bound to `127.0.0.1`
- a server password is mandatory (`SERVER_PASS`; Steam enforces >= 5 chars)
- the container runs on its own bridge network and joins nothing else
- the host runs Valheim and nothing else — no other service, no personal data

## Firewall

**Hetzner Cloud Firewall** — attach it in the console. It sits in front of the
VM, so it still holds if the host firewall is ever misconfigured:

```
Inbound  UDP  2456-2457   0.0.0.0/0, ::/0     # game + query
Inbound  TCP  22          0.0.0.0/0, ::/0     # SSH, key-only
                                               # everything else: DENY
```

**Host firewall** — `firewalld`, applied by `bootstrap.sh`. Verified active with
`services: dhcpv6-client mdns ssh` and `ports: 2456-2457/udp`.

> **Gotcha, found the hard way:** on a fresh Fedora cloud image firewalld is
> installed and `enabled` but **not running**. An earlier version of
> `bootstrap.sh` only configured it *if already active*, so it silently skipped —
> leaving the box with no host firewall, and a landmine where the next reboot
> would start firewalld with defaults that block the game ports. It now writes
> the rules with `firewall-offline-cmd` first, then starts the daemon.

> **Docker publishes past firewalld.** Container ports bypass firewalld's zone
> rules (Docker writes its own nftables rules), so the game ports keep working
> regardless. Filtering a *published* port requires the `DOCKER-USER` chain.
> firewalld here protects host services — it closed LLMNR on `5355`, which the
> image exposes publicly by default.

Equivalent commands:

```bash
# Debian/Ubuntu (ufw)
ufw allow 22/tcp && ufw allow 2456:2457/udp && ufw --force enable
# Fedora/RHEL (firewalld)
firewall-cmd --permanent --add-port=2456-2457/udp && firewall-cmd --reload
```

SSH stays open to `0.0.0.0/0` rather than pinned to a source address, because
the home connection is on a dynamic ISP address. Key-only auth is the control
that actually matters here.

## SSH hardening

Applied by `bootstrap.sh`, and **only after key login is verified working** — so
there is no way to lock ourselves out:

- `PasswordAuthentication no` — retires the provider-emailed root password,
  which is otherwise a standing brute-force target
- `PermitRootLogin prohibit-password`
- `fail2ban` on the SSH jail
- unattended security upgrades

## Blast radius

The only credential on this machine is the in-game server password, held in
`.env` (gitignored, never committed). The SSH key that opens it is dedicated to
this host and authorizes nothing else — see `SERVER.md`.

Worst case on total compromise or total loss: one Valheim world, which is backed
up hourly. Nothing else of value lives here, by design.
