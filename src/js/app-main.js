import './chrome-shim.js';

import {lib} from '../libdot/index.js';
import {hterm} from '../hterm/index.js';
import {cleanupChromeSockets} from '../nassh/wassh/js/sockets.js';
import {
  getSyncStorage, loadMessages, loadWebFonts, localize,
  watchBackgroundColor,
} from '../nassh/js/nassh.js';
import {CommandInstance} from '../nassh/js/nassh_command_instance.js';
import {
  PreferenceManager, LocalPreferenceManager,
} from '../nassh/js/nassh_preference_manager.js';
import {getIndexeddbFileSystem} from '../nassh/js/nassh_fs.js';
import {
  encryptAndStore, decryptKey, listStoredKeys, deleteStoredKey,
} from './key-store.js';
import {relayOptionsString} from './config.js';

const storage = getSyncStorage();

globalThis.addEventListener('DOMContentLoaded', async () => {
  await cleanupChromeSockets();
  await loadMessages();

  const prefs = new PreferenceManager(storage);
  const localPrefs = new LocalPreferenceManager();
  await prefs.readStorage();
  await localPrefs.readStorage();

  const formWrapper = document.getElementById('connect-form-wrapper');
  const form = document.getElementById('connect-form');
  const terminalEl = document.getElementById('terminal');
  const usernameInput = document.getElementById('username');
  const hostnameInput = document.getElementById('hostname');
  const portInput = document.getElementById('port');
  const appSelect = document.getElementById('app-mode');
  const profileSelect = document.getElementById('profile-select');
  const deleteBtn = document.getElementById('delete-profile');
  const identitySelect = document.getElementById('identity-select');
  const importKeyInput = document.getElementById('import-key');
  const deleteKeyBtn = document.getElementById('delete-key');

  populateProfiles(prefs, profileSelect);
  refreshKeyList();

  // --- URL parameter pre-population ---
  // Supports: ?user=root&host=server.example.com&port=22&mode=sftp
  const params = new URLSearchParams(location.search);
  if (params.get('user')) usernameInput.value = params.get('user');
  if (params.get('host')) hostnameInput.value = params.get('host');
  if (params.get('port')) portInput.value = params.get('port');
  if (params.get('mode')) appSelect.value = params.get('mode');
  // Strip params from address bar and history after reading.
  if (location.search) {
    history.replaceState({}, '', location.pathname + location.hash);
  }

  // --- Profile selection ---
  profileSelect.addEventListener('change', () => {
    const id = profileSelect.value;
    if (!id) {
      usernameInput.value = '';
      hostnameInput.value = '';
      portInput.value = '22';
      appSelect.value = 'ssh';
      identitySelect.value = '';
      return;
    }
    const p = prefs.getProfile(id);
    usernameInput.value = p.get('username') || '';
    hostnameInput.value = p.get('hostname') || '';
    portInput.value = p.get('port') || 22;
    const app = p.get('app') || 'ssh';
    appSelect.value = (app === 'nasftp') ? 'sftp' : 'ssh';
    identitySelect.value = p.get('identity') || '';
  });

  deleteBtn.addEventListener('click', () => {
    const id = profileSelect.value;
    if (!id) return;
    const desc = profileSelect.selectedOptions[0]?.textContent;
    if (!confirm(`Delete profile "${desc}"?`)) return;
    prefs.removeProfile(id);
    populateProfiles(prefs, profileSelect);
    usernameInput.value = '';
    hostnameInput.value = '';
    portInput.value = '22';
    appSelect.value = 'ssh';
    identitySelect.value = '';
  });

  // Restore last-used profile (only if URL params didn't pre-populate).
  if (!params.get('user') && !params.get('host')) {
    const lastId = localPrefs.getString('connectDialog/lastProfileId');
    if (lastId) {
      profileSelect.value = lastId;
      profileSelect.dispatchEvent(new Event('change'));
    }
  }

  // --- Passphrase dialog (masked input, browser password manager) ---
  const passphraseDialog = document.getElementById('passphrase-dialog');
  const passphraseForm = document.getElementById('passphrase-form');
  const passphraseInput = document.getElementById('passphrase-input');
  const passphraseTitle = document.getElementById('passphrase-title');
  const passphraseMessage = document.getElementById('passphrase-message');
  const passphraseCancel = document.getElementById('passphrase-cancel');

  function askPassphrase(title, message) {
    return new Promise((resolve) => {
      passphraseTitle.textContent = title;
      passphraseMessage.textContent = message;
      passphraseInput.value = '';
      passphraseDialog.showModal();
      passphraseInput.focus();

      function onSubmit(e) {
        e.preventDefault();
        cleanup();
        passphraseDialog.close();
        resolve(passphraseInput.value);
      }
      function onCancel() {
        cleanup();
        passphraseDialog.close();
        resolve(null);
      }
      function cleanup() {
        passphraseForm.removeEventListener('submit', onSubmit);
        passphraseCancel.removeEventListener('click', onCancel);
      }
      passphraseForm.addEventListener('submit', onSubmit);
      passphraseCancel.addEventListener('click', onCancel);
    });
  }

  // --- SSH key management (encrypted at rest) ---
  importKeyInput.addEventListener('change', async () => {
    if (!importKeyInput.files.length) return;

    const passphrase = await askPassphrase(
        'Encrypt SSH key',
        'Choose a passphrase to protect this key. You\'ll need it each time you connect.');
    if (passphrase === null) {
      importKeyInput.value = '';
      return;
    }
    if (passphrase.length < 4) {
      alert('Passphrase must be at least 4 characters.');
      importKeyInput.value = '';
      return;
    }

    const imported = [];
    for (const file of importKeyInput.files) {
      if (file.name.endsWith('.pub') && !file.name.endsWith('-cert.pub')) {
        continue;
      }
      const data = await file.arrayBuffer();
      await encryptAndStore(file.name, data, passphrase);
      imported.push(file.name);
    }

    importKeyInput.value = '';
    refreshKeyList();
    if (imported.length) {
      identitySelect.value = imported[0];
    }
  });

  deleteKeyBtn.addEventListener('click', () => {
    const name = identitySelect.value;
    if (!name) return;
    if (!confirm(`Delete key "${name}"?`)) return;
    deleteStoredKey(name);
    refreshKeyList();
  });

  function refreshKeyList() {
    const names = listStoredKeys();
    const current = identitySelect.value;
    identitySelect.innerHTML = '<option value="">Password authentication</option>';
    for (const name of names) {
      const opt = document.createElement('option');
      opt.value = name;
      opt.textContent = name;
      identitySelect.appendChild(opt);
    }
    if (current) identitySelect.value = current;
  }

  // --- Form submission ---
  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    const username = usernameInput.value.trim();
    const hostname = hostnameInput.value.trim();
    const port = parseInt(portInput.value, 10) || 22;
    const app = appSelect.value;
    const identity = identitySelect.value;

    if (!username || !hostname) {
      alert('Username and hostname are required.');
      return;
    }

    // If a key is selected, decrypt it and inject into the nassh filesystem.
    if (identity) {
      const passphrase = await askPassphrase(
          'Unlock SSH key',
          `Enter passphrase for "${identity}"`);
      if (passphrase === null) return;
      let keyData;
      try {
        keyData = await decryptKey(identity, passphrase);
      } catch {
        alert('Wrong passphrase or corrupted key.');
        return;
      }
      const fs = await getIndexeddbFileSystem();
      await fs.createDirectory('/.ssh');
      await fs.createDirectory('/.ssh/identity');
      await fs.writeFile(`/.ssh/identity/${identity}`, keyData.buffer);
    }

    // Save or update profile.
    const desc = `${username}@${hostname}`;
    let profileId = profileSelect.value;
    let profile;
    if (profileId) {
      profile = prefs.getProfile(profileId);
    } else {
      profile = prefs.createProfile();
      profileId = profile.id;
    }
    await profile.set('description', desc);
    await profile.set('username', username);
    await profile.set('hostname', hostname);
    await profile.set('port', port);
    await profile.set('app', app === 'sftp' ? 'nasftp' : 'ssh');
    await profile.set('nassh-options', relayOptionsString());
    await profile.set('identity', identity);

    await localPrefs.set('connectDialog/lastProfileId', profileId);

    populateProfiles(prefs, profileSelect);

    // Hide form, show terminal.
    formWrapper.style.display = 'none';
    terminalEl.style.display = 'block';

    startTerminal(terminalEl, profileId, identity, storage, formWrapper);
  });

  // If URL hash has a profile-id, connect directly.
  const hash = location.hash.slice(1);
  if (hash.startsWith('profile-id:')) {
    const profileId = hash.split(':')[1];
    try {
      prefs.getProfile(profileId);
      formWrapper.style.display = 'none';
      terminalEl.style.display = 'block';
      startTerminal(terminalEl, profileId, null, storage, formWrapper);
    } catch {
      // Profile not found, show form.
    }
  }
});

