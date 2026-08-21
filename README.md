# valheim-server

A containerized **Valheim dedicated server** on its own Hetzner instance.

This directory holds everything needed to build, deploy and operate it:
the compose stack, the host bootstrap, and the docs describing exactly what
was done and why.

## Docs

| File | What's in it |
|---|---|
| `SERVER.md` | The machine: IP, location, specs, the SSH key we use, and the purpose |
| `DEPLOY.md` | Step-by-step record of the deployment — decisions, what ran, what's open |
| `SECURITY.md` | Port map, firewall rules, and the SSH hardening applied |
| `OPERATIONS.md` | Day-2: backups, world restore, updates, troubleshooting |

## Files

| File | Role |
|---|---|
| `docker-compose.yml` | The stack. One service, own bridge network, resource caps. |
| `.env.example` | Config template. Copy to `.env` and fill in. |
| `.env` | Real config incl. server password. **Gitignored, never committed.** |
| `bootstrap.sh` | Runs on the server: Docker, swap, firewall, SSH hardening. Idempotent. |
| `preflight.sh` | Runs on the server before deploy. Refuses to green-light a host that can't support the configured limits. |
| `deploy.sh` | Runs on biscuite. Ships the stack up and starts it. |

## Quickstart

```bash
ssh valheim 'echo OK'          # confirm key access first
./deploy.sh                    # bootstrap + preflight + up
```

Then join in-game: **Join Game → Join by IP**, using the address in `SERVER.md`
and the password from `.env`.

First boot downloads ~4 GB of game files, so allow **5–15 minutes** before the
server answers. That is normal, not a hang.

## Design notes

- **x86_64 only.** The Valheim dedicated server ships x86-only; Hetzner's ARM
  (`CAX`) instances would need box64 emulation, which is not viable for a game
  server. Do not "save money" by moving to ARM.
- **UDP 2456–2457 only.** Port 2458 is not used by current versions.
- **No control panel on the box.** Plain Docker host — a panel would consume
  ~1 GB for a machine running a single container.
- **Resource caps are deliberate.** Even on a dedicated box, `mem_limit` /
  `cpus` / `oom_score_adj` mean a runaway server process degrades the game
  rather than taking the whole host down with it.
