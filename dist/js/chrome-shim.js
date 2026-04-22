// Minimal stubs for Chrome extension APIs not available in web context.
// Most nassh code already guards with optional chaining; only these crash.
if (!globalThis.chrome) globalThis.chrome = {};
if (!chrome.runtime) chrome.runtime = {};
if (!chrome.runtime.sendMessage) {
  chrome.runtime.sendMessage = (...args) => {
    const cb = args[args.length - 1];
    if (typeof cb === 'function') setTimeout(cb, 0, {});
    return Promise.resolve({});
  };
}
if (!chrome.tabs) chrome.tabs = {};
if (!chrome.tabs.getCurrent) {
  chrome.tabs.getCurrent = (cb) => cb({id: 0});
}
