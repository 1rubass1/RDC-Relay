# G110 — Account-switch web helper opens official settings page

**Date:** 2026-11-11. **Status:** Programmer candidate; independent review and visual acceptance pending. No installed app or Remote changed.

## Owner correction

The G109 Owner account-switch confirmation has a helper button **«Выйти из аккаунта»**, deliberately opening a browser without executing local Host logout or account switching. The owner supplied the precise desired target:

`https://mcp.desktopcommander.app/settings`

G109 opened the site's root `https://mcp.desktopcommander.app/`. G110 changes **only this helper button's destination** to the owner's exact `/settings` path. Other root URLs in the app, including unrelated Account commands, stay unchanged. This button still does **not** automatically sign out; user signs out using the website itself.

## Implementation

- `Source/remote-window.ps1`: the `Start-Process -FilePath` inside `rc1-account-switch-signout-website` click handler now points to the exact official HTTPS `/settings` URL.
- `Tests/Test-V16OwnerAccountSwitchDialog.ps1`: fake `Start-Process` click verifies exact URL with `/settings`, one launch, dialog result remains None, and existing Host `SWITCH_ACCOUNT` gate remains unchanged.
- No changes to G109 native warning icon, text, typography, button geometry, No/Yes, Host, Remote or account credentials.

**Evidence:** isolated production dialog and mocked browser-click test **23/23 PASS**; complete RC1 safe regression **44/44 PASS**, exit 0; standalone Setup manifest and disposable extraction test **19/19 PASS**, exit 0; full RC1 build **21 SHA-verified payload members**, no installation.

### STARMER Desktop G110 candidate

- `RDC-Relay-1.6.0-RC1-AccountSettings-Setup.exe`, SHA256 `E7BF717C641986E1DE7C3EBBDF373B8041F5BD4FE23ABE0203ED520035124BA7`.
- `RDC-Relay-1.6.0-RC1-AccountSettings-Portable.zip`, SHA256 `A27CB85065C77FCB91844DF726FA64F99CBCDF967E55FF7BC6442F62DEC0ACF5`.

Copied to Desktop and verified byte-exact. Previous G109 `AccountSwitchWarning` pair hash-checked and archived intact in `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G110_Superseded_AccountSwitchWarning/`. Stable rollback `RDC.Relay.Setup.v1.5.18.exe` SHA checked and preserved.

**Not checked:** browser actually reaching the settings page under a live logged-in session, user sign-out action, installed GUI at owner's DPI, live Host account switch. Do not test these by changing the installed app or using real credentials.
