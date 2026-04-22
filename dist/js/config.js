// Base domain for subdomain-based host extraction.
// If set, visiting host123.ssh.example.com extracts "host123" as the target.
// Set to null to disable subdomain extraction.
// Example: "ssh.secure.roche.com" — then host123.ssh.secure.roche.com → host123
export const BASE_DOMAIN = null;

export const RELAY_CONFIG = {
  proxyMode: 'corp-relay-v4@google.com',
  proxyHost: window.location.hostname,
  proxyPort: window.location.port || (window.location.protocol === 'https:' ? 443 : 80),
  useSSL: window.location.protocol === 'https:',
  relayMethod: 'direct',
};

export function relayOptionsString() {
  const c = RELAY_CONFIG;
  const parts = [
    `--proxy-mode=${c.proxyMode}`,
    `--proxy-host=${c.proxyHost}`,
    `--proxy-port=${c.proxyPort}`,
  ];
  if (c.useSSL) parts.push('--use-ssl');
  parts.push(`--relay-method=${c.relayMethod}`);
  return parts.join(' ');
}

export function extractSubdomainHost() {
  if (!BASE_DOMAIN) return null;
  const hostname = window.location.hostname;
  const suffix = '.' + BASE_DOMAIN.toLowerCase();
  if (!hostname.toLowerCase().endsWith(suffix)) return null;
  const sub = hostname.slice(0, -suffix.length);
  return sub || null;
}
