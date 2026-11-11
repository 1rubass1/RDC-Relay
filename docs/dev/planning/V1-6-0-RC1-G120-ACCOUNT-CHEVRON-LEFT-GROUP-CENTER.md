# G120 — Account left chevron and text centered as one group

**2026-11-11 · Owner correction to G119 · private RC1 candidate, not a release.**

## Requirement and diagnosis

Owner rejected G119's label-only centering with a detached right-hand chevron. The entire **icon + Account text** should appear compositionally centered, just like the Stop button's glyph + text; owner suggested placing the dropdown arrow to the **left** of the word.

## Implementation

- `Source/remote-window.ps1` retains `RdcRoundedButton.ShowMenuChevron` for Account only, but replaces its fixed right-corner geometry with a **left-hand 12px icon slot**, a **7px gap**, and the same measured text width used by the Stop/Play buttons.
- `GetGroupIconBounds(textWidth)` is now the single calculation of the center-aligned icon-plus-text group shared by Account and Stop/Play. A 10x8 downward chevron is painted inside the centered 12px slot. Text is placed immediately after the gap using exactly the same positioning and flags as the Stop button; only the icon's graphic differs.
- The previous behavior of centering `Аккаунт` by itself and anchoring the chevron far right is **superseded**. Avoid reintroducing either the inline Unicode glyph `Аккаунт ▾` or the detached right-hand arrow.
- Button size 120x36, colors, hover/pressed/focus, Account menu click position, Owner Host/Remote behavior and tray logic are untouched. Competing Designer/Tray work and their uncommitted BOARD.md + design files were not altered or included.

## Verification

- `Tests/Test-V16AccountButtonCentering.ps1` is updated to validate **group centering**, not the mistaken G119 label-only rule. Uses compiled production C# and actual WinForms painting; checks native icon bounds, Stop-identical group text pixels, separate left chevron, lack of overlap and centering at 120x36, 144x43 and 160x48. Space/Enter click path is also covered. **27/27 PASS**.
- Full isolated RC1 regression `Tests/Invoke-V16Rc1SafeRegression.ps1`: **51/51 PASS**, exit 0.
- Standalone compiled Setup extraction test: **19/19 PASS**; built candidate contains 21 manifest-hashed members and v04 app/installer icon.
- Current STARMER Desktop **`RDC-Relay-1.6.0-RC1-CenteredAccountGroup-Setup.exe`**, SHA256: `42DB147C6C738CC768DC19148878AE42FFCF924EDC17F5204544D00C551F387F`.
- Current STARMER Desktop **`RDC-Relay-1.6.0-RC1-CenteredAccountGroup-Portable.zip`**, SHA256: `99C585CBCF3A215788064520CBE70C1D643D2EBB8472FF131868B1815A60E9D9`.
- Previous G119 Setup/Portable SHA-checked and archived under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G120_Superseded_AccountLabelOnly`. Original v1.5.18 rollback SHA verified intact.

## Gates

Owner's visual acceptance on installed STARMER UI, Windows DPI/hover and independent Reviewer remain **NOT CHECKED**. Live installed GUI, Host/Remote, registry, accounts, shortcuts and tray not modified. Do not merge or publish a release.
