# G102 — Correct quota checkbox default to ON; preserve original auto-sync

**Date:** 2026-11-10. **Status:** Programmer candidate staged, independent review and owner acceptance outstanding; **NOT INSTALLED**.

## Owner correction to G101

Owner explicitly clarified **before installing G101**: the new Account-menu checkbox **«Выводить остаток вызовов»** must start **checked**. All previously existing quota behavior (Host-managed automatic OAuth connection when necessary and periodic updates) must continue **without requiring a first click**. Unchecking is only a user opt-out. G101 erroneously defaulted to OFF and disabled the original Host automatic OAuth. G102 supersedes G101.

## Corrected behavior

- **Default / first launch:** checked; Host follows original 15-second timer, only after verified `ActiveManagedAccount` from an actual Host-owned Ready Remote; if the independent quota grant is absent or the official cache belongs to a different account, the Host may start the existing browser PKCE authorization **once per account per Host run**. Subsequent official `who_am_i` refreshes are scheduled every 30 minutes, exactly as before G101.
- **Uncheck:** immediately shows `Остаток вызовов: --%`, prevents new quota polls/browser requests and stores an **explicit** user opt-out. An already running quota client rechecks before cache publication, so it does not publish after observing the disabled flag. No Remote or account device credential action.
- **Recheck:** clears the opt-out marker and restores automatic Host-managed authorization/polling at the **next 15-second timer tick**. If no independent quota token exists, the Host opens the provider login; it is intentionally **not** launched separately by the GUI, avoiding duplicate OAuth tabs. Disabling observed by Host re-arms the one-shot authorization attempt.
- **Restart:** default remains checked if never explicitly disabled. Explicit disabled state remains unchecked across GUI/Host restarts.
- **Preference representation:** same compatibility path `%LOCALAPPDATA%\RDCRelayOwnerPilot\quota-display.opt-in` as G101, but **absence now means ON**; the only new persisted content is ASCII `disabled-v1` (11 bytes). The transient G101 `enabled-v1` (10 bytes) is also understood as ON for compatibility. Invalid/unreadable/reparse-marked files fail closed (OFF). The authenticated OAuth vault remains separately DPAPI-encrypted and is never deleted by toggling the checkbox.
- **Scope:** existing Owner-only menu item, client pre- and post-request checks, existing six-row display, update notice and all other RC1 features unchanged. Adopted/fake mode still does not present an active Owner quota control. No new Host IPC verb or Remote process changes.
- **Known limitations:** real provider OAuth and visual rendering not verified. Browser consent is subject to the 15-second Host tick; damaged but existing OAuth credentials may require an explicit later recovery flow. If OFF and then ON both happen between Host timer ticks, an earlier one-shot account attempt may remain latched until Host restarts; this is a noncritical trial edge requiring Reviewer attention.

## Evidence on STARMER (offline, 2026-11-10)

| Check | Result | Focus |
| --- | --- | --- |
| `Tests/Test-V16QuotaDisplayToggle.ps1` | **31/31 PASS** | Real menu click handler; default checked without file, exact explicit OFF marker, ON removal, migration, malformed-file failure, actual Host timer mocked auto browser / poll / OFF / re-ON, synthetic OAuth client OFF |
| `Tests/Test-V16QuotaOAuthPoll.ps1` | **37/37 PASS** | Original automatic PKCE grant guarded by managed account and explicit OFF; synthetic DPAPI and who_am_i |
| `Tests/Test-V16OwnerQuotaFooter.ps1` | **33/33 PASS** | Unchanged quota footer, expiry and 0% handling |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **40/40 PASS** | Whole bounded compile/mock regression |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS** | Embedded Setup source manifest/extraction; no installation |
| `Scripts/build-rc1-full.ps1 -Build` | **21 SHA-verified package members** | Setup + Portable staged, never executed |

### Desktop STARMER (supersedes G101)

- `RDC-Relay-1.6.0-RC1-QuotaDefaultOn-Setup.exe` SHA256 `E5746BFEFEEC22E13FDCF423FD93D980C0051F0A2C305A29CEC7E62CB74B55E0`.
- `RDC-Relay-1.6.0-RC1-QuotaDefaultOn-Portable.zip` SHA256 `6B7C7B7775A2F8FC6706C81CF3E6F72213E2B27A948506959D474B10BD1698CF`.

G101 `QuotaToggle` pair moved after SHA checks to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G102_Superseded_QuotaToggle/`. Stable 1.5.18 rollback hash checked and preserved. No installed RC1, real Host/GUI/Remote, OAuth tokens or credentials were altered.

## Gate

**Not checked:** live first-start automatic browser, successful provider synchronization, visual checkmark after install, real OFF/ON during in-flight network and across restarts. Independent Reviewer to verify and owner to install/test. No PR merge, public updater or stable release without separate approval.
