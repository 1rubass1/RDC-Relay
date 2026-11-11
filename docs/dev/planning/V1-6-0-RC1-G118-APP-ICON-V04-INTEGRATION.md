# G118 — Owner-approved primary application icon v04 integration

**2026-11-11. Programmer candidate. NOT A PUBLIC RELEASE.**

## Request and scope

Owner selected the finished graphic kit *RDC Relay - Значок 04* on STARMER Desktop for application and shortcut icons. Owner also explicitly requested that the test Setup.exe **itself** display the new native Windows icon. Tray-state icon and tray logic work is concurrent and explicitly **out of scope**.

Selected Windows ICO has 18 PNG-backed RGBA dimensions: 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 120, 128, 144, 192, 256 px.

**Approved ICO SHA-256:** 6421F60D00030F21F958B81118B36ACCF08155CE2A887EEEB329B60044A06FA8

## Implementation

- Assets/RDCRelay.ico and Source/RDCRelay.ico copied from owner-selected source after strict hash validation. Source/update-manifest.json updated only for the icon SHA.
- Scripts/build-rc1-full.ps1 validates both source icon hashes and passes **csc /win32icon** for private Setup.exe **and** Launcher.exe. Its manifest already packages the same runtime ICO, and the existing safe owner shortcut activation points to this release/Source/RDCRelay.ico.
- Scripts/build-release.ps1 retains /win32icon for public Setup and Portable launcher, but no longer calls Assets/build-icon.ps1, which would regenerate the superseded artwork. New strict preflight checks refuse an unapproved/mismatched icon. Public stable build was **not** invoked.
- Tests/Test-V16AppIconV04.ps1 checks all 18 frames, source asset SHA-256, the icon manifest entry, GUI/shortcut references and Win32-extracted native EXE icons. Setup and Launcher native icons match the approved 32px PNG frame **pixel for pixel**. The RC1 builder runs this safety test before packaging and aborts on failure.
- No source or installer mutations to tray runtime/logic, tray icon statuses, animation, Host lifecycle, credentials, installed Windows registry or user shortcut. Concurrent Designer's uncommitted work in COORDINATION/BOARD.md and docs/dev/design/icon-concepts-2026-11-11 was left untouched and is not included in G118 commit.

## Verification and candidate

- Native icon + static checks: **10/10 PASS**.
- Standalone private Setup extraction and validation: **19/19 PASS**.
- Full safe regression Tests/Invoke-V16Rc1SafeRegression.ps1: **50/50 PASS**, exit 0; includes the new icon regression test.
- Private full RC1 built without installing: 21 SHA-verified payload members.
- Current STARMER Desktop **RDC-Relay-1.6.0-RC1-AppIcon04-Setup.exe**, SHA256: F77B50AE904A47DFB1FACF82729CDC890B5CCE7F4131DC5E154F27D3164313DC
- Current STARMER Desktop **RDC-Relay-1.6.0-RC1-AppIcon04-Portable.zip**, SHA256: 8BB05C78CEB44F6509D4001081D8E645B33EB1FF1CEC01327BFD3FE2703E2333
- Earlier G117 TextPaneFloor Setup/Portable hash-checked and archived at Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G118_Superseded_TextPaneFloor.
- Stable v1.5.18 rollback installer hash separately verified and preserved.

## Outstanding gates

Owner-installed Windows icon appearance and Shell pinned-icon cache, independent Reviewer and clean main/stable branch release build NOT CHECKED. This is a private RC1 test only, not a release. No live Host/Remote or installed application has been changed.
