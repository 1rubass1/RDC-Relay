# G119 — Account button label centering

**2026-11-11 · Programmer implementation candidate; owner visual and independent Reviewer pending. NOT A PUBLIC RELEASE.**

## Owner observation

Owner noticed the `Аккаунт` label looked a few pixels left of center compared with the `Остановить` button, whose Stop glyph is separately drawn. Owner requested a narrow UI fix only if its cause was clear, with no tray behavior changes.

## Root cause

The Account button was a `RdcRoundedButton` with `Text = 'Аккаунт ▾'` and `Glyph = None`. In `OnPaint`, the full text, **including the trailing dropdown indicator**, was horizontally centered. Because the arrow occupied the right side of the centered string, the actual word `Аккаунт` was necessarily offset left. Meanwhile `Остановить` uses a separately painted Stop glyph and text geometry.

## Implementation

- In `Source/remote-window.ps1`, new opt-in `RdcRoundedButton.ShowMenuChevron` property defaults to false. The Account button now uses `Text = 'Аккаунт'`, `ShowMenuChevron = true`, and an explicit accessible name indicating the menu. `TextRenderer.DrawText` centers **only the word** in the whole button. A 10×8-pixel downward chevron is separately drawn on the right at a stable offset. It never participates in text measurements.
- Stop/Start play/stop glyph logic, button size 120×36, colors, focus and click handling, ContextMenuStrip positioning, account menu contents, Remote/Host and tray files are unchanged.
- No independent `button.Click` handler, action, timer, or animation added; only rendering changes.

## Verification

- New `Tests/Test-V16AccountButtonCentering.ps1` compiles the actual embedded C# control declaration extracted from the production PowerShell source and draws its WinForms pixels into an isolated bitmap. It checks real production `Аккаунт` text, exact menu click route, no overlap of the label with the chevron at 120×36 and scaled 144×43, that the chevron changes **only** the right pixels while the label is pixel-identical, that visible text is within 3 pixels of geometric center, that Stop glyph remains independent, and that keyboard Space/Enter still click. **13/13 PASS.**
- Full private RC1 safe regression (including the new test): **51/51 PASS**, exit 0.
- Actual rebuilt private RC1 Setup extraction/validation: **19/19 PASS**, 21 hash-verified payload members.
- Current STARMER Desktop `RDC-Relay-1.6.0-RC1-CenteredAccount-Setup.exe`, SHA256: `E5F05369FC850E3DE5669B0B7DFBB86768F85037C710E440C66BB107C8900B02`.
- Current STARMER Desktop `RDC-Relay-1.6.0-RC1-CenteredAccount-Portable.zip`, SHA256: `786D549FF839169C3735721DA6E76CF334AFA150D3B9C52EC1C923EED386A73D`.
- Previous G118 Setup/Portable verified by SHA and archived at `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G119_Superseded_AppIcon04`. Stable 1.5.18 rollback installer separately verified and preserved.

## Boundaries and remaining work

Owner-installed physical visual inspection (including actual Windows DPI, font fallback, default/hover focus) and independent Reviewer NOT CHECKED. Safe full RC1 build performed without executing Setup, Host, Remote or GUI; no public release, registry, user shortcut, credentials or live process touched. Concurrent Designer/Tray changes in `COORDINATION/BOARD.md` and `docs/dev/design/icon-concepts-2026-11-11/` remain outside this task and commit.
