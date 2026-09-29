# Password Manager (AutoHotkey v2)

Standalone Alt+Q menu for usernames/passwords and links. It lives in this folder and does not use any other script in the repository.

## Requirements

- AutoHotkey v2.0+
- Windows 10/11

## Run

1. Double-click `PasswordManager.ahk` (or run it with AutoHotkey v2).
2. Create a master password (new vault) or enter it to unlock (existing vault).
3. The script stays in the tray. There is no main window until you open Config.
4. Press **Alt+Q** to open the menu.

The tray menu can **Lock** the vault (clears secrets from memory) and **Change master password**. Lock or Alt+Q while locked asks for the master password again.

## Menu

Alt+Q shows a popup at the cursor:

- **Submenus** nest more items
- **Login** items type a username and password into the window that was active before the menu
- **Link** items open the URL in the default browser
- **Config** is always the last item (it is not stored in the vault)

If a login has **Press Tab between username and password** enabled, it types the username, sends Tab, then types the password. If that option is off, it types the username and then the password with no Tab.

## Config

Open Config from the menu, or from the tray icon.

The config window lets you:

- Add / edit / delete **submenus**
- Add / edit / delete **login** items (username, password, Tab option)
- Add / edit / delete **link** items
- Reorder siblings with **Move up** / **Move down**
- **Nest** an item into the previous sibling submenu
- **Unnest** an item one level toward the root

New items go inside the selected submenu, or after the selected item. Changes are saved immediately to `vault.json` next to the script.

### Keyboard (tree focused)

| Key | Action |
| --- | --- |
| F2 | Edit |
| Insert | Add login |
| Shift+Insert | Add submenu |
| Ctrl+Insert | Add link |
| Delete | Delete |
| Alt+Up / Alt+Down | Reorder |
| Alt+Right | Nest |
| Alt+Left | Unnest |

Double-click an item to edit it. Right-click the tree for the same actions as the buttons.

**Typing delay (ms)** is the pause after activating the target window, and after Tab, before more keys are sent. Raise it if a site is slow to move focus.

## Storage

The vault is `password-manager/vault.json` (gitignored).

SHA-256 is a hash, not an encryption algorithm, so it cannot lock and later read a vault by itself. The script uses SHA-256 the way a password manager should:

1. You enter a **master password**
2. **PBKDF2-HMAC-SHA256** (210,000 iterations, random salt) stretches that password into keys
3. The full vault JSON is encrypted with **AES-256-CBC**
4. An **HMAC-SHA256** tag detects a wrong password or a tampered file

The file on disk only has public parameters (salt, IV, iteration count) plus ciphertext. Names, URLs, usernames, and passwords are inside the encrypted blob.

- The master password is not stored. If you forget it, the vault cannot be opened.
- Use at least 8 characters; a longer random passphrase is better.
- After unlock, secrets are in memory so Alt+Q can type them. Use **Lock** when you step away.
- An older DPAPI vault is upgraded the first time you set a master password.

This is a local filler, not a synced password manager. Keep a backup of `vault.json` if you care about the data. The backup is only useful if you also remember the master password.

## Assumptions

These defaults were chosen so the script can ship without a setup wizard:

- Hotkey is **Alt+Q** (change the `Hotkey("!q", ...)` line if you want another)
- Config is only on the root menu, always last
- Login fills the previously active window with `SendText`
- Links with no scheme get `https://`
- Master password encrypts the whole vault (PBKDF2-SHA256 + AES-256); there is no recovery
- Empty submenus show a disabled `(empty)` placeholder in the popup
