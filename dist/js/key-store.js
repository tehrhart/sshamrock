const STORE_PREFIX = 'sshkey:';
const PBKDF2_ITERATIONS = 600000;

async function deriveKey(passphrase, salt) {
  const enc = new TextEncoder();
  const baseKey = await crypto.subtle.importKey(
      'raw', enc.encode(passphrase), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
      {name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256'},
      baseKey,
      {name: 'AES-GCM', length: 256},
      false,
      ['encrypt', 'decrypt']);
}

export async function encryptAndStore(name, keyData, passphrase) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(passphrase, salt);
  const plaintext = typeof keyData === 'string'
      ? new TextEncoder().encode(keyData)
      : new Uint8Array(keyData);
  const ciphertext = await crypto.subtle.encrypt(
      {name: 'AES-GCM', iv}, key, plaintext);
  const blob = {
    salt: arrayToBase64(salt),
    iv: arrayToBase64(iv),
    data: arrayToBase64(new Uint8Array(ciphertext)),
  };
  localStorage.setItem(STORE_PREFIX + name, JSON.stringify(blob));
}

export async function decryptKey(name, passphrase) {
  const raw = localStorage.getItem(STORE_PREFIX + name);
  if (!raw) throw new Error(`Key "${name}" not found`);
  const blob = JSON.parse(raw);
  const salt = base64ToArray(blob.salt);
  const iv = base64ToArray(blob.iv);
  const ciphertext = base64ToArray(blob.data);
  const key = await deriveKey(passphrase, salt);
  const plaintext = await crypto.subtle.decrypt(
      {name: 'AES-GCM', iv}, key, ciphertext);
  return new Uint8Array(plaintext);
}

export function listStoredKeys() {
  const names = [];
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    if (k.startsWith(STORE_PREFIX)) {
      names.push(k.slice(STORE_PREFIX.length));
    }
  }
  return names.sort();
}

export function deleteStoredKey(name) {
  localStorage.removeItem(STORE_PREFIX + name);
}

function arrayToBase64(arr) {
  let bin = '';
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin);
}

function base64ToArray(b64) {
  const bin = atob(b64);
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return arr;
}
