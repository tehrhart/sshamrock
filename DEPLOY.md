# Quick Deploy — SSH Web Client + Relay

Single-server deployment: the relay serves both the SSH WebSocket proxy
and the static web client on one port behind a Cloudflare Tunnel.

## Prerequisites

- Linux server (Ubuntu 22.04+ / Debian 12+) with Python 3.11+
- Cloudflare Tunnel (`cloudflared`) forwarding to `localhost:8080`
- Cloudflare Access application protecting the tunnel's public hostname
- The `libapps` repo checked out (for building the web client)
- Node.js 18+ (for the rollup build step)

## Build the web client (on your dev machine)

```bash
cd SSH-web-app
bash build/assemble.sh /path/to/libapps
# If ssh.wasm is missing, extract from Chrome extension:
cp ~/.config/google-chrome/Default/Extensions/iodihamcpbpeioajjeobimgagajmlibd/*/plugin/wasm/ssh.wasm dist/plugin/wasm/
```

## Deploy (from your dev machine to the server)

```bash
SERVER=root@your-server

# Package
tar czf /tmp/ssh-deploy.tar.gz --exclude='.git' --exclude='__pycache__' \
    --exclude='.venv' -C /path/to/SSH-proxy .
tar czf /tmp/ssh-webclient.tar.gz -C SSH-web-app/dist .

# Upload
scp /tmp/ssh-deploy.tar.gz /tmp/ssh-webclient.tar.gz $SERVER:/tmp/

# Install (SSH in and run)
ssh $SERVER bash -s << 'EOF'
set -euo pipefail

# Create user and directories (first time only)
id ssh-relay &>/dev/null || useradd -r -s /sbin/nologin ssh-relay
mkdir -p /opt/ssh-relay/{src,static} /etc/ssh-relay /var/log/ssh-relay
chown ssh-relay:ssh-relay /opt/ssh-relay /var/log/ssh-relay

# Deploy code
rm -rf /opt/ssh-relay/src/*
tar xzf /tmp/ssh-deploy.tar.gz -C /opt/ssh-relay/src/
rm -rf /opt/ssh-relay/static/*
tar xzf /tmp/ssh-webclient.tar.gz -C /opt/ssh-relay/static/
chown -R ssh-relay:ssh-relay /opt/ssh-relay/

# Create venv and install (first time or after dependency changes)
python3 -m venv /opt/ssh-relay/.venv
/opt/ssh-relay/.venv/bin/pip install --no-cache-dir -e /opt/ssh-relay/src/

# Clean up
rm /tmp/ssh-deploy.tar.gz /tmp/ssh-webclient.tar.gz
EOF
```

## Configure (first time only)

Write `/etc/ssh-relay/env`:

```ini
RELAY_PUBLIC_HOST=ssh.example.com
RELAY_PUBLIC_PORT=443

RELAY_IDENTITY_PROVIDER=cloudflare-access
RELAY_AUTH_REQUIRED=true
RELAY_CF_TEAM_DOMAIN=yourteam
RELAY_CF_AUDIENCE=your-cf-access-audience-tag

RELAY_LOG_SINKS=stderr
RELAY_STATIC_DIR=/opt/ssh-relay/static
```

Write `/etc/systemd/system/ssh-relay.service`:

```ini
[Unit]
Description=SSH Web Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ssh-relay
Group=ssh-relay
EnvironmentFile=/etc/ssh-relay/env
WorkingDirectory=/opt/ssh-relay/src
ExecStart=/opt/ssh-relay/.venv/bin/uvicorn ssh_relay.app:app \
    --host 127.0.0.1 --port 8080 \
    --proxy-headers --forwarded-allow-ips "127.0.0.1"
Restart=always
RestartSec=2
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/ssh-relay

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now ssh-relay
```

## Update (subsequent deploys)

The fastest path — rebuild, upload, restart:

```bash
# On dev machine:
tar czf /tmp/ssh-deploy.tar.gz --exclude='.git' --exclude='__pycache__' \
    --exclude='.venv' -C /path/to/SSH-proxy .
tar czf /tmp/ssh-webclient.tar.gz -C SSH-web-app/dist .
scp /tmp/ssh-deploy.tar.gz /tmp/ssh-webclient.tar.gz $SERVER:/tmp/

# On server:
ssh $SERVER 'systemctl stop ssh-relay && \
  rm -rf /opt/ssh-relay/src/* && tar xzf /tmp/ssh-deploy.tar.gz -C /opt/ssh-relay/src/ && \
  rm -rf /opt/ssh-relay/static/* && tar xzf /tmp/ssh-webclient.tar.gz -C /opt/ssh-relay/static/ && \
  chown -R ssh-relay:ssh-relay /opt/ssh-relay/ && \
  /opt/ssh-relay/.venv/bin/pip install --no-cache-dir -e /opt/ssh-relay/src/ -q && \
  systemctl start ssh-relay && \
  rm /tmp/ssh-deploy.tar.gz /tmp/ssh-webclient.tar.gz && \
  echo "Deployed. Status:" && systemctl status ssh-relay --no-pager | head -5'
```

## Verify

```bash
# Health check
curl -s http://localhost:8080/healthz

# Web client loads
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/

# COOP/COEP headers set
curl -sI http://localhost:8080/ | grep cross-origin

# WASM binary accessible
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/plugin/wasm/ssh.wasm
```
