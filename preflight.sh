#!/usr/bin/env bash
# Run ON THE SERVER before deploying. Verifies the host can actually back the
# limits configured in .env, so we fail here rather than in an OOM at 2am.
set -uo pipefail

fail=0
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }

# Read the configured ceiling out of .env (default 6g), normalise to MB.
envf="$(dirname "$0")/.env"
lim=$(grep -E '^VALHEIM_MEM_LIMIT=' "$envf" 2>/dev/null | cut -d= -f2 | tr -d '"'"'"' ')
lim=${lim:-6g}
case "$lim" in
  *g|*G) lim_mb=$(( ${lim%[gG]} * 1024 )) ;;
  *m|*M) lim_mb=${lim%[mM]} ;;
  *)     lim_mb=$(( lim / 1024 / 1024 )) ;;
esac

echo "== 1. Architecture (Valheim is x86_64-only) =="
arch=$(uname -m)
if [ "$arch" = "x86_64" ]; then ok "$arch"; else bad "$arch — Valheim has no native ARM build; box64 emulation is not viable"; fi

echo "== 2. RAM vs configured cap (${lim} = ${lim_mb}MB) =="
total_mb=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
avail_mb=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
echo "  MemTotal=${total_mb}MB  MemAvailable=${avail_mb}MB"
if [ "$total_mb" -ge $(( lim_mb + 1536 )) ]; then
  ok "cap leaves >=1.5GB for the OS"
else
  bad "cap of ${lim_mb}MB is too close to MemTotal ${total_mb}MB — lower VALHEIM_MEM_LIMIT in .env"
fi
if [ "$total_mb" -lt 3500 ]; then warn "under 4GB total — Valheim will be tight even alone on the box"; fi

echo "== 3. CPU =="
cores=$(nproc)
if [ "$cores" -ge 2 ]; then ok "${cores} vCPU"; else warn "only ${cores} vCPU — expect tick lag with several players"; fi

echo "== 4. Swap (OOM cushion) =="
swap_mb=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)
if [ "$swap_mb" -ge 1024 ]; then ok "SwapTotal=${swap_mb}MB"; else warn "SwapTotal=${swap_mb}MB — bootstrap.sh adds 4GB"; fi

echo "== 5. Disk (game files need ~4GB) =="
free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if [ "${free_gb:-0}" -ge 10 ]; then ok "${free_gb}GB free on /"; else bad "only ${free_gb}GB free on / — need >=10GB"; fi

echo "== 6. UDP 2456-2457 =="
# On a redeploy our own container already holds these ports — that is fine.
# Only a FOREIGN listener is a problem.
if ss -lnu 2>/dev/null | grep -qE ':(2456|2457)\b'; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'valheim-server'; then
    ok "held by our own valheim-server container (redeploy)"
  else
    bad "in use by something else:"; ss -lnup | grep -E ':(2456|2457)\b'
  fi
else
  ok "free"
fi

echo "== 7. Docker =="
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ok "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  docker compose version >/dev/null 2>&1 && ok "compose plugin present" || bad "compose plugin missing"
else bad "docker not installed or not running — run bootstrap.sh"; fi

echo
if [ "$fail" -eq 0 ]; then echo "PREFLIGHT PASSED — safe to deploy."
else echo "PREFLIGHT FAILED — fix the FAIL lines above."; fi
exit "$fail"
