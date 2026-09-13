#!/usr/bin/env bash
#
# MyDesk — one-click self-hosted relay (coturn)
#
# Deploys coturn in Docker with a STATIC AUTH SECRET (coturn "use-auth-secret"),
# then prints the exact values you paste into MyDesk:
#   Settings -> Custom relay (自定义中继) -> Add config
#
# Usage:
#   sudo bash deploy-coturn.sh                     # auto-detect public IP
#   sudo bash deploy-coturn.sh --ip 1.2.3.4        # force public IP
#   sudo bash deploy-coturn.sh --dir /opt/mydesk-coturn
#   sudo bash deploy-coturn.sh --turn-port 3478 --tls-port 5349
#
# Tested on Ubuntu/Debian/CentOS. Needs a Linux server with a PUBLIC IP.
#
set -euo pipefail

DIR="/opt/mydesk-coturn"
IP=""
TURN_PORT=3478
TLS_PORT=5349
MIN_PORT=49152
MAX_PORT=65535
CONTAINER="mydesk-coturn"
IMAGE="coturn/coturn:4.6.2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)         IP="$2"; shift 2;;
    --dir)        DIR="$2"; shift 2;;
    --turn-port)  TURN_PORT="$2"; shift 2;;
    --tls-port)   TLS_PORT="$2"; shift 2;;
    -h|--help)    sed -n '2,16p' "$0"; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 1;;
  esac
done

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Please run as root:  sudo bash $0"

# --- 1. Docker -------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Docker not found — installing from get.docker.com ..."
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# --- 2. Public IP ----------------------------------------------------------
if [[ -z "$IP" ]]; then
  log "Detecting public IP ..."
  IP="$(curl -fsS https://api.ipify.org 2>/dev/null || curl -fsS https://ifconfig.me 2>/dev/null || true)"
fi
[[ -n "$IP" ]] || die "Could not detect a public IP. Re-run with:  --ip <your.server.ip>"
log "Public IP: $IP"

# --- 3. Secret, dirs, self-signed cert -------------------------------------
mkdir -p "$DIR/ssl"
if command -v openssl >/dev/null 2>&1; then
  SECRET="$(openssl rand -hex 32)"
else
  SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
log "Generated static auth secret."

TLS_OK=1
if [[ ! -f "$DIR/ssl/certificate.pem" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$DIR/ssl/privatekey.pem" -out "$DIR/ssl/certificate.pem" \
      -days 3650 -subj "/CN=$IP" >/dev/null 2>&1
  else
    TLS_OK=0
    warn "openssl unavailable — TLS (turns:) will be disabled."
  fi
fi

# --- 4. turnserver.conf ----------------------------------------------------
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
    echo "cert=/etc/coturn/ssl/certificate.pem"
    echo "pkey=/etc/coturn/ssl/privatekey.pem"
  else
    echo "no-tls"
    echo "no-dtls"
  fi
} > "$DIR/turnserver.conf"
chmod 600 "$DIR/turnserver.conf"
log "Wrote $DIR/turnserver.conf"

# --- 5. Run ----------------------------------------------------------------
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --network host --restart unless-stopped \
  -v "$DIR/turnserver.conf:/etc/coturn/turnserver.conf:ro" \
  -v "$DIR/ssl:/etc/coturn/ssl:ro" \
  "$IMAGE" >/dev/null
log "coturn container started."

# --- 6. Firewall (best effort) ---------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "$TURN_PORT"/tcp >/dev/null 2>&1 || true
  ufw allow "$TURN_PORT"/udp >/dev/null 2>&1 || true
  ufw allow "$TLS_PORT"/tcp  >/dev/null 2>&1 || true
  ufw allow "$TLS_PORT"/udp  >/dev/null 2>&1 || true
  ufw allow "$MIN_PORT:$MAX_PORT"/udp >/dev/null 2>&1 || true
  log "Opened required ports in ufw."
fi

# --- 7. Print the values ---------------------------------------------------
TLS_LINE=""
[[ "$TLS_OK" -eq 1 ]] && TLS_LINE="  TLS variant (if 3478 is blocked) : turns:$IP:$TLS_PORT"

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
echo "  Logs        : docker logs -f $CONTAINER"
echo "  Config file : $DIR/turnserver.conf"
echo "  Uninstall   : docker rm -f $CONTAINER && rm -rf $DIR"
echo
echo "  Keep the static key private. To rotate it:  rm $DIR/turnserver.conf"
echo "  and run this script again."
echo
