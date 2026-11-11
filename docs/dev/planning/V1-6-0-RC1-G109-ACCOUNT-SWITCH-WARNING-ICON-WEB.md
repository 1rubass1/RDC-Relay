# G109 — Warning icon and browser shortcut in the Owner account-switch confirmation

**Date:** 2026-11-11. **Status:** Programmer candidate implementation; independent Reviewer and owner visual acceptance outstanding. **NOT INSTALLED.**

## User decision and boundaries

The owner approved the G108 dark theme, fixed rectangular button style and four-paragraph Russian copy, but wanted only the **first bold login instruction** shifted right to make room for the classic **yellow warning triangle**. The other three paragraphs must keep their original left text edge.

On the bottom action row, add a third button on the **left**, labelled **«Выйти из аккаунта»**, **192 px** wide (twice each **96 px** Yes/No button), flush with the same inset as the existing rightmost «Нет» button. Retain «Да» and «Нет» on the right, same color, size and no rounding. Clicking the new button should **open the official website** for manual sign-out without triggering the local Remote logout, device revocation, Host account switch, or closing the warning.

## Implemented UI and verified URL

- `Source/remote-window.ps1` → `New-RdcOwnerAccountSwitchDialog`: first paragraph is placed in a nested two-column WinForms TableLayoutPanel with an **actual Windows `SystemIcons.Warning` 32×32 icon** on the left and a fixed **44 px** offset to the first bold instruction. The other paragraphs remain in their original positions in the same outer layout.
- The bottom row is a two-column TableLayoutPanel: left **192×34 px** `Выйти из аккаунта`, right the existing unmodified right-to-left 96×34 px `Да` and `Нет`. Explicit Top/Left alignment ensures all three buttons have identical vertical baseline; the calculated horizontal margins are **24 px on each side**.
- The new button opens the documented official Remote MCP account dashboard **`https://mcp.desktopcommander.app/`** in the user's browser. A direct public sign-out URL could **not** be independently confirmed; the user must sign out **manually** using the site's UI. The button **does not perform a logout** and never closes the confirmation. Its accessible description makes this clear.
- Original `Yes/No` DialogResults, default Enter/Esc = **Нет**, RC1 Host capability gate and authenticated `SWITCH_ACCOUNT` queue remain unchanged. All four user-approved Russian paragraphs, color palette, footer, emoji, Host, Remote, stable updater and device credentials remain untouched.
- Relevant upstream docs: [Desktop Commander Remote dashboard](https://github.com/desktop-commander/remote-desktop-commander/blob/main/docs/SETUP.md) and [Desktop Commander account guidance](https://desktopcommander.app/help/troubleshooting/usage-limit-after-upgrading). Both explicitly direct account operations to `mcp.desktopcommander.app`; neither provides a verified deep link to browser sign-out.

## Validation

- `Tests/Test-V16OwnerAccountSwitchDialog.ps1`: uses actual production WinForms dialog and source AST. Tests exact prior copy, first bold-only indentation and native icon, unchanged left origin of other paragraphs, actual screen/relative layout, **24px symmetric margins**, aligned y-coordinates and no clipping, unchanged Yes/No defaults, mock-redirect of `Start-Process` to prove **only** the official dashboard URL opens, no dialog result/Host operation, and fake-only existing `SWITCH_ACCOUNT` gate/decision. Browser never opened during tests.
- `Tests/Test-V16OwnerAccountSwitchDialog.ps1` **23/23 PASS**, including the genuine warning icon, first-only text inset, symmetric **24px** margins, strict identical button baseline, no button clipping, intercepted website navigation, and unchanged Host switch safety. No actual browser opened.
- `Tests/Invoke-V16Rc1SafeRegression.ps1` **44/44 PASS**, exit 0, including original Host/process/account/remote safety checks.
- `Scripts/build-rc1-full.ps1 -Build`: full Setup + Portable, **21 SHA-verified package members**.
- `Tests/Test-V16StandaloneSetup.ps1` **19/19 PASS**, exit 0, standalone Setup inspection and disposable extraction without installation.

### G109 Desktop on STARMER

- `RDC-Relay-1.6.0-RC1-AccountSwitchWarning-Setup.exe`: SHA256 `CB7384DC63E7E9C20CE36DCC3398F1476C9575636AEF197C329B97A5686B61B3`.
- `RDC-Relay-1.6.0-RC1-AccountSwitchWarning-Portable.zip`: SHA256 `FB8D3D80B41C82B1BCB4B6ECEFC676AADE1A46D88A3E7C02791B8D919B0D964E`.

Both copies hash-checked after staging. Prior G108 `AccountSwitchDialog` Setup/Portable hash-checked then archived intact at `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G109_Superseded_AccountSwitchDialog`. Stable v1.5.18 rollback Setup hash verified and unchanged.

**NOT CHECKED:** physical rendered modal at owner display DPI/high-contrast, website's logged-in sign-out UI, true site page navigation or real Host account switch. No installed app, live Remote/Host, OAuth, credentials, public release or rollback changed during code verification. Independent Reviewer and owner visual acceptance required; Draft PR #23 stays draft.
