# G97 — Emoji-friendly font trial in both Owner text panes

**Status:** Programmer candidate ready / independent review and owner visual acceptance required / **NOT INSTALLED**.
**Source:** `60f4128` on `feature/v1.6-host-gui-owner-pilot` (Draft PR #23).
**Boundaries:** No installed program, Remote process, OAuth credentials, stable 1.5.18, release branch, updater or actual account session changed.

## Owner intent

The original compact first/second RichTextBox panes show tiny missing-glyph boxes instead of several original Remote symbols (`🔧`, `✅`, `❌`, `🔌`, etc.). Owner requested a candidate using a Unicode emoji-aware *whole-text* font while retaining the point sizes and the six-row collapsed layout. A future choice under Help/Journal settings was discussed but **not requested for this first trial**.

## Scope

- Set a single Owner-only font family preset `$script:ownerTextFontFamily='Segoe UI Emoji'`. In legacy non-Owner GUI it remains `'Consolas'`. Use that variable for both actual RichEdit controls **and both temporary measurement probes**; unchanged 9pt header and 10pt journal.
- On STARMER 96 DPI, measured WinForms RichEdit line pitches are **16px (Emoji 9pt)** and **17px (Emoji 10pt)**, versus original Consolas 14px/15px. The measured Owner collapsed upper pane is now **105px** (six rows ×16 +7 divider +2 safety). The minimum lower pane is now **153px** (eight 17px rows: six events and one blank row each side, plus 17px reserved scrollbar). Preferred full window minimum: **429px**, previously 401px. All shared pane drag/collapse clamps use the calculated minima; 64-row retained history and dynamic capacity remain intact.
- No emoji strings, color-token selection, transcript sanitization, upstream Host startup, tool ordinals, process lifecycle, shader or OAuth logic changed. The original startup ASCII/box-art and six-digit journal gutter may *visually shift* in this proportional font; verify carefully.
- This intentionally does **not** claim that standard WinForms RichTextBox can render *multicolored layered emoji*. Windows' Segoe UI Emoji font is available on STARMER, and RichEdit preserves selected font+Unicode in RTF; rendered appearance/color needs real user visual acceptance. A future settings choice could expose `Consolas` vs `Segoe UI Emoji` using one internal font-preset source, with geometry recomputed on selection; this switch was **not** implemented.
- Microsoft references: [Segoe UI Emoji font](https://learn.microsoft.com/en-us/typography/font-list/segoe-ui-emoji), [WinUI RichEditBox color-font property](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox.iscolorfontenabled).

## Evidence (STARMER, 2026-11-08)

| Verification | Result | Limits |
| --- | --- | --- |
| `Tests/Test-V16OwnerEmojiFont.ps1` | **10/10 PASS** | Native installed font, WinPS AST, both source font contracts, WinForms RichEdit Unicode/RTF/font at 9/10pt; **does not prove pixel rendering or color** |
| `Tests/Test-V16ActivityPaneMinimum.ps1` | **18/18 PASS** | Real RichTextBox measured 16/17px pitches and six-row clamping |
| `Tests/Test-V16OwnerAdaptiveJournal.ps1` | **17/17 PASS** | Six visible at min, grow/shrink, retained 64-event history |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **38/38 PASS**, exit 0 | Existing fake-only/AST/compile tests including G96 SwitchAccount |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS**, exit 0 | Standalone embedded Setup manifest, no installation |
| Full builder | **21 packaged payload members, SHA verified** | Setup/Portable staged, not executed |

**Desktop staged candidate (no install):**
- `RDC-Relay-1.6.0-RC1-EmojiFont-Setup.exe` — SHA256 `4BFC3981564F4D56EBCE56B2F210BE731575E0042B29356E6275DFFAABADF396`.
- `RDC-Relay-1.6.0-RC1-EmojiFont-Portable.zip` — SHA256 `6A14C59AA5368B0B172D97FDCC33CE673EF04D138ECD0D326130E065ABDF67CE`.

Installer housekeeping: G96 `AccountSwitch` Desktop Setup/Portable moved without modification, hashes checked, into `Desktop/RemoteDesktopCommander/Old_Installers_2026-10-29/G97_Superseded_AccountSwitch/`. Kept rollback `RDC.Relay.Setup.v1.5.18.exe` (hash unchanged), previous archived G95 and RC1 installed state.

## Acceptance gate

**NOT CHECKED:** physical pixel glyph rendering, actual emoji colors, original six-line Desktop Commander banner alignment in proportional font, bottom journal spacing at real DPI, scrollbar, link selection, RichEdit font fallback on other Windows versions, installed GUI visual appearance. Owner manually installs only at a safe time and compares G97 against G96. If missing glyphs persist or ASCII logo alignment regresses, retain fallback instead of declaring success; a future glyph-specific font overlay or custom icon renderer may be necessary.

**Next:** independent Reviewer verifies UI font-size/line geometry contracts and fallback preservation, then owner visual check. Do not enable public update, merge or stable release.
