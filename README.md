# SSHamrock

Browser-based SSH and SFTP — no extensions, no plugins, no VPN.

SSHamrock repackages Google's [Secure Shell](https://chromium.googlesource.com/apps/libapps/) Chrome extension as a standalone web page. It ships as a single server that serves the web client and proxies the SSH connections on the same port.

## Quick start

### Interactive (on an existing server)

```bash
git clone https://github.com/tehrhart/sshamrock.git
cd sshamrock
sudo bash quickstart.sh
```

The installer prompts for your public hostname and identity provider, then handles everything: Python venv, relay server, static files, systemd service. Point any reverse proxy at `localhost:8080` and you're live.

### Automated (cloud VM bootstrap)

For DigitalOcean, AWS, GCP, or any cloud provider that supports startup scripts:

1. Open [`sshamrock-bootstrap.sh`](sshamrock-bootstrap.sh)
2. Edit the settings at the top (hostname, Cloudflare team/audience, tunnel token)
3. Paste the entire script as your VM's **User Data** / startup script

The VM boots, installs all dependencies (including `cloudflared`), configures the relay, and comes up ready. Logs at `/var/log/sshamrock-init.log`.

This works with any cloud VM — DigitalOcean Droplets, AWS EC2, GCP Compute Engine, Azure VMs, etc.

## How it works

```
Browser (any Chromium)           SSHamrock Server              SSH Target
┌─────────────────────┐    ┌──────────────────────┐    ┌──────────────┐
│ hterm terminal       │    │ FastAPI (Python)      │    │              │
│ OpenSSH (WebAssembly)│─wss│  static web client    │    │   sshd       │
│ Relay client JS      │────│  /v4/connect → TCP    │────│              │
└─────────────────────┘    └──────────────────────┘    └──────────────┘
         ▲                          ▲
         └──── Authenticating reverse proxy ────┘
```

1. User visits the page and authenticates via your identity provider
2. The browser loads a full SSH client — hterm + OpenSSH compiled to WebAssembly
3. User picks a host and the browser opens a WebSocket to the same server
4. The relay bridges the WebSocket to a TCP connection to the target
5. All SSH encryption happens inside the browser — the relay sees only opaque ciphertext

## Authentication

SSHamrock itself doesn't authenticate users — it relies on a reverse proxy in front of it that handles SSO and passes identity headers. Any proxy that terminates auth and forwards to `localhost:8080` will work:

| Proxy | How it works |
|-------|-------------|
| **Cloudflare Access** | Cloudflare Tunnel → `localhost:8080`. JWT in `Cf-Access-Jwt-Assertion` header. First-class support via `RELAY_IDENTITY_PROVIDER=cloudflare-access`. |
| **Google IAP** | GCE/GKE backend → `localhost:8080`. JWT in `x-goog-iap-jwt-assertion` header. First-class support via `RELAY_IDENTITY_PROVIDER=gcp-iap`. |
| **nginx + oauth2-proxy** | oauth2-proxy handles SSO, nginx forwards to `localhost:8080`. Set `RELAY_IDENTITY_PROVIDER=none` and `RELAY_AUTH_REQUIRED=false` (proxy handles auth). |
| **Tailscale / ZeroTier** | Mesh VPN limits who can reach the server. Same config as above. |
| **Any other** | Anything that authenticates the user and proxies to `localhost:8080`. |

The quickstart installer prompts for Cloudflare or GCP IAP details. For other proxies, choose "none" and let your proxy handle authentication.

## Features

- **SSH and SFTP** in the browser — interactive terminal or command-line SFTP
- **SSH key management** — import private keys, encrypted at rest with a passphrase (PBKDF2 + AES-256-GCM via Web Crypto API). Browser password manager can save the passphrase.
- **Saved connections** — profiles persist in localStorage
- **URL shortcuts** — pre-populate with `?user=root&host=server.example.com`
- **Session resumption** — relay buffers data during brief disconnects (v4 protocol)
- **Single binary deployment** — one server, one port, one container

## Configuration

Config lives at `/etc/ssh-relay/env` (written by the installer). Key settings:

```bash
RELAY_PUBLIC_HOST=ssh.example.com   # Your public hostname
RELAY_PUBLIC_PORT=443               # Public-facing port
RELAY_IDENTITY_PROVIDER=cloudflare-access  # or gcp-iap, or none
RELAY_AUTH_REQUIRED=true
RELAY_STATIC_DIR=/opt/ssh-relay/static

# Target policy (optional) — restrict which hosts the relay can reach
RELAY_TARGET_ALLOWLIST=10.0.0.0/8   # Comma-separated CIDRs
```

Full configuration reference: [nassh-proxy docs](https://github.com/tehrhart/nassh-proxy).

## Security model

**Network:** The relay transports opaque SSH ciphertext — it cannot read passwords, keys, or session content. Loopback, link-local, and cloud metadata IPs are blocked by default.

**Browser:** A strict Content Security Policy (`script-src 'self'`) prevents XSS. SSH private keys are encrypted at rest with PBKDF2 + AES-256-GCM and only decrypted into the WASM filesystem during an active connection. Stale keys are wiped on startup (crash recovery). URL parameters are stripped from browser history.

**Headers:** COOP/COEP enable SharedArrayBuffer for the WASM worker. `Referrer-Policy: no-referrer` and `X-Content-Type-Options: nosniff` are set on all responses.

| Data | Visible to relay? |
|------|-------------------|
| Who connected (JWT identity) | Yes |
| Target host and port | Yes |
| SSH traffic content | No (encrypted) |
| Passwords typed in SSH | No (encrypted) |
| SSH private keys | No (never leave browser) |

## Building from source (optional)

The repo includes a pre-built `dist/` directory with everything needed. If you want to modify the web client or update the nassh components:

```bash
# Prerequisites: Node.js 18+, libapps checkout
bash build/assemble.sh /path/to/libapps
cp ~/.config/google-chrome/Default/Extensions/iodihamcpbpeioajjeobimgagajmlibd/*/plugin/wasm/ssh.wasm dist/plugin/wasm/
```

## Tech stack

| Component | Source |
|-----------|--------|
| Terminal | [hterm](https://chromium.googlesource.com/apps/libapps/+/HEAD/hterm/) |
| SSH client | [OpenSSH → WebAssembly](https://chromium.googlesource.com/apps/libapps/+/HEAD/ssh_client/) |
| Relay protocol | [Corp Relay v4](https://chromium.googlesource.com/apps/libapps/+/HEAD/nassh/docs/relay-protocol.md) |
| Relay server | [nassh-proxy](https://github.com/tehrhart/nassh-proxy) (FastAPI/Python) |
| Key encryption | Web Crypto API (PBKDF2 + AES-256-GCM) |

## License

The web client wrapper (this repo) is MIT licensed. The underlying nassh/hterm/ssh_client components are BSD licensed by The Chromium Authors.
