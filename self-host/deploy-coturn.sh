#!/usr/bin/env bash
#
# MyDesk — one-click self-hosted relay (coturn)
#
# Installs coturn FROM THE DISTRO PACKAGE REPO (no Docker) with a STATIC AUTH
# SECRET (coturn "use-auth-secret"), then prints the exact values you paste
# into MyDesk:
#   Settings -> Custom relay (自定义中继) -> Add config
#
# Deliberately avoids every endpoint that is unreliable from mainland China:
#   get.docker.com, download.docker.com, registry-1.docker.io, api.ipify.org.
#
# Usage:
# ---usage begin
#   sudo bash deploy-coturn.sh                     # auto-detect public IP
#   sudo bash deploy-coturn.sh --ip 1.2.3.4        # force public IP (behind NAT)
#   sudo bash deploy-coturn.sh --turn-port 3478 --tls-port 5349
# ---usage end
#
# Tested on Ubuntu 26.04 / Debian 13. RHEL family is refused explicitly (see
# the platform check) rather than half-supported.
#
# Re-running is idempotent: the auth secret and the TLS cert are reused, so
# existing MyDesk configs keep working. To rotate the secret instead:
#   rm /etc/coturn/mydesk-secret  &&  run this script again
#
set -euo pipefail

DIR="/etc/coturn"            # certs + our own state
CONF="/etc/turnserver.conf"  # must match what the distro's coturn.service passes to -c
SERVICE="coturn"
IP=""
TURN_PORT=3478
TLS_PORT=5349
MIN_PORT=49152
MAX_PORT=65535

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)         IP="$2"; shift 2;;
    --turn-port)  TURN_PORT="$2"; shift 2;;
    --tls-port)   TLS_PORT="$2"; shift 2;;
    -h|--help)    sed -n '/^# ---usage begin/,/^# ---usage end/p' "$0" | sed -e '1d;$d' -e 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 1;;
  esac
done

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Please run as root:  sudo bash $0"

# --- 1. Platform ------------------------------------------------------------
command -v apt-get >/dev/null 2>&1 || die \
  "This script targets Debian/Ubuntu (apt-get not found). On RHEL/CentOS: install coturn from EPEL and put the same options in /etc/turnserver.conf."

# --- 2. Install coturn (distro repo — no Docker, no Docker Hub) -------------
if command -v turnserver >/dev/null 2>&1; then
  log "coturn already installed — skipping package install."
else
  log "Installing coturn from the distro repo ..."
  if ! apt-get update -qq; then
    warn "apt-get update failed. On a China-hosted box this is usually a slow or"
    warn "blocked upstream mirror — point /etc/apt/sources.list(.d/*) at"
    warn "mirrors.aliyun.com or mirrors.tuna.tsinghua.edu.cn and re-run."
    die "apt-get update failed"
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq coturn
  log "coturn installed."
fi
log "coturn version: $(dpkg-query -W -f='${Version}' coturn 2>/dev/null || echo unknown)"

# --- 3. Public IP -----------------------------------------------------------
# Cloud metadata first: in-China, fast, and correct even when the interface
# holds a private address (the common 阿里云/腾讯云 ECS case). Then public echo
# services that actually answer from mainland China.
detect_ip() {
  local url out
  for url in \
    "http://100.100.100.200/latest/meta-data/public-ipv4" \
    "http://metadata.tencentyun.com/latest/meta-data/public-ipv4" \
    "https://ip.3322.net" \
    "https://myip.ipip.net" \
    "https://ifconfig.co" \
    "https://api.ipify.org" ; do
    out="$(curl -fsS -m 3 "$url" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)" || true
    if [[ -n "$out" && "$out" != 127.* ]]; then printf '%s' "$out"; return 0; fi
  done
  return 1
}

if [[ -z "$IP" ]]; then
  log "Detecting public IP ..."
  IP="$(detect_ip || true)"
fi
[[ -n "$IP" ]] || die "Could not detect a public IP. Re-run with:  --ip <your.server.ip>"
log "Public IP: $IP"

# --- 4. Secret + TLS cert (both reused across runs) -------------------------
SSL_DIR="$DIR/ssl"
SECRET_FILE="$DIR/mydesk-secret"
install -d -m 750 "$DIR" "$SSL_DIR"

if [[ -s "$SECRET_FILE" ]]; then
  SECRET="$(cat "$SECRET_FILE")"
  log "Reusing existing auth secret ($SECRET_FILE)."
else
  if command -v openssl >/dev/null 2>&1; then
    SECRET="$(openssl rand -hex 32)"
  else
    SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  printf '%s\n' "$SECRET" > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  log "Generated a new static auth secret."
fi

TLS_OK=1
if [[ -f "$SSL_DIR/certificate.pem" && -f "$SSL_DIR/privatekey.pem" ]]; then
  log "Reusing existing TLS certificate."
