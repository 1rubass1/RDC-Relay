# G114 — Owner Help seamless background + question icon; Reconnect warning modal

**2026-11-11 · Programmer implementation candidate.** Owner asked for targeted changes after G113. **Not a release.**

## User-visible requirements

1. In Owner **«Справка / О программе»**, remove the lighter grey rectangular text backdrop. The help content must visually merge into the parent dark dialog. Add the standard circled **question** icon immediately to the left of **«Справка / О программе»**.
2. In Owner **«Переподключить»**, replace the stock Windows MessageBox and its lengthy text. Show one sentence **«Переподключить Remote?»**, in a modal identical in style to **«Остановить Remote?»**, with standard Windows **warning exclamation triangle** instead of the old Question icon. Keep **«Да» / «Нет»**, No on Enter/Escape, only explicit Yes sends the original `RECONNECT` request.
3. Preserve existing Host ownership/capability gates, account behavior, existing Stop confirmation and stable legacy flow. Do not touch live Remote.

## Implementation

- `Source/remote-window.ps1` changes the Owner Help `RichTextBox.BackColor` to the parent dialog's dark `BackColor` (RGB 29,32,36), keeping it borderless, readable, scrollable and read-only. A two-column header row carries a native 32×32 `[Drawing.SystemIcons]::Question` bitmap followed by the unaltered bold `Справка / О программе` heading.
- `New-RdcOwnerReconnectDialog` **reuses** the exact G113 Stop warning form geometry and controls (dark palette, Segoe UI, 480×168 compact fixed centered dialog, Warning 32×32, 96×34 buttons, No default). It changes only Owner Reconnect title `Переподключение Remote`, confirmation `Переподключить Remote?` and control identities. It adds no new Host action or subprocess.
- `Show-RdcOwnerReconnectConfirmation` replaces only the Owner Reconnect stock MessageBox. The preexisting `ownerManagedMode` and `ownerCanReconnect` checks remain in the same event handler. The existing explicit-Yes `RECONNECT` queue action and legacy `Restart-Remote` path remain unchanged.
- `Tests/Test-V16OwnerStopHelpDialogs.ps1` expands to inspect actual AST-extracted production WinForms forms, native Help icon, consistent backdrop, reconnect warning icon, bounds, buttons and No/Yes/capability/observed-mode behavior without invoking real Host/Remote.

## Verification evidence

- Dedicated real WinForms/route tests: **34/34 PASS**.
- Standalone built Setup with verified embedded payload: **19/19 PASS**.
- Full safe regression `Tests/Invoke-V16Rc1SafeRegression.ps1`: **48/48 PASS**, exit 0.
- Built private candidate from `Scripts/build-rc1-full.ps1 -Build`, 21 hashed payload members:
  - Setup SHA256: `9E5FA727094C5958A7474C5233C6CBD959D7A4D0D30105420C873D2C25BF284A`
  - Portable SHA256: `20B4AA3B2A5217EEA0CB3E1FC228A82208947BF0AD3F80C22C82E3DB8017208E`
- Staging path: `dist/RDCRelay-1.6.0-RC1-Full-1d9d7d190e254896a47c5feb5d2d3593`. Verified STARMER Desktop artifacts: `RDC-Relay-1.6.0-RC1-ReconnectHelp-Setup.exe` and `RDC-Relay-1.6.0-RC1-ReconnectHelp-Portable.zip`, corresponding SHA-256 above. Previous G113 Setup/Portable hash-checked and archived at `RemoteDesktopCommander/Old_Installers_2026-11-10/G114_Superseded_StopHelpDialogs`. Stable v1.5.18 rollback Setup separately hash-checked and preserved.

## Pending

Independent Reviewer and owner-installed visual inspection of Windows icon scaling, seamless Help background and Reconnect dialog **NOT CHECKED**. Do not merge or publish a stable release. Preserve 1.5.18 rollback, existing user Installed Apps registry, working GUI/Host/Remote, credentials and user shortcuts unchanged.
