#!/usr/bin/env bash
# Runs ON THE SERVER. Prepares a bare Fedora host to run the Valheim stack.
# Idempotent — safe to re-run. Does NOT start the game server; deploy.sh does.
set -euo pipefail

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "1/8 System update"
dnf -y upgrade --refresh

log "2/8 Docker CE + compose plugin"
if ! command -v docker >/dev/null; then
  dnf -y install dnf-plugins-core
  dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null \
    || dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
docker version --format 'server {{.Server.Version}}'
docker compose version

log "3/8 Swap (4GB, OOM cushion — not a RAM substitute)"
if ! swapon --show | grep -q .; then
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  # game server: prefer RAM, use swap only under real pressure
  sysctl -w vm.swappiness=10
  grep -q '^vm.swappiness' /etc/sysctl.d/99-valheim.conf 2>/dev/null || echo 'vm.swappiness=10' > /etc/sysctl.d/99-valheim.conf
else
  echo "swap already present:"; swapon --show
fi

log "4/8 Firewall — UDP 2456-2457 + SSH, nothing else"
# NOTE: on a fresh Fedora cloud image firewalld is installed and `enabled` but
# NOT yet running. Configuring it only when active silently skips the firewall,
# and then the next reboot starts it with defaults that would block the game
# ports. So: write the rules offline, then start it.
if command -v firewall-offline-cmd >/dev/null; then
  firewall-offline-cmd --add-service=ssh || true
  firewall-offline-cmd --add-port=2456-2457/udp || true
  systemctl enable --now firewalld
  sleep 2
  firewall-cmd --list-all | grep -E "target:|services:|ports:"
else
  echo "firewalld not installed — relying on the Hetzner Cloud Firewall (see SECURITY.md)"
fi

log "5/8 fail2ban on the SSH jail"
# NOTE: the fail2ban-firewalld subpackage ties the two services together —
# starting firewalld AFTER fail2ban silently stops fail2ban. Firewall first
# (step 4), fail2ban second, and re-assert it at the end.
dnf -y install fail2ban >/dev/null
cat > /etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
findtime = 10m
JAIL
systemctl enable --now fail2ban
systemctl restart fail2ban     # re-assert in case step 4 disturbed it
echo "fail2ban: $(systemctl is-active fail2ban)"

log "6/8 SSH hardening"
# Guard: only disable password auth if THIS session came in via a key, so a
# misconfiguration can never lock us out of the box.
if [ "${SSH_AUTH_METHOD:-publickey}" = "publickey" ] && [ -s /root/.ssh/authorized_keys ]; then
  install -d -m 700 /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'SSHD'
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 2
# AllowTcpForwarding stays ENABLED on purpose: it is how the host-local status
# page is reached (ssh -L 9080:127.0.0.1:9080), and it guards nothing here.
SSHD
  sshd -t && systemctl reload sshd && echo "password auth disabled"
else
  echo "SKIPPED: /root/.ssh/authorized_keys is empty — refusing to disable password auth"
fi

log "7/8 Host hardening — auto security updates, LLMNR off, sysctl"
dnf -y install dnf5-plugin-automatic >/dev/null 2>&1 || dnf -y install dnf-automatic >/dev/null 2>&1 || true
# Fedora 44 ships dnf5; its config file is a %ghost entry and may not exist.
mkdir -p /etc/dnf/dnf5-plugins
cat > /etc/dnf/dnf5-plugins/automatic.conf <<'AUTO'
[commands]
upgrade_type = security
random_sleep = 300
network_online_timeout = 60
download_updates = yes
apply_updates = yes
reboot = never

[emitters]
emit_via = motd

[base]
assumeyes = True
AUTO
systemctl enable --now dnf5-automatic.timer 2>/dev/null || systemctl enable --now dnf-automatic.timer 2>/dev/null || true

# LLMNR/mDNS listen on 0.0.0.0:5355 by default and are useless on a public VM.
mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nLLMNR=no\nMulticastDNS=no\n' > /etc/systemd/resolved.conf.d/99-hardening.conf
systemctl restart systemd-resolved

cat > /etc/sysctl.d/99-hardening.conf <<'SYS'
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.tcp_syncookies=1
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
SYS
sysctl -p /etc/sysctl.d/99-hardening.conf >/dev/null

log "8/8 Final state"
printf 'firewalld : %s\nfail2ban  : %s\nauto-upd  : %s\n' \
  "$(systemctl is-active firewalld)" \
  "$(systemctl is-active fail2ban)" \
  "$(systemctl is-active dnf5-automatic.timer 2>/dev/null || echo n/a)"

log "Bootstrap complete"