function startTerminal(terminalEl, profileId, identityName, storage, formWrapper) {
  const terminal = new hterm.Terminal({profileId, storage});
  terminal.alwaysUseLegacyPasting = true;
  terminal.decorate(terminalEl);
  terminal.installKeyboard();

  terminal.onTerminalReady = () => {
    watchBackgroundColor(terminal.getPrefs());
    loadWebFonts(terminal.getDocument());

    const argstr = `profile-id:${profileId}`;
    const nasshCommand = new CommandInstance({
      io: terminal.io,
      syncStorage: storage,
      args: [argstr],
      environment: {},
      connectPage: '',
      onExit: async (code) => {
        // Clean up decrypted key from the nassh filesystem.
        if (identityName) {
          try {
            const fs = await getIndexeddbFileSystem();
            await fs.removeFile(`/.ssh/identity/${identityName}`);
          } catch { /* already gone */ }
        }
        terminal.uninstallKeyboard();
        terminalEl.style.display = 'none';
        formWrapper.style.display = '';
        terminalEl.innerHTML = '';
      },
    });
    nasshCommand.run();
  };

  terminal.contextMenu.setItems([
    {name: localize('TERMINAL_CLEAR_MENU_LABEL') || 'Clear',
     action: () => terminal.wipeContents()},
    {name: localize('TERMINAL_RESET_MENU_LABEL') || 'Reset',
     action: () => terminal.reset()},
  ]);
}

function populateProfiles(prefs, select) {
  const ids = prefs.get('profile-ids') || [];
  const currentVal = select.value;
  select.innerHTML = '<option value="">New connection</option>';
  for (const id of ids) {
    const p = prefs.getProfile(id);
    const desc = p.get('description') || id;
    const opt = document.createElement('option');
    opt.value = id;
    opt.textContent = desc;
    select.appendChild(opt);
  }
  if (currentVal) select.value = currentVal;
}
