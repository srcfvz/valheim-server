# SERVER.md — the machine, the key, the purpose

_Last updated (UTC): 2026-08-22._

## Purpose

A **dedicated Valheim game server** on its own Hetzner instance — a single-purpose
box that runs the game and nothing else.

## The machine

| | |
|---|---|
| **Public IPv4** | `91.99.190.110` |
| **Public IPv6** | `2a01:4f8:c014:6a82::/64` |
| **Provider** | Hetzner Cloud |
| **Instance name** | `fedora-8gb-valheimsrcfvz` |
| **Plan** | CX33 — x86_64, 4 vCPU, 8 GB RAM (7737 MB usable), 80 GB disk |
| **OS** | Fedora Linux 44 (Forty Four) |
| **Location** | Helsinki, Finland (`HEL1`) — RIPE `netname: CLOUD-HEL1` |
| **Role** | Valheim dedicated server, nothing else |
| **SSH daemon** | OpenSSH 10.2 |
| **Host key** | `SHA256:Or9v6XF4demgawRjGaKTA2F/AaXZfcFyN6eaofaALWM` (ed25519) |

> **Latency note:** Helsinki is ~55–70 ms from Romania, vs ~35 ms from Nuremberg
> (`NBG1`) or Falkenstein (`FSN1`). Perfectly playable for Valheim, but not the
> latency optimum. Recorded here so nobody re-investigates it later as a bug.

## The SSH key

We use **one dedicated key, scoped to this machine only**:

| | |
|---|---|
| **Private** | `~/.ssh/id_ed25519_valheim` (mode 600, on `biscuite`) |
| **Public** | `~/.ssh/id_ed25519_valheim.pub` |
| **Type** | ed25519, **no passphrase** |
| **Fingerprint** | `SHA256:UHB2lC/qun6wB+kAFN+mdhui91Wn85lFF7FJ4mhyJSM` |
| **Comment** | `valheim-hetzner src21@biscuite 2026-08-21` |
| **Created** | 2026-08-21 |
| **Logs in as** | `root@91.99.190.110` |

Public key (paste target for the Hetzner console):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCaBq1iSzUAb40i3dcm0vqTyem34Z49tvC5nOCtW0bK valheim-hetzner src21@biscuite 2026-08-21
```

### Why a separate key, and why no passphrase

- **Separate:** blast-radius containment. This key opens the game server and
  nothing else — no other host in the fleet authorizes it, so a compromised game
  box has nowhere to pivot to.
- **No passphrase:** the deploy runs non-interactively from `biscuite`. The
  trade-off is accepted precisely *because* the key's scope is one disposable
  game server holding no secrets and no personal data.

Registered in the workspace key inventory at `homelab/AGENTS.md` (key table).

### Revoking it

```bash
# 1. remove the key from the server
ssh valheim "sed -i '/valheim-hetzner/d' ~/.ssh/authorized_keys"
# 2. delete it in the Hetzner console (Security -> SSH Keys)
# 3. drop it locally
rm ~/.ssh/id_ed25519_valheim ~/.ssh/id_ed25519_valheim.pub
```

## SSH config entry

Added to `~/.ssh/config` on `biscuite`:

```
Host valheim 91.99.190.110
  HostName 91.99.190.110
  User root
  IdentityFile ~/.ssh/id_ed25519_valheim
  IdentitiesOnly yes
```

So `ssh valheim` is the whole command.

## Credentials

The in-game server password lives in **`.env` only**, which is gitignored and
never committed. It is not written into any `.md` in this directory — the
workspace rule is that secrets never enter git, and this repo is pushed to
GitHub. See `.env.example` for the shape of the file.
