#!/usr/bin/env bash
# Runs on biscuite. Ships the stack to the server and starts it.
#   ./deploy.sh            full: bootstrap + preflight + up
#   ./deploy.sh --no-boot  skip bootstrap (host already prepared)
set -euo pipefail

HOST=${VALHEIM_SSH_HOST:-valheim}
DEST=/opt/valheim
cd "$(dirname "$0")"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

[ -f .env ] || { echo "FATAL: .env missing — copy .env.example and fill it in"; exit 1; }
grep -q '^SERVER_PASS=.\{5,\}' .env || { echo "FATAL: SERVER_PASS must be >= 5 chars"; exit 1; }

log "0/4 Connectivity"
ssh -o BatchMode=yes "$HOST" 'echo "connected as $(id -un)@$(hostname)"'

if [ "${1:-}" != "--no-boot" ]; then
  log "1/4 Host bootstrap"
  scp -q bootstrap.sh "$HOST":/root/bootstrap.sh
  ssh "$HOST" 'bash /root/bootstrap.sh'
else
  log "1/4 Bootstrap skipped (--no-boot)"
fi

log "2/4 Upload stack"
ssh "$HOST" "mkdir -p $DEST"
scp -q docker-compose.yml .env preflight.sh "$HOST":"$DEST"/
ssh "$HOST" "chmod 600 $DEST/.env && chmod +x $DEST/preflight.sh"

log "3/4 Preflight"
ssh "$HOST" "bash $DEST/preflight.sh"

log "4/4 Start"
ssh "$HOST" "cd $DEST && docker compose pull -q && docker compose up -d"
ssh "$HOST" "cd $DEST && docker compose ps"

cat <<MSG

Deployed. First boot downloads ~4GB of game files (5-15 min) before the
server answers — this is normal.

  Watch progress : ssh $HOST 'cd $DEST && docker compose logs -f'
  Status         : ssh $HOST 'curl -s http://127.0.0.1:9080/status.json'
  Resource usage : ssh $HOST 'docker stats --no-stream valheim-server'
MSG
