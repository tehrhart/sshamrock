#!/bin/bash
set -euo pipefail
exec > /var/log/sshamrock-init.log 2>&1

# ============================================================
#  SSHamrock — Non-interactive bootstrap script
#
#  For cloud VMs (DigitalOcean User Data, AWS EC2 User Data, etc.)
#  Edit the settings below, then paste as the VM startup script.
#
#  Logs: /var/log/sshamrock-init.log
# ============================================================

# --- Your settings (edit these) ---
export SSHAMROCK_HOST="sshamrock.mycompany.com"    # Your public hostname
export SSHAMROCK_PORT="443"
export SSHAMROCK_IDP="cloudflare"                  # cloudflare | gcp-iap | none
export SSHAMROCK_CF_TEAM="CHANGE_ME"               # Cloudflare team domain
export SSHAMROCK_CF_AUD="CHANGE_ME"                # Cloudflare Access audience tag
CLOUDFLARED_TOKEN="CHANGE_ME"                      # Cloudflare Tunnel token

# Network binding — for remote cloudflared load balancers, set BIND_IP
# to a LAN address (or 0.0.0.0) and TRUSTED_PROXIES to the cloudflared IPs.
export SSHAMROCK_BIND_IP="127.0.0.1"              # 127.0.0.1 | 0.0.0.0 | specific LAN IP
export SSHAMROCK_TRUSTED_PROXIES="127.0.0.1"      # Comma-separated IPs/CIDRs of upstream proxies

# For GCP IAP instead, use:
# export SSHAMROCK_IDP="gcp-iap"
# export SSHAMROCK_IAP_AUD="/projects/123/global/backendServices/456"

# --- Validate placeholders were changed ---
for var in SSHAMROCK_HOST SSHAMROCK_CF_TEAM SSHAMROCK_CF_AUD CLOUDFLARED_TOKEN; do
    val="${!var}"
    if [[ "$val" == "CHANGE_ME" || "$val" == *"TODO"* || "$val" == *"###"* ]]; then
        echo "ERROR: $var is still set to a placeholder value: $val" >&2
        echo "Edit this script and replace all placeholder values before running." >&2
        exit 1
    fi
done

# --- Install system dependencies ---
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    python3 python3-venv git curl

# --- Install cloudflared ---
mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
    | tee /etc/apt/sources.list.d/cloudflared.list
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cloudflared

cloudflared service install "$CLOUDFLARED_TOKEN"

# --- Install SSHamrock ---
git clone https://github.com/tehrhart/sshamrock.git /opt/sshamrock-installer
cd /opt/sshamrock-installer
bash quickstart.sh

echo "SSHamrock install complete at $(date)"
