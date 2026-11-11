# G107 — Critical correction: show Owner update button only for a real published update

**Date:** 2026-11-10. **Status:** Programmer candidate staged, NOT INSTALLED. Draft PR #23; independent review and owner visual acceptance outstanding.

## Owner feedback and root cause

Owner approved G106 emoji colors but reported that the update button now remained visible all the time. **This is a G105 functional defect, not a harmless aesthetic difference:** G105 eliminated its repeat timer while retaining the `form.Add_Shown({ Start-RdcUpdateNoticePreview '1.6.0 RC2' })` unconditional Owner GUI callback. Its synthetic nonexistent RC2 offer therefore animated once and remained expanded indefinitely.

Owner's corrected requirement: keep the approved one-shot animation, button height, text placement and emoji colors, but **only show the button when a real published stable update is available**.

## Implementation

1. Removed the **entire Owner startup callback** that unconditionally called `Start-RdcUpdateNoticePreview '1.6.0 RC2'`. Normal Owner GUI now starts in its original **115px idle version footer**, with no button. The explicitly launched offline `-Preview` animation helper remains available for isolated UI inspection but is never called by normal Owner startup.
2. Existing `Update-RdcUpdateNoticePolling` now permits **read-only Owner passive release checks** even though Owner GUI runs with `-Preview` to block legacy Remote process/startup side effects. The Owner's existing 150ms WinForms timer calls it without blocking UI; first HTTP check begins approximately 25 seconds after GUI startup and subsequent checks at most once per hour. Checks are asynchronous with 8-second HTTP timeout, using the existing pinned-source verification route:
   - `https://api.github.com/repos/1rubass1/RDC-Relay/commits/stable`
   - `https://raw.githubusercontent.com/1rubass1/RDC-Relay/<verified-stable-commit-sha>/Source/update-manifest.json`
3. `Get-RdcAvailableVersionFromManifest` knows that **1.6.0 RC1 is a prerelease**: published stable 1.6.0 or newer is eligible; 1.5.18 and other earlier versions are not. Owner requires actual stable manifest payload entries `remote-window.ps1` and `update.ps1` before displaying any offer. Legacy stable-to-stable comparison remains strictly greater-than and unchanged.
4. A verified newer version triggers the **existing one-shot animation**. Same-version hourly checks do not restart it. If a subsequent manifest reports no newer stable version, `Hide-RdcUpdateNotice` returns the footer to idle. No fake RC2 or constant display.
5. **RC1 safety remains:** the candidate `rc1-candidate.json` continues with `autoUpdateEnabled=false` and `stableManifestEnabled=false` (no automatic installation, no candidate publication). `ownerUpdateDemoMode` still controls compact/read-only rendering, `VisualPreviewOnly` denies button activation, and the click handler refuses Owner/Preview. The accessible name and hover tooltip now say the published stable version is available but installation from RC1 is disabled. No update script, installer, Host, Remote, OAuth, tokens or installed app is invoked by a passive check.
6. **G106 semantic emoji colors unchanged.** No adjustment to menu/checkmark rendering or approved update-button geometry and text.

**Official channel observation:** independently fetched `1rubass1/RDC-Relay` `stable/Source/update-manifest.json` through the connected GitHub tool on 2026-11-10; it reports **version 1.5.18**, which is older than RC1. Thus the new Owner GUI should remain at its idle footer under the current published stable feed. This is not a live installed-GUI test.

## Verification on STARMER (bounded and isolated)

| Check | Result | Evidence |
| --- | --- | --- |
| `Tests/Test-V16OwnerRealUpdateNotice.ps1` | **23/23 PASS** | Parses production module and calls actual version/async polling/show/hide functions with mocked Github responses; verifies no artificial RC2 startup, stable 1.5.18 not offered, missing real payload not offered, published 1.6.0 final outranks RC1, exact SHA-pinned stable manifest URL, same-version no replay, newer replacement and older-version hide; legacy Preview remains network-free and legacy stable comparison unchanged |
| `Tests/Test-V16OwnerUpdateDemo.ps1` | **16/16 PASS** | Real offline WinForms sample still paints approved 25px footer/22px button and text; explicit one-shot preview helper only; production startup source asserts no fake RC2 |
| `Tests/Test-UpdateNoticeVersionRefresh.ps1` | **PASS** | Original stable updater's existing version-refresh and no-repeat behavior unchanged |
| `Tests/Test-V16OwnerBoundaryStatic.ps1` | **26/26 PASS** | Original RC1 ownership/updater/process safety boundary stays guarded |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **43/43 PASS**, exit 0 | Complete bounded source/compile/mock regression, plus G107 test |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS**, exit 0 | Actual standalone package embedding/extraction; no installation |
| `Scripts/build-rc1-full.ps1 -Build` | **21 SHA-verified package members** | Staged Setup and Portable; no launching application |

### G107 on STARMER Desktop

- `RDC-Relay-1.6.0-RC1-RealUpdateOnly-Setup.exe` SHA256 `E62F6E588B516DD8AED8F2188CBFB5C5786DFA86BEF5237DAFD8828C3B82FD4F`.
- `RDC-Relay-1.6.0-RC1-RealUpdateOnly-Portable.zip` SHA256 `8A0B807F18AB1643C03A8B386EAB20AF34E588099BC15BE72C1DB1ACE504CFD9`.

Previous flawed G106 `OneShotEmojiColors` Setup/Portable hash-checked and archived intact at `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G107_Superseded_OneShotEmojiColors/`. Stable v1.5.18 rollback Setup hash-verified and preserved.

## Remaining gates / nonclaims

**NOT CHECKED:** the actual installed Owner GUI's asynchronous network check on the owner's physical display, animation for a future genuinely published 1.6.0 release, interaction at different Windows DPI, and real RC1 update installation (intentionally disabled). A passive update **notification** is not permission to replace the candidate or current Remote; full Owner Host-aware update transaction remains an independent release gate.

**Do not** merge Draft PR #23, publish stable 1.6.0/update feed, run a candidate installation or interrupt the installed Host/Remote without the owner's separate authorization.
