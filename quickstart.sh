#!/usr/bin/env bash
set -euo pipefail

# SSHamrock quickstart installer
# Usage: sudo bash quickstart.sh

INSTALL_DIR="/opt/ssh-relay"
CONFIG_DIR="/etc/ssh-relay"
LOG_DIR="/var/log/ssh-relay"
RELAY_REPO="https://github.com/tehrhart/nassh-proxy.git"
SERVICE_NAME="ssh-relay"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}==>${NC} ${BOLD}$*${NC}"; }
ok()    { echo -e "${GREEN} ✓${NC} $*"; }
error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

# --- Pre-flight checks ---
[[ $EUID -eq 0 ]] || error "Run as root: sudo bash quickstart.sh"
command -v python3 >/dev/null || error "Python 3.11+ is required"
command -v git >/dev/null || error "git is required"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -d "$SCRIPT_DIR/dist" ]] || error "dist/ directory not found. Run from the sshamrock repo root."
[[ -f "$SCRIPT_DIR/dist/plugin/wasm/ssh.wasm" ]] || error "dist/plugin/wasm/ssh.wasm not found."

echo ""
echo -e "${BOLD}  SSHamrock — Browser-based SSH client${NC}"
echo -e "  ${BLUE}https://github.com/tehrhart/sshamrock${NC}"
echo ""

# --- Gather configuration ---
# All settings can be pre-set via environment variables for unattended installs.
# Example: SSHAMROCK_HOST=ssh.example.com SSHAMROCK_IDP=cloudflare \
#          SSHAMROCK_CF_TEAM=myco SSHAMROCK_CF_AUD=abc123 bash quickstart.sh
#
# Network: SSHAMROCK_BIND_IP and SSHAMROCK_TRUSTED_PROXIES control where the
# relay listens and which upstream IPs may set forwarded-for headers.
# Default: 127.0.0.1 (localhost only). For remote cloudflared load balancers,
# set BIND_IP to a LAN address and TRUSTED_PROXIES to the cloudflared IPs.

info "Configuration"
echo ""

if [[ -n "${SSHAMROCK_HOST:-}" ]]; then
  PUBLIC_HOST="$SSHAMROCK_HOST"
  ok "Hostname: $PUBLIC_HOST (from env)"
else
  read -rp "  Public hostname (e.g. ssh.example.com): " PUBLIC_HOST
fi
[[ -n "$PUBLIC_HOST" ]] || error "Hostname is required"

PUBLIC_PORT="${SSHAMROCK_PORT:-}"
if [[ -z "$PUBLIC_PORT" ]]; then
  read -rp "  Public port [443]: " PUBLIC_PORT
fi
PUBLIC_PORT="${PUBLIC_PORT:-443}"

IDP_CHOICE="${SSHAMROCK_IDP:-}"
if [[ -z "$IDP_CHOICE" ]]; then
  echo ""
  echo "  Identity provider options:"
  echo "    1) none          — no authentication (for testing only)"
  echo "    2) cloudflare    — Cloudflare Access (requires team domain + audience)"
  echo "    3) gcp-iap       — Google IAP (requires audience)"
  echo ""
  read -rp "  Identity provider [1]: " IDP_CHOICE
fi
IDP_CHOICE="${IDP_CHOICE:-1}"

IDP="none"
AUTH_REQUIRED="false"
CF_TEAM="${SSHAMROCK_CF_TEAM:-}"
CF_AUD="${SSHAMROCK_CF_AUD:-}"
IAP_AUD="${SSHAMROCK_IAP_AUD:-}"

case "$IDP_CHOICE" in
  2|cloudflare|cloudflare-access)
    IDP="cloudflare-access"
    AUTH_REQUIRED="true"
    if [[ -z "$CF_TEAM" ]]; then
      read -rp "  Cloudflare team domain (e.g. mycompany): " CF_TEAM
    fi
    if [[ -z "$CF_AUD" ]]; then
      read -rp "  Cloudflare Access audience tag: " CF_AUD
    fi
    [[ -n "$CF_TEAM" && -n "$CF_AUD" ]] || error "Team domain and audience are required"
    ok "Identity: Cloudflare Access ($CF_TEAM)"
    ;;
  3|gcp-iap)
    IDP="gcp-iap"
    AUTH_REQUIRED="true"
    if [[ -z "$IAP_AUD" ]]; then
      read -rp "  IAP audience (e.g. /projects/123/global/backendServices/456): " IAP_AUD
    fi
    [[ -n "$IAP_AUD" ]] || error "IAP audience is required"
    ok "Identity: GCP IAP"
    ;;
  *)
    echo ""
    echo -e "  ${RED}WARNING: Running without authentication. For testing only.${NC}"
    echo ""
    ;;
esac

# --- Network binding ---
BIND_IP="${SSHAMROCK_BIND_IP:-}"
if [[ -z "$BIND_IP" ]]; then
  echo ""
  echo "  Listener bind address:"
  echo "    127.0.0.1  — localhost only (cloudflared on same machine)"
  echo "    0.0.0.0    — all interfaces (remote load balancer)"
  echo "    10.x.x.x   — specific LAN IP"
  echo ""
  read -rp "  Bind IP [127.0.0.1]: " BIND_IP
fi
BIND_IP="${BIND_IP:-127.0.0.1}"