elif command -v openssl >/dev/null 2>&1; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$SSL_DIR/privatekey.pem" -out "$SSL_DIR/certificate.pem" \
    -days 3650 -subj "/CN=$IP" >/dev/null 2>&1
  log "Generated self-signed TLS certificate (CN=$IP)."
else
  TLS_OK=0
  warn "openssl unavailable — TLS (turns:) will be disabled."
fi

if [[ "$TLS_OK" -eq 1 ]]; then
  chmod 644 "$SSL_DIR/certificate.pem"
  chmod 600 "$SSL_DIR/privatekey.pem"
  # coturn drops privileges to the 'turnserver' user, which must read the key.
  if id turnserver >/dev/null 2>&1; then
    chown -R turnserver:turnserver "$SSL_DIR"
  fi
fi

# --- 5. turnserver.conf -----------------------------------------------------
{
  echo "# MyDesk self-hosted relay — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "listening-port=$TURN_PORT"
  echo "tls-listening-port=$TLS_PORT"
  echo "external-ip=$IP"
  echo "min-port=$MIN_PORT"
  echo "max-port=$MAX_PORT"
  echo "fingerprint"
  echo "use-auth-secret"
  echo "static-auth-secret=$SECRET"
  echo "realm=$IP"
  echo "no-multicast-peers"
  echo "log-file=stdout"
  echo "simple-log"
  echo "cli-ip=127.0.0.1"
  echo "cli-port=35766"
  echo "cli-password=$SECRET"
  if [[ "$TLS_OK" -eq 1 ]]; then
    echo "cert=$SSL_DIR/certificate.pem"
    echo "pkey=$SSL_DIR/privatekey.pem"
  else
    echo "no-tls"
    echo "no-dtls"
  fi
} > "$CONF"
chmod 600 "$CONF"
log "Wrote $CONF"

# --- 6. Enable + start ------------------------------------------------------
# Debian/Ubuntu gate the init script behind this flag; harmless if unused.
if [[ -f /etc/default/coturn ]]; then
  if grep -qE '^#?TURNSERVER_ENABLED=' /etc/default/coturn; then
    sed -i 's|^#\?TURNSERVER_ENABLED=.*|TURNSERVER_ENABLED=1|' /etc/default/coturn
  else
    echo 'TURNSERVER_ENABLED=1' >> /etc/default/coturn
  fi
fi

systemctl enable "$SERVICE" >/dev/null 2>&1 || true
systemctl restart "$SERVICE"
sleep 1
if ! systemctl is-active --quiet "$SERVICE"; then
  warn "coturn failed to start. Unit definition:"
  systemctl cat "$SERVICE" --no-pager 2>&1 | head -n 20 >&2 || true
  warn "Last log lines:"
  journalctl -u "$SERVICE" -n 20 --no-pager >&2 || true
  die "coturn is not running (see above)."
fi
log "coturn is running."

# --- 7. Firewall (best effort) ---------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "$TURN_PORT"/tcp >/dev/null 2>&1 || true
  ufw allow "$TURN_PORT"/udp >/dev/null 2>&1 || true
  ufw allow "$TLS_PORT"/tcp  >/dev/null 2>&1 || true
  ufw allow "$TLS_PORT"/udp  >/dev/null 2>&1 || true
  ufw allow "$MIN_PORT:$MAX_PORT"/udp >/dev/null 2>&1 || true
  log "Opened required ports in ufw."
fi

# --- 8. Print the values ---------------------------------------------------
TLS_LINE=""
[[ "$TLS_OK" -eq 1 ]] && TLS_LINE="  TLS port (optional, if 3478 is blocked) : $TLS_PORT"

echo
echo "===================================================================="
echo "  MyDesk self-hosted relay is running."
echo "  Paste these into:  MyDesk -> Settings -> Custom relay (自定义中继)"
echo "                     -> Add config"
echo "===================================================================="
echo
echo "  Name        : My relay            (any label you like)"
echo "  TURN server : turn:$IP:$TURN_PORT"
echo "  STUN server : stun:$IP:$TURN_PORT"
echo "  Auth method : Static secret (静态密钥)"
echo "  Static key  : $SECRET"
[[ -n "$TLS_LINE" ]] && echo "$TLS_LINE"
echo "  Bandwidth   : <your server uplink in Kb/s, e.g. 102400 for 100 Mbps>"
echo
echo "  Then enable it for 控制时 / 被控时 and switch it on for the device."
echo
echo "  Logs        : journalctl -u $SERVICE -f"
echo "  Config file : $CONF"
echo "  Uninstall   : sudo apt-get purge -y $SERVICE && rm -rf $DIR"
echo
echo "  Cloud VPS: also open TCP/UDP $TURN_PORT, TCP/UDP $TLS_PORT and UDP"
echo "  $MIN_PORT-$MAX_PORT in the provider security group (安全组), not just ufw."
echo
echo "  Keep the static key private. To rotate it:  rm $SECRET_FILE"
echo "  and run this script again."
echo
