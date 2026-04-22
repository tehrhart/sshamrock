// Copyright 2026 The ChromiumOS Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/**
 * @fileoverview Read Chrome managed-storage policy and expose it as relay
 * defaults. Admins can set these via the `3rdparty.extensions.<ID>` policy
 * keys on managed browsers (see `managed_schema.json`). Values are applied as
 * lowest-priority defaults; the user's explicit options always win.
 */

/** @type {!Object<string, *>} */
let cachedPolicy = {};

/**
 * Load the managed policy from chrome.storage.managed once at startup, and
 * listen for live updates from the policy service.
 *
 * @return {!Promise<void>}
 */
export async function initManagedPolicy() {
  if (!globalThis.chrome?.storage?.managed) {
    return;
  }

  try {
    cachedPolicy = await new Promise((resolve) => {
      chrome.storage.managed.get(null, (items) => {
        if (chrome.runtime.lastError) {
          resolve({});
          return;
        }
        resolve(items || {});
      });
    });
  } catch (e) {
    cachedPolicy = {};
  }

  if (chrome.storage.onChanged) {
    chrome.storage.onChanged.addListener((changes, areaName) => {
      if (areaName !== 'managed') {
        return;
      }
      for (const [key, {newValue}] of Object.entries(changes)) {
        if (newValue === undefined) {
          delete cachedPolicy[key];
        } else {
          cachedPolicy[key] = newValue;
        }
      }
    });
  }
}

/**
 * Return the raw managed-policy object. Empty if no policy is set or the
 * extension is not managed.
 *
 * @return {!Object<string, *>}
 */
export function getManagedPolicy() {
  return cachedPolicy;
}

/**
 * Translate the managed-policy schema into an option map suitable for merging
 * into the relay option set produced by postProcessOptions(). Only keys that
 * the admin has actually set appear in the returned object.
 *
 * @return {!Object<string, *>}
 */
export function managedDefaultsAsOptions() {
  const rv = {};
  const p = cachedPolicy;

  if (typeof p.DefaultRelayServer === 'string' && p.DefaultRelayServer) {
    rv['--proxy-host'] = p.DefaultRelayServer;
  }
  if (Number.isInteger(p.DefaultRelayServerPort)) {
    rv['--proxy-port'] = String(p.DefaultRelayServerPort);
  }
  if (typeof p.DefaultRelayServerUseSsl === 'boolean') {
    rv['--use-ssl'] = p.DefaultRelayServerUseSsl;
  }
  if (typeof p.DefaultRelayServerProxyMode === 'string' &&
      p.DefaultRelayServerProxyMode) {
    rv['--proxy-mode'] = p.DefaultRelayServerProxyMode;
  }

  return rv;
}

/**
 * Free-form options string set by the admin, or '' if unset. Callers that
 * render a Relay Server Options field use this as a placeholder/default.
 *
 * @return {string}
 */
export function managedDefaultsAsOptionsString() {
  const s = cachedPolicy.DefaultRelayServerOptions;
  return (typeof s === 'string') ? s : '';
}