TRUSTED_PROXIES="${SSHAMROCK_TRUSTED_PROXIES:-}"
if [[ "$BIND_IP" != "127.0.0.1" && -z "$TRUSTED_PROXIES" ]]; then
  echo ""
  echo "  Since the relay is not localhost-only, you must specify which"
  echo "  upstream IPs are trusted to set X-Forwarded-For headers."
  echo "  Comma-separated IPs or CIDRs (e.g. 10.0.0.0/8,172.16.0.0/12)"
  echo ""
  read -rp "  Trusted proxy IPs: " TRUSTED_PROXIES
  [[ -n "$TRUSTED_PROXIES" ]] || error "Trusted proxies required when binding to a non-localhost address"
fi
TRUSTED_PROXIES="${TRUSTED_PROXIES:-127.0.0.1}"

# --- Create user and directories ---
info "Creating service user and directories"
id "$SERVICE_NAME" &>/dev/null || useradd -r -s /sbin/nologin "$SERVICE_NAME"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
chown "$SERVICE_NAME:$SERVICE_NAME" "$LOG_DIR"
ok "User and directories ready"

# --- Install relay server ---
info "Installing nassh-proxy relay server"
if [[ -d "$INSTALL_DIR/src/.git" ]]; then
  (cd "$INSTALL_DIR/src" && git pull --quiet)
  ok "Updated existing relay code"
else
  rm -rf "$INSTALL_DIR/src"
  git clone --quiet "$RELAY_REPO" "$INSTALL_DIR/src"
  ok "Cloned relay server"
fi

if [[ ! -d "$INSTALL_DIR/.venv" ]]; then
  python3 -m venv "$INSTALL_DIR/.venv"
fi
"$INSTALL_DIR/.venv/bin/pip" install --no-cache-dir -q -e "$INSTALL_DIR/src/"
ok "Python dependencies installed"

# --- Deploy web client ---
info "Deploying web client"
rm -rf "$INSTALL_DIR/static"
cp -r "$SCRIPT_DIR/dist" "$INSTALL_DIR/static"
chown -R "$SERVICE_NAME:$SERVICE_NAME" "$INSTALL_DIR"
ok "Static files deployed ($(find "$INSTALL_DIR/static" -type f | wc -l) files)"

# --- Write configuration ---
info "Writing configuration"
cat > "$CONFIG_DIR/env" << ENVEOF
# SSHamrock relay configuration
# Generated by quickstart.sh on $(date -Iseconds)

RELAY_PUBLIC_HOST=$PUBLIC_HOST
RELAY_PUBLIC_PORT=$PUBLIC_PORT

RELAY_IDENTITY_PROVIDER=$IDP
RELAY_AUTH_REQUIRED=$AUTH_REQUIRED
ENVEOF

if [[ "$IDP" == "cloudflare-access" ]]; then
  cat >> "$CONFIG_DIR/env" << ENVEOF
RELAY_CF_TEAM_DOMAIN=$CF_TEAM
RELAY_CF_AUDIENCE=$CF_AUD
ENVEOF
elif [[ "$IDP" == "gcp-iap" ]]; then
  cat >> "$CONFIG_DIR/env" << ENVEOF
RELAY_IAP_AUDIENCE=$IAP_AUD
ENVEOF
fi

cat >> "$CONFIG_DIR/env" << ENVEOF

RELAY_TRUSTED_PROXIES=$TRUSTED_PROXIES
RELAY_LOG_SINKS=stderr
RELAY_STATIC_DIR=/opt/ssh-relay/static
ENVEOF

chmod 640 "$CONFIG_DIR/env"
chown root:"$SERVICE_NAME" "$CONFIG_DIR/env"
ok "Config written to $CONFIG_DIR/env"

# --- Write systemd service ---
info "Installing systemd service"
cat > "/etc/systemd/system/$SERVICE_NAME.service" << SVCEOF
[Unit]
Description=SSHamrock — browser-based SSH relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ssh-relay
Group=ssh-relay
EnvironmentFile=/etc/ssh-relay/env
WorkingDirectory=/opt/ssh-relay/src
ExecStart=/opt/ssh-relay/.venv/bin/uvicorn ssh_relay.app:app \\
    --host $BIND_IP --port 8080 \\
    --proxy-headers --forwarded-allow-ips "$TRUSTED_PROXIES"
Restart=always
RestartSec=2
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/ssh-relay
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME" --quiet
ok "Service started"

# --- Verify ---
sleep 2
if curl -sf "http://${BIND_IP}:8080/healthz" > /dev/null 2>&1; then
  ok "Health check passed"
else
  error "Service failed to start. Check: journalctl -u $SERVICE_NAME"
fi

echo ""
echo -e "${GREEN}${BOLD}  SSHamrock is running!${NC}"
echo ""
echo "  Relay listening on:  http://${BIND_IP}:8080"
echo "  Trusted proxies:     $TRUSTED_PROXIES"
echo "  Public hostname:     $PUBLIC_HOST"
echo ""
if [[ "$AUTH_REQUIRED" == "false" ]]; then
  echo -e "  ${RED}⚠  No authentication configured.${NC}"
  echo "  Point any reverse proxy at ${BIND_IP}:8080 to get started."
  echo "  For production, re-run with Cloudflare Access or Google IAP."
else
  echo "  Point your authenticating reverse proxy (Cloudflare Tunnel,"
  echo "  GCP IAP, nginx + oauth2-proxy, etc.) at ${BIND_IP}:8080."
fi
echo ""
echo "  Config:   $CONFIG_DIR/env"
echo "  Logs:     journalctl -u $SERVICE_NAME -f"
echo "  Restart:  systemctl restart $SERVICE_NAME"
echo ""
