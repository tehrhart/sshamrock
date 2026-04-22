# Manual Deployment Reference

For most deployments, use `quickstart.sh` (interactive) or `sshamrock-bootstrap.sh` (automated). This document covers manual setup for custom environments.

## Prerequisites

- Linux server (Ubuntu 22.04+ / Debian 12+) with Python 3.11+
- An authenticating reverse proxy forwarding to port `8080` (Cloudflare Tunnel, GCP IAP, nginx, etc.)

## Install

```bash
# Create user and directories
useradd -r -s /sbin/nologin ssh-relay
mkdir -p /opt/ssh-relay /etc/ssh-relay /var/log/sshamrock
chown ssh-relay:ssh-relay /var/log/sshamrock

# Clone relay server
git clone https://github.com/tehrhart/nassh-proxy.git /opt/ssh-relay/src

# Create venv and install
python3 -m venv /opt/ssh-relay/.venv
/opt/ssh-relay/.venv/bin/pip install --no-cache-dir -e /opt/ssh-relay/src/

# Deploy web client (from the sshamrock repo)
cp -r dist/ /opt/ssh-relay/static/
chown -R ssh-relay:ssh-relay /opt/ssh-relay/
```

## Configure

Write `/etc/ssh-relay/env`:

```ini
RELAY_PUBLIC_HOST=ssh.example.com
RELAY_PUBLIC_PORT=443

RELAY_IDENTITY_PROVIDER=cloudflare-access
RELAY_AUTH_REQUIRED=true
RELAY_CF_TEAM_DOMAIN=yourteam
RELAY_CF_AUDIENCE=your-audience-tag

RELAY_LOG_SINKS=stderr,file
RELAY_LOG_FILE_PATH=/var/log/sshamrock/audit.jsonl
RELAY_LOG_FILE_MAX_BYTES=104857600
RELAY_LOG_FILE_BACKUP_COUNT=10
RELAY_STATIC_DIR=/opt/ssh-relay/static
```

```bash
chmod 640 /etc/ssh-relay/env
chown root:ssh-relay /etc/ssh-relay/env
```

## Systemd service

Write `/etc/systemd/system/ssh-relay.service`:

```ini
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
ExecStart=/opt/ssh-relay/.venv/bin/uvicorn ssh_relay.app:app \
    --host 0.0.0.0 --port 8080 \
    --proxy-headers --forwarded-allow-ips "*"
Restart=always
RestartSec=2
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/sshamrock
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now ssh-relay
```

## Update (subsequent deploys)

```bash
# Stop, update relay + web client, restart
systemctl stop ssh-relay
(cd /opt/ssh-relay/src && git pull)
/opt/ssh-relay/.venv/bin/pip install --no-cache-dir -e /opt/ssh-relay/src/ -q
rm -rf /opt/ssh-relay/static && cp -r dist/ /opt/ssh-relay/static/
chown -R ssh-relay:ssh-relay /opt/ssh-relay/
systemctl start ssh-relay
```

## Verify

```bash
curl -s http://localhost:8080/healthz                                    # {"ok": true}
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/            # 200
curl -sI http://localhost:8080/ | grep content-security-policy           # CSP present
curl -sI http://localhost:8080/ | grep cross-origin                      # COOP/COEP present
```
