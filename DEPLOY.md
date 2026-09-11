# DEPLOY.md — exactly what we are doing

_Last updated (UTC): 2026-08-22._

Chronological record of this deployment: what was decided, what was built, what
ran, and what is still open. See `SERVER.md` for the machine and key, and
`SECURITY.md` for ports and isolation.

## Step 0 — Decisions taken

| Decision | Outcome | Why |
|---|---|---|
| Where does Valheim run? | **Its own dedicated Hetzner instance** | A game server wants 2-3 GB resident and sustained CPU. It gets a box to itself rather than competing for one. |
| Which architecture? | **x86_64** | The Valheim dedicated server ships x86-only; ARM (Hetzner `CAX`) would need box64 emulation — unusable for a game server. |
| Which SSH key? | **New, dedicated `id_ed25519_valheim`** | Blast-radius containment — it authorizes this host only, and nothing else in the fleet. |
| Containerized? | **Yes** — `ghcr.io/lloesche/valheim-server` | Reproducible, self-updating, world backups built in. |
| Which ports? | **UDP 2456-2457** | What the game uses. `2458` is obsolete and stays shut. |
| Homelab instead? | **Rejected** | ISP does not permit port forwarding (CGNAT). |

## Step 1 — SSH key created [DONE]

Generated on `biscuite`, 2026-08-21:

```bash
ssh-keygen -t ed25519 -a 100 -N '' \
  -C "valheim-hetzner src21@biscuite 2026-08-21" \
  -f ~/.ssh/id_ed25519_valheim
```

Fingerprint `SHA256:UHB2lC/qun6wB+kAFN+mdhui91Wn85lFF7FJ4mhyJSM`.
Recorded in `homelab/AGENTS.md`.

## Step 2 — Server provisioned [DONE] (by hand, in the Hetzner console)

`fedora-8gb-valheimsrcfvz` — `203.0.113.10`, Hetzner Cloud, Helsinki (`HEL1`),
CX33 / Fedora Linux 44. Verified from the box itself: `x86_64`, 4 vCPU,
7737 MB RAM, 71 GB free.

> **Note — the first attempt was discarded.** An earlier instance at
> `62.238.124.10` was unreachable because its SSH key was never injected. Adding
> a key under *Security -> SSH Keys* only stores it on the **account**; it is
> injected into a VM by cloud-init **at creation time only**, so attaching it to
> an already-running server does nothing. The giveaway was that the host key
> never changed across a supposed "rebuild" — proof the machine was the same one.
> Resolution: the server was recreated with the key ticked at creation.

## Step 3 — Authorize the key [DONE]

The key was attached at creation, and access is confirmed:

```
$ ssh valheim 'echo CONNECTED; uname -m; nproc; free -m'
CONNECTED
x86_64
4
RAM=7737MB
```

Host key recorded in `SERVER.md`. If you ever recreate the box, clear the stale
entry first or SSH will refuse to connect:

```bash
ssh-keygen -R 203.0.113.10
```

## Step 4 — Host bootstrap [DONE]

Verified on the box after the run: Docker **29.7.2** + compose plugin, swap
**4095 MB**, firewalld with `2456-2457/udp` open, fail2ban active on the sshd
jail, and `PasswordAuthentication no` applied.

> **From here on, the provider-emailed root password no longer works.** Access is
> exclusively via `~/.ssh/id_ed25519_valheim`. Back that key up — losing it means
> recovering through the Hetzner console in rescue mode.


`bootstrap.sh` runs on the server and is idempotent — safe to re-run:

1. update packages
2. install Docker CE + compose plugin
3. create a 4 GB swapfile (OOM cushion, not a RAM substitute)
4. open UDP 2456-2457 in the host firewall
5. harden SSH: `PasswordAuthentication no`, `PermitRootLogin prohibit-password`
   — only **after** key login is confirmed working, so we cannot lock ourselves out

```bash
scp bootstrap.sh valheim:/root/ && ssh valheim 'bash /root/bootstrap.sh'
```

## Step 5 — Deploy [DONE]

`deploy.sh` exited 0. Preflight passed 7/7:

```
OK  x86_64
OK  cap leaves >=1.5GB for the OS   (MemTotal=7737MB, cap=6144MB)
OK  4 vCPU
OK  SwapTotal=4095MB
OK  67GB free on /
OK  UDP 2456-2457 free
OK  docker 29.7.2 + compose plugin
```

Container up, ports bound:
`0.0.0.0:2456-2457->2456-2457/udp, 127.0.0.1:9080->80/tcp`


```bash
./deploy.sh            # from this directory, on biscuite
```

Which does: copy `docker-compose.yml` + `.env` to `/opt/valheim`, run
`preflight.sh` on the host, and only on a pass `docker compose up -d`.

First boot downloads ~4 GB of game files — **5-15 minutes** before the server
appears in the Steam browser. That is normal, not a hang.

## Step 6 — Verify [DONE]

**Server is live.** From the logs, 2026-08-22 01:02:53 local:

```
Session "Valheim src21" registered with join code 460282
This is the serverIP used to register the server: 203.0.113.10:2456
Session "Valheim src21" with join code 460282 and IP 203.0.113.10:2456
  is active with 0 player(s)
```

**Network path proven end-to-end** with a packet capture on the server while
sending UDP from an external host — packets arrive on `eth0` and are forwarded
across the docker bridge to the container at `172.18.0.2`:

```
eth0            In  IP <ext>.58602 > 203.0.113.10.2456: UDP, length 25
br-8f61c2ea53f1 Out IP <ext>.58602 > 172.18.0.2.2456:    UDP, length 25
veth3b9e181     Out IP <ext>.58602 > 172.18.0.2.2456:    UDP, length 25
```

Resource use after world generation: **1.14 GiB / 6 GiB**, well inside the cap.

> `status.json` and raw A2S queries return timeouts. **Expected with
> `-crossplay`** — the server registers via PlayFab relay and does not answer
> the legacy Steam query protocol. See `OPERATIONS.md`.

### Original checklist


```bash
ssh valheim 'docker compose -f /opt/valheim/docker-compose.yml ps'
ssh valheim 'curl -s http://127.0.0.1:9080/status.json'
ssh valheim 'docker stats --no-stream valheim-server'   # confirm under the cap
```

From outside, confirm the game port answers:
```bash
nmap -sU -p 2456-2457 203.0.113.10      # expect open|filtered
```

## Step 7 — Connect

In Valheim: **Join Game -> Join by IP ->** `203.0.113.10:2456`, then the server
password from `.env`.

If the server does not appear in the community browser, join by IP — the browser
listing is frequently slow or flaky and is not a reliable health signal.

## Open items

- [x] Step 3: SSH key authorized
- [x] Plan confirmed: CX33, 7737 MB usable RAM. The `6g` cap leaves ~1.5 GB to
      the OS — `preflight.sh` enforces that margin and passes.
- [x] `OPERATIONS.md` written against the running box
- [x] Host firewall active (`firewalld`) — see the gotcha in `SECURITY.md`
- [ ] Optional: enable Hetzner automated backups (+20% of server cost) on top of
      the container's own hourly world backups
- [ ] Optional: move to `NBG1`/`FSN1` for ~20-35 ms lower latency from Romania
