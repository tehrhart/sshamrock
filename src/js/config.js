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
