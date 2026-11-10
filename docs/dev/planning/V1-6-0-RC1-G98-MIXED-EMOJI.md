# G98 — mixed emoji font after G97 visual feedback

**Status:** Programmer candidate prepared / NOT INSTALLED / independent review and owner visual verification required.
**Date:** 2026-11-10.

## Observed G97 defect and cause

Owner screenshot shows partial emoji success, but replacement squares in the six-row Desktop Commander startup banner and in Next/Commands sections. The entire Owner RichTextBox had been assigned Segoe UI Emoji, a *non-monospaced* font. This breaks the box-art glyphs and the originally fixed-width column layout. Do not store user identifiers or logs from the screenshot in public Git.

## G98 implementation

- Restores Consolas 9pt header and Consolas 10pt activity journal **as the base font for the entire contents**, including banner, ASCII/Unicode line art, journal IDs and text.
- Applies Segoe UI Emoji **only to Unicode emoji and pictogram character spans**, after semantic colorization, using a dedicated Owner-only Apply-OwnerEmojiFont function based on the RichTextBox SelectionFont API. It leaves U+2500..U+259F box art untouched, maintains selection colors, and disposes the font object.
- Prepares a single Owner-only boolean font overlay switch for a possible future Help/Journal preference. No settings UI or persistent config added in G98.
- At STARMER: normal Consolas 9pt header pitch **14px**, Owner collapsed header min **93px** for six banner lines; lower journal calculates the safe maximum of Consolas 10pt **15px** and selected Segoe Emoji 10pt **17px**, min **153px** for six events and one blank line on each side. Measured disposable RichEdit mixed line pitch is **16px / 17px** at 9pt/10pt; preferred Form minimum **417px**.
- Preserves legacy non-Owner behavior, source transcript, Host state, Remote, OAuth, account-switch functionality, update/release boundaries and stable rollback. No actual Host, Remote, installed application or credentials touched.

## Verification on STARMER

| Validation | Result | Scope |
| --- | --- | --- |
| Test-V16OwnerEmojiFont.ps1 | **27/27 PASS** | Disposable RichTextBox, actual per-run font selection, text, colors, line art vs emoji, 9pt/10pt, disabled legacy |
| Test-V16ActivityPaneMinimum.ps1 | **18/18 PASS** | Font pitch and pane clamps, six-line banner |
| Test-V16OwnerAdaptiveJournal.ps1 | **17/17 PASS** | Event capacity and retained history |
| Invoke-V16Rc1SafeRegression.ps1 | **38/38 PASS** | Full safe static/fake/compile regression |
| Test-V16StandaloneSetup.ps1 | **19/19 PASS** | Real standalone package extraction; no installation |
| Full package build | **21 members** | SHA verified; not installed |

### Staged candidate on STARMER Desktop

- RDC-Relay-1.6.0-RC1-MixedEmoji-Setup.exe — SHA256 07680D5F6F873B9CEC9F42FC03258BAAEDF0AB4C0FC1E5A2E7814F8ABC8FF2CA
- RDC-Relay-1.6.0-RC1-MixedEmoji-Portable.zip — SHA256 BE021EFE64757A0471707EE72F698DB6C849AAA5B9AAD9F847A0ADB914578B32

Previous G97 EmojiFont Setup/Portable were moved with SHA verification to Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G98_Superseded_EmojiFont/. Stable 1.5.18 Setup remained intact. No user-install action or Remote process changes.

## Review and owner visual gate

**NOT CHECKED:** actual screenshot after install; whether Desktop Commander banner is fully drawn and continuous; whether Next, Return, Stop and Commands icons are visibly identifiable without replacement squares; scroll and selection in the live GUI, other DPI/display setups, multicolored emoji layers. WinForms RichTextBox does not guarantee color emoji like XAML controls. If an individual supplementary symbol still fails, prefer a safe glyph-specific fallback or separate icon rather than another font-wide replacement.

Microsoft references: RichTextBox.SelectionFont API; Segoe UI Emoji font; Windows App Design Guidelines and Fluent 2.
