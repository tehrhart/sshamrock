# SSHamrock

Browser-based SSH and SFTP client — no extensions, no plugins, no VPN.

SSHamrock repackages Google's [Secure Shell](https://chromium.googlesource.com/apps/libapps/) Chrome extension as a standalone web page served by the same relay server that proxies the SSH connections. One container, one port, one DNS record.

## How it works

```
Browser (any Chromium)           SSHamrock Server              SSH Target
┌─────────────────────┐    ┌──────────────────────┐    ┌──────────────┐
│ hterm terminal       │    │ FastAPI (Python)      │    │              │
│ OpenSSH (WebAssembly)│─wss│  static web client    │    │   sshd       │
│ Relay client JS      │────│  /v4/connect → TCP    │────│              │
└─────────────────────┘    └──────────────────────┘    └──────────────┘
         ▲                          ▲
         └── Protected by Cloudflare Access / Google IAP ──┘
```

1. User visits `https://ssh.example.com` and authenticates via SSO (Cloudflare Access, Google IAP, etc.)
2. The page loads a full SSH client — hterm terminal emulator + OpenSSH compiled to WebAssembly
3. User picks a host, and the browser opens a WebSocket to the same server
4. The relay bridges the WebSocket to a TCP connection to the target SSH server
5. All SSH encryption happens inside the browser — the relay sees only opaque SSH traffic

## Quick start

### Prerequisites

- Linux server with Python 3.11+
- [nassh-proxy](https://github.com/tehrhart/nassh-proxy) relay server
- [libapps](https://chromium.googlesource.com/apps/libapps/) checkout (for the build step)
- Node.js 18+ (for rollup)
- The `ssh.wasm` binary (extracted from the [Secure Shell extension](https://chrome.google.com/webstore/detail/iodihamcpbpeioajjeobimgagajmlibd) or built from source)

### Build

```bash
git clone https://github.com/tehrhart/ssh-web-app.git
cd ssh-web-app

# Build the static web client from libapps sources
bash build/assemble.sh /path/to/libapps

# Copy the WASM binary (from an installed Chrome extension)
cp ~/.config/google-chrome/Default/Extensions/iodihamcpbpeioajjeobimgagajmlibd/*/plugin/wasm/ssh.wasm dist/plugin/wasm/
```

### Deploy

Copy the built `dist/` directory to the nassh-proxy relay server as a `static/` directory, and set `RELAY_STATIC_DIR=/path/to/static` in the relay's environment. The relay serves both the web client and the SSH WebSocket proxy on the same port.

```bash
# On the relay server
cp -r dist/ /opt/ssh-relay/static/
echo 'RELAY_STATIC_DIR=/opt/ssh-relay/static' >> /etc/ssh-relay/env
systemctl restart ssh-relay
```

That's it. Visit `https://your-relay-host/` in any Chromium browser.

For detailed deployment instructions (systemd, Docker, Cloudflare Tunnel), see [DEPLOY.md](DEPLOY.md).

### URL shortcuts

Pre-populate the connection form with URL parameters:

```
https://ssh.example.com/?user=root&host=server.internal.com&port=22&mode=ssh
```

## Security model

### Network security

- **Zero trust** — the relay and web client sit behind an identity-aware proxy (Cloudflare Access, Google IAP). Every request carries a verified JWT.
- **Same-origin** — the web client and relay are served from the same origin. No CORS. The browser automatically includes auth cookies on all requests.
- **End-to-end SSH encryption** — the relay transports opaque SSH traffic over WebSocket. It cannot read passwords, key material, or session content.
- **Target policy** — the relay restricts which hosts/ports can be reached (allowlist/denylist CIDRs). Loopback, link-local, and cloud metadata ranges are blocked by default.

### Browser security

- **Content Security Policy** — strict CSP (`script-src 'self'`) prevents XSS from exfiltrating SSH keys or injecting into terminal sessions.
- **SSH keys encrypted at rest** — private keys are encrypted with a user passphrase (PBKDF2 + AES-256-GCM) before storage. The browser's password manager can save the passphrase, protected by the OS keychain and biometrics.
- **Keys decrypted only during connection** — on connect, the key is decrypted into the WASM filesystem; on disconnect, it's removed.
- **Cross-Origin Isolation** — COOP/COEP headers enable `SharedArrayBuffer` for the WASM worker while preventing cross-origin attacks.
- **No referrer leakage** — `Referrer-Policy: no-referrer` and URL parameters are stripped from browser history after reading.

### What the relay can see

| Data | Visible to relay? |
|------|-------------------|
| Who connected (identity from JWT) | Yes |
| Target host and port | Yes |
| SSH traffic content | No (encrypted) |
| Passwords typed in SSH | No (encrypted) |
| SSH private keys | No (never leave browser) |

## Tech stack

| Component | Source |
|-----------|--------|
| Terminal emulator | [hterm](https://chromium.googlesource.com/apps/libapps/+/HEAD/hterm/) |
| SSH client | [OpenSSH compiled to WebAssembly](https://chromium.googlesource.com/apps/libapps/+/HEAD/ssh_client/) |
| Relay protocol | [Corp Relay v4](https://chromium.googlesource.com/apps/libapps/+/HEAD/nassh/docs/relay-protocol.md) |
| Relay server | [nassh-proxy](https://github.com/tehrhart/nassh-proxy) (FastAPI/Python) |
| Key encryption | Web Crypto API (PBKDF2 + AES-256-GCM) |

## License

The web client wrapper (this repo) is MIT licensed. The underlying nassh/hterm/ssh_client components are BSD licensed by The Chromium Authors.
