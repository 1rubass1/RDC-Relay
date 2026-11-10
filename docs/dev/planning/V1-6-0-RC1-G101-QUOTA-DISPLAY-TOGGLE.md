# G101 — User-controlled call-quota display and automatic refresh

**Status:** Programmer candidate staged, NOT INSTALLED; independent review and owner GUI/OAuth acceptance outstanding.
**Date:** 2026-11-10. **Branch:** `feature/v1.6-host-gui-owner-pilot`, Draft PR #23.

## Owner acceptance intent

Replace the existing Account menu entry **«Подключить статистику вызовов…»** with the checkbox menu item **«Выводить остаток вызовов»**. Checking it enables automatic quota display/refresh. If the independent quota OAuth token is missing, this *explicit click* initiates the official browser PKCE consent. If the independent vault exists, reuse its stored grant. Unchecking disables further automatic updates. The checked state persists across GUI/Host restarts.

## Implementation boundaries

- `Source/remote-window.ps1`: reused the existing Account-menu `ToolStripMenuItem` with `CheckOnClick`, same position and styling. Click persists the opt-in setting; when checked and the quota DPAPI vault file is **absent**, spawns the existing isolated `rc1-quota-client.ps1 -Authorize` flow; if present, the tray poller reuses its grant. Clicking off immediately shows `Остаток вызовов: --%`, not a stale percentage. Failed setting writes revert the check state and show a fixed local warning.
- `Source/rc1-owner-gui.ps1`: loads persisted state during the Owner HELLO setup; the 15-second GUI timer rereads the preference before using the official 60-minute-expiring quota cache. When disabled it reads no quota cache and shows `--%`. The checkbox is enabled only in **MANAGED_OWNER_RC1**; fake/observed modes cannot promise refresh of an unverified account.
- Persisted opt-in is **not an OAuth token**: `%LOCALAPPDATA%\RDCRelayOwnerPilot\quota-display.opt-in` contains exactly ASCII `enabled-v1` (10 bytes) or does not exist. Missing, malformed or unreadable file means disabled. The GUI creates/replaces the marker atomically via same-directory staging, and deletes it on uncheck. Actual OAuth tokens remain in the pre-existing separate CurrentUser-DPAPI protected vault and are neither opened nor deleted by the GUI.
- `Source/rc1-tray-host.ps1`: its 15-second timer checks opt-in **before** reading the verified managed account and before scheduling a child request; when enabled, it launches **only `-Poll`** after the existing 30-minute schedule. It **never initiates browser consent automatically** anymore. The Host still requires `ActiveManagedAccount` to be a verified Host-owned Ready account. Disabled state resets the schedule, so the next enabled tick can refresh immediately.
- `Source/rc1-quota-client.ps1`: checks opt-in before accessing tokens or making any network request; checks again before opening the OAuth browser and before storing newly authorized credentials; checks again before saving any completed `who_am_i` result. An already in-flight request cannot publish a new cache value after opt-out if it sees the disabled setting at this final guard. It does **not** terminate the Remote or revoke the separate OAuth grant.
- No changes to device-agent credentials, Remote process, IPC host actions, UI geometry, update-notice animation, account-switch lifecycle, or stable 1.5.18 release. **No automatic OAuth login, network tests or live credential reads were performed by Programmer.**

## Verified isolated evidence on STARMER

| Check | Result | Notes |
| --- | --- | --- |
| `Tests/Test-V16QuotaDisplayToggle.ps1` | **33/33 PASS** | GUI/Host/client PowerShell parse; synthetic temp persisted marker; WinForms checkbox check/uncheck; malformed marker fail-closed; actual Host timer handler with intercepted `Start-Process`; actual Account menu handler with fake OAuth child and synthetic vault; real disabled CLI on disposable LOCALAPPDATA exits before network |
| `Tests/Test-V16QuotaOAuthPoll.ps1` | **37/37 PASS** | Synthetic PKCE, DPAPI, exact who_am_i scope, explicit browser-only policy |
| `Tests/Test-V16OwnerQuotaFooter.ps1` | **33/33 PASS** | Quota cache expiry/identity validation, footer source and UI positioning |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **40/40 PASS**, exit 0 | Bounded fake/static/compile suites including all prior Owner and G96 account-switch gates |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS**, exit 0 | Actual self-contained Setup inspection and extraction, **no installation** |
| `Scripts/build-rc1-full.ps1 -Build` | **21 SHA-checked package members** | Setup and Portable staged, **not launched** |

### STARMER Desktop

- `RDC-Relay-1.6.0-RC1-QuotaToggle-Setup.exe`: SHA256 `3D202C94AFCC120A1787D41A0DA3B1504FA88E43E83FA80C12300828F7AD805D`.
- `RDC-Relay-1.6.0-RC1-QuotaToggle-Portable.zip`: SHA256 `44368E162A367FE67990A54AE0E98D81E228A766D2E86AE95A32B0A7BA48FA46`.

Immediately superseded `UpdateButton1px` Setup/Portable were validated by SHA-256 and moved to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G101_Superseded_UpdateButton1px`. Stable rollback `RDC.Relay.Setup.v1.5.18.exe` SHA verified and preserved.

## Independent review and acceptance

**NOT CHECKED:** physical checkbox visibility with custom `ToolStripProfessionalRenderer`; actual browser OAuth when vault absent; live reuse or expiration/revocation of a damaged existing vault; actual first `who_am_i` synchronization; real on/off during in-flight network; GUI restart persistence across multiple Windows sessions; visuals on other DPI scales.

Behavioral caveats: existing vault **presence** avoids reauth on click even if its token is later unusable; a separate explicit recovery path may be needed for corrupted/expired grants. Browser consent already started before an uncheck may continue until its bounded callback timeout, but the client will not save a new grant or publish a quota snapshot after observing disabled state. The GUI displays an honest `--%` instead of freezing a possibly stale percentage. Automatic requests resume at the next 15-second Host timer and follow the existing 30-minute interval when checked.

**Next:** independent Reviewer examines UI/Host/client opt-in consistency, fail-closed behavior and packaging. Owner may install G101 at a planned safe time to visually verify the checkbox and OAuth tab; do not merge, publish updater or stable release yet.
