# OPERATIONS.md — day-2 runbook

_Last updated (UTC): 2026-08-22._

Everything here assumes `ssh valheim` works (see `SERVER.md`). The stack lives
at `/opt/valheim` on the server.

## Cheat sheet

| Task | Command |
|---|---|
| Status | `ssh valheim 'cd /opt/valheim && docker compose ps'` |
| Live logs | `ssh valheim 'cd /opt/valheim && docker compose logs -f'` |
| Server status JSON | `ssh valheim 'curl -s http://127.0.0.1:9080/status.json'` |
| Resource usage | `ssh valheim 'docker stats --no-stream valheim-server'` |
| Restart | `ssh valheim 'cd /opt/valheim && docker compose restart'` |
| Stop | `ssh valheim 'cd /opt/valheim && docker compose stop'` |
| Start | `ssh valheim 'cd /opt/valheim && docker compose up -d'` |
| Who is online | `ssh valheim 'curl -s http://127.0.0.1:9080/status.json' \| jq .players` |

**Always stop with `docker compose stop`, never `kill`.** The compose file sets
`stop_grace_period: 2m` so the server flushes the world to disk before exiting.
Killing it can cost you the time since the last autosave.

## Changing configuration

Edit `.env` **locally** (in this directory), then re-deploy — never hand-edit the
copy on the server, or the next deploy silently reverts it:

```bash
vim .env
./deploy.sh --no-boot        # skips bootstrap, ships config, restarts
```

Changing `SERVER_PASS`, `SERVER_NAME` or `WORLD_NAME` requires a restart, which
`deploy.sh` performs.

## Backups

The container backs the world up **hourly** on its own:

- location on the server: `/opt/valheim/config/backups`
- retention: 12 files / 7 days max age (`BACKUPS_MAX_COUNT`, `BACKUPS_MAX_AGE`)

List them:
```bash
ssh valheim 'ls -lah /opt/valheim/config/backups'
```

Pull one off-box (do this before any risky change):
```bash
scp valheim:/opt/valheim/config/backups/<file>.tgz ./
```

### Restoring a world

```bash
ssh valheim 'cd /opt/valheim && docker compose stop'
ssh valheim 'cd /opt/valheim/config && cp -a worlds_local worlds_local.bak.$(date +%s)'
ssh valheim 'cd /opt/valheim/config && tar xzf backups/<file>.tgz'
ssh valheim 'cd /opt/valheim && docker compose up -d'
```

The `cp -a` line is not optional — it is what lets you undo a restore that turns
out to be the wrong snapshot.

> **Live world files are `/opt/valheim/config/worlds_local/<WORLD_NAME>.db` and
> `.fwl`.** The `.db` holds the world, the `.fwl` its seed and metadata. Both are
> needed; copying only the `.db` produces a world the server refuses to load.

## Updates

Valheim itself auto-updates daily at **05:00 UTC** (`UPDATE_CRON`), restarting
only when the server is idle (`RESTART_IF_IDLE`). No action needed.

Update the container image itself:
```bash
ssh valheim 'cd /opt/valheim && docker compose pull && docker compose up -d'
```

Host OS patching:
```bash
ssh valheim 'dnf -y upgrade --refresh && systemctl reboot'
```

## Troubleshooting

**`status.json` returns `TimeoutError` and A2S queries get no answer.**
**This is expected, not a fault.** With `-crossplay` enabled the server registers
through PlayFab/Steam relay and does not answer the classic Steam A2S query
protocol — which is exactly what the container's status probe uses. Judge health
from the logs instead:

```bash
ssh valheim 'cd /opt/valheim && docker compose logs --tail=50 --no-log-prefix' \
  | grep -E 'Session .* is active|join code'
```

A healthy server prints `Session "<name>" with join code <NNNNNN> and IP <ip>:2456
is active with N player(s)`. To get A2S/status.json working instead, clear
`SERVER_ARGS` in `.env` (drops crossplay, Steam-only).

**Proving the network path independently of the app.** If you need to know
whether packets actually reach the container, capture on the server while
sending from elsewhere — this bypasses any question of how the game answers:

```bash
ssh valheim 'timeout 25 tcpdump -ni any "udp port 2456 or udp port 2457" -c 10'
# then from another machine:
python3 -c "import socket;socket.socket(socket.AF_INET,socket.SOCK_DGRAM).sendto(b'x',('<ip>',2456))"
```
Arriving packets show as `eth0 In` followed by the docker bridge forwarding them
to the container's `172.x` address.

**Server not in the community browser.** Join by IP instead — the browser listing
is routinely slow and flaky, and is not a health signal. Confirm the server is
actually alive with `status.json` before chasing this.

**Nobody can connect.** Work outwards:
```bash
ssh valheim 'cd /opt/valheim && docker compose ps'          # container up?
ssh valheim 'ss -lnup | grep 245'                            # listening on UDP?
ssh valheim 'firewall-cmd --list-ports'                      # host firewall
# then check the Hetzner Cloud Firewall in the console — it sits in front of the
# VM, so a rule missing there looks exactly like a dead server from outside
nmap -sU -p 2456-2457 91.99.190.110                          # from outside
```

**"Wrong password" for everyone.** `SERVER_PASS` must be >= 5 chars and must not
contain the server name — Valheim silently refuses to start otherwise. Check the
logs for the refusal message.

**High memory / OOM restarts.** Check it against the cap:
```bash
ssh valheim 'docker stats --no-stream valheim-server'
```
The cap is `VALHEIM_MEM_LIMIT` in `.env` (currently `6g` on a 7737 MB box). If
the world has grown and legitimately needs more, the box needs resizing — do not
raise the cap past ~6.5 GB or the OS loses its own headroom.

**Container restart loop.** `docker compose logs --tail=100` first. The usual
causes are a malformed `.env` value or a corrupted world file — in which case,
restore from a backup above.

## Decommissioning

```bash
ssh valheim 'cd /opt/valheim && docker compose down'
scp valheim:/opt/valheim/config/backups/*.tgz ./world-archive/   # keep the world
```
Then delete the server in the Hetzner console, remove the key
(`ssh-keygen -R 91.99.190.110`, delete `~/.ssh/id_ed25519_valheim*`), drop the
`Host valheim` block from `~/.ssh/config`, and remove the key row from
`homelab/AGENTS.md`.
