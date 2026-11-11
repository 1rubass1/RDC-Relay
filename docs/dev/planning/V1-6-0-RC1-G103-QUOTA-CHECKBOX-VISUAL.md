# G103 — Distinct Account-menu quota checkbox

**Date:** 2026-11-10. **Status:** Programmer staged; independent Review and owner visual acceptance needed; **NOT INSTALLED**.

## Owner feedback

The previously delivered G102 checked `Выводить остаток вызовов` menu item is functionally correct, **ON by default**, with the restored managed-account automatic OAuth and 30-minute quota refresh. However, the Account menu's **whole left image gutter is orange** (the original `RdcMenuColorTable.ImageMarginGradient*`), which makes the standard native tick hard to distinguish from general decoration. Owner asks to **highlight the checkbox itself** while leaving existing menu/text placement and existing quota behavior intact.

## UI design and implementation

- `Source/remote-window.ps1`: adds **Owner-only** `RdcOwnerAccountMenuRenderer : ToolStripProfessionalRenderer`, retaining the existing `RdcMenuColorTable` orange gutter, purple selected-row treatment and all other items. The ordinary help and legacy menus retain the original native `ToolStripProfessionalRenderer`.
- Assigns only quota item's **Name=`rc1-quota-display-toggle`**. The renderer draws a fixed **16×16px**, dark, separately bounded square at **X=6**, centered vertically inside the existing left image gutter. OFF is an **empty light-outlined** square; ON is a dark-violet square with a pale-gold border and **white, antialiased check mark**. Hover/keyboard selection brightens the border. A disabled item gets a toned-down square. Windows High Contrast uses **`SystemColors.Window`/`Highlight`/`WindowText`/`HighlightText`** instead of fixed brand colors.
- Overrides `OnRenderItemCheck` **for that named item only** so the native check is not drawn twice; all other menu checks use normal rendering. Overrides `OnRenderMenuItemBackground` to draw empty OFF squares too (WinForms otherwise draws its checkbox only when checked). Underlying `ToolStripMenuItem.Checked`, `CheckOnClick`, keyboard activation, accessible description and full-row click target stay native.
- **No new form controls, no changes to account menu items' size, font or position, update button, footer, log, animated motion, Host polling/auth, preference, or Remote credentials**. In G103 the default remains checked, as approved in G102.
- Microsoft UI guidance: Windows checkbox state must be visually clear (Windows App Design Guidelines); `ToolStripProfessionalRenderer.OnRenderItemCheck` is its supported WinForms override mechanism. No installation or live Remote performed for this UI trial.

## Isolated verification on STARMER

| Check | Result | Scope |
| --- | --- | --- |
| `Tests/Test-V16QuotaMenuCheckbox.ps1` | **12/12 PASS** | Compiles actual renderer C# from production source; renders bitmap samples at ON/OFF/disabled; validates white tick vs empty center, contrasting dark fill against orange gutter, 16px bounds, no row height drift on `PerformClick`, Owner-only renderer hookup, keyboard/accessibility continuity, high-contrast colors |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **41/41 PASS** | Prior G102 default-ON quota/Host OAuth, journal, update animation, UI ownership, process and fake-only regression including new 12-check test |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS** | Standalone EXE extraction and payload manifest, no install |
| Full candidate | **21 embedded payload members SHA-verified** | Setup/Portable built and staged; not executed |

### STARMER Desktop

- `RDC-Relay-1.6.0-RC1-QuotaCheckbox-Setup.exe`: SHA256 `BD5114FEF845510D2D791EFFB1673FD0974408C36DA9870A02A36A82ADDE9564`.
- `RDC-Relay-1.6.0-RC1-QuotaCheckbox-Portable.zip`: SHA256 `F43FA56781CF121675799FCF7EB2DF4DBF39D440D38012925D97D9B2DCC796B8`.

Previous G102 `QuotaDefaultOn` Setup/Portable hash-verified and archived intact under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G103_Superseded_QuotaDefaultOn/`. Stable `RDC.Relay.Setup.v1.5.18.exe` unchanged and SHA verified.

## Unchecked, acceptance and boundaries

**NOT CHECKED:** visual impression in the actual installed Account dropdown, other Windows DPI scaling/High Contrast system settings, physical hover/keyboard focus, live quota OAuth. Owner should evaluate whether checked/unchecked is obvious on the orange gutter. Independent Reviewer verifies targeted renderer and no regression of accessible/native behavior. No installed Host/GUI/Remote, credentials, authentication or update channel modified; no merge or stable release authorized.
