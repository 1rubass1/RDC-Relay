# G104 — Account menu neutral image gutter

**Date:** 2026-11-10. **Status:** Programmer candidate staged, NOT INSTALLED; independent review and owner visual approval required.

## Owner feedback and decision

G103's 16×16 outlined quota checkbox was visually accepted, but the shared orange vertical image gutter behind Account commands was distracting. Owner preferred making that gutter **the same dark color as the menu text background**, rather than darkening the orange.

## Minimal implementation

- `Source/remote-window.ps1`, `RdcOwnerAccountMenuRenderer.OnRenderImageMargin(ToolStripRenderEventArgs)`: fill only the **Owner Account** image margin with `e.ToolStrip.BackColor`, the existing menu background `Color.FromArgb(38,41,46)`. This removes the orange gutter without changing row selection, text label positions, or the menu's pre-existing dimensional layout.
- Does **not** change the shared `RdcMenuColorTable.ImageMarginGradientBegin/Middle/End` properties; Help and non-Owner legacy menus retain their original orange image gutter.
- G103 custom quota checkbox remains unchanged: dark 16px square with a light border, white checkmark in the checked state, visible empty OFF box, bright hover/focus border, Windows High Contrast fallback.
- **G102 quota behavior untouched:** checkbox `Выводить остаток вызовов` is checked by default; automatic Host-owned Ready account OAuth and 30-minute `who_am_i` polling continue until user explicitly unchecks; opt-out persists. No Remote, process, account, password, token, IPC, updater, layout or other GUI features changed.
- The UI renderer uses the supported Windows Forms virtual `OnRenderImageMargin` method, so the existing menu background is authoritative, even if the color is later adjusted.

## STARMER evidence

| Verification | Result | Scope |
| --- | --- | --- |
| `Tests/Test-V16QuotaMenuCheckbox.ps1` | **14/14 PASS** | Compiled production renderer C#, real `ToolStripRenderer.DrawImageMargin` paints Owner margin exactly RGB(38,41,46), legacy/shared renderer still paints orange RGB(191,118,67), checkbox bitmap ON/OFF/disabled and native `CheckOnClick`/row geometry unchanged |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **41/41 PASS** | Safe compile/static/mock suite incl. G102 quota, G103 checkbox, prior Owner UX |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS** | Standalone package manifest/extraction; not installed |
| Full builder | **21 SHA-verified package members** | Setup/Portable candidate staged; not executed |

### New G104 pair on STARMER Desktop

- `RDC-Relay-1.6.0-RC1-NeutralAccountMenu-Setup.exe` SHA256 `353271010F2ADCA6BDBC4C0530360D97711625F0CDD6FC337F5DE028F97BD9C2`.
- `RDC-Relay-1.6.0-RC1-NeutralAccountMenu-Portable.zip` SHA256 `BAD29B66258271CFE0D7670F2CFA028354C5F69415108C91A8B23013FD16E0BA`.

Immediately superseded G103 `QuotaCheckbox` Setup/Portable moved with verified hashes to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G104_Superseded_QuotaCheckbox/`. Stable rollback `RDC.Relay.Setup.v1.5.18.exe` SHA verified and preserved.

## Acceptance boundary

**NOT CHECKED:** installed Owner GUI's visible dropdown at the user's display DPI, actual hovered/off row appearance or OS high contrast; no real account login/test. Reviewer should confirm that the override affects only Owner Account and has no row clipping; owner can visually verify a continuous neutral background after installing this candidate. Running installed GUI, Host/Remote, credentials, stable, updater or public release were **not changed**.
