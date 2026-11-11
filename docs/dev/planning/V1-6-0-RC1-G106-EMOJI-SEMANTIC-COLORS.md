# G106 — Owner semantic emoji color audit, incorporating G105 one-shot preview

**Date:** 2026-11-10. **Status:** Programmer candidate staged on STARMER, NOT INSTALLED; independent review and owner visual acceptance required.
**Branch:** `feature/v1.6-host-gui-owner-pilot` / Draft PR #23.

## Two-step owner request

1. **G105 first:** stop repeating the update-notice demonstration, preserving its approved height, font, position and animation. See [G105 source-stage report](V1-6-0-RC1-G105-UPDATE-PREVIEW-ONCE.md). This is an Owner RC1 **fake update preview**, not a real RC2 release. It reveals once 1.8 seconds after GUI Shown, stops/disposes the preview timer, remains expanded and static. The unrelated real update-notification timer already animates once when a genuine update is available, and remains untouched.
2. **G106 second:** research/update the palette of visible emoji in the upper Desktop Commander header and lower activity journal. Owner specifically reported the **purple ✅ success checkmark** as misleading.

## Research and semantic mapping

Read current Microsoft primary guidance:
- [Fluent 2 — Color](https://fluent2.microsoft.design/color): semantic colors signal positive feedback (green), caution (yellow/orange) and danger (red); colors should convey meaning, not simply decorate
- [Windows classic UI color guidelines](https://learn.microsoft.com/en-us/windows/win32/uxguide/vis-color): green = go/safe/done, red = error/stop, yellow = warning/caution, blue = information/links
- [Windows app iconography](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-design): shape/metaphor must remain legible independent of color; do not rely on color alone for meaning

The existing dark RdcLogBox background and terminal-like typography do not need a brand redesign. The emoji glyph itself continues conveying state; color serves as a redundant semantic cue.

| Icon | Meaning in these logs | Before in Owner | After in Owner | Decision |
| --- | --- | --- | --- | --- |
| ✅ | Tool call succeeded | Purple (`$accentPurple`) | **LightGreen** (`$statusGreen`) | Positive completed operation, not purple branding |
| ⏹ | Explicit Stop/disconnect action in Owner Next | Orange | **LightCoral** | Stop/danger action, but not a claim that Remote crashed |
| 👋 | Greeting/presence marker | Plum | **Gainsboro** | Non-status greeting; neutral text instead of arbitrary purple |
| ❌ | Failure | LightCoral | Unchanged | Red failure |
| 🔌 | Remote connected | LightGreen | Unchanged | Green connected/positive |
| ⏳ | Pending/wait | Khaki | Unchanged | Yellow pending/caution |
| 🌐 | Web/network | LightSkyBlue | Unchanged | Blue information/network |
| 💾 | Save/storage | LightSteelBlue | Unchanged | Blue-gray utility/storage |
| 🔧 | Tool operation | Muted orange | Unchanged | Branded/action emphasis |
| 🚀 | Start/launch | Muted orange | Unchanged | Branded/action emphasis |

The new variables `$accentSuccess`, `$accentStop`, `$accentGreeting` are **Owner-only conditionals** in `Source/remote-window.ps1`, so legacy 1.5.18 text colors continue to use their original purple/orange/plum. Both Owner rich-text panes use the same semantic mapping; no change to existing base **Consolas 9pt/10pt** and inline `Segoe UI Emoji` fallback, line spacing, event history, other purple brand accents, account checkbox, menu, update button geometry or Host.

## STARMER verification

| Test | Result | Evidence |
| --- | --- | --- |
| `Tests/Test-V16OwnerUpdateDemo.ps1` | **16/16 PASS** | Actual WinForms timer Tick invoked; single preview, timer disposed, subsequent calls no replay, font/height/button safety unchanged |
| `Tests/Test-V16OwnerEmojiPalette.ps1` | **14/14 PASS** | Owner & legacy source parsing, actual `RdcLogBox` and `Color-LogToken`/font selection, all 10 icon color bindings, surrounding text neutral Consolas |
| `Tests/Test-V16FullOriginalStartupHeader.ps1` | **50/50 PASS** | Next / Commands sequence intact; stop marker now uses appropriate semantic accent |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **42/42 PASS**, exit 0 | All safe compile/mock/contract regression (41 previous + new emoji palette test) |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS**, exit 0 | Real self-contained Setup extraction and launcher manifest without installing |
| Full builder | **21 SHA-verified payload members** | Built offline; copied to Desktop without launching |

### STARMER Desktop G106 (contains both stages G105 + G106)

- `RDC-Relay-1.6.0-RC1-OneShotEmojiColors-Setup.exe` SHA256 `D1502B3681D974952A4679AA40E5B92BF032AA911052A063ACB985B5B30EA6BE`.
- `RDC-Relay-1.6.0-RC1-OneShotEmojiColors-Portable.zip` SHA256 `AB928E8B80749AFEFC36914C4AA349A11D22396BD75BAA6D03AE532D0FB82DE7`.

Prior G104 `NeutralAccountMenu` Setup/Portable checked byte-exact and moved intact to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G106_Superseded_NeutralAccountMenu`. Stable rollback `RDC.Relay.Setup.v1.5.18.exe` checked by SHA and preserved. No change to running installed app, Remote/Host, OAuth, credentials or release channel.

## Outstanding gates and caveats

**NOT CHECKED:** actual installed Owner GUI after the one-time animation and its static preview badge, subjective emoji tint on the owner's display, color-emoji glyph layers that RichEdit may render differently from `SelectionColor`, contrast at other DPI/system settings. Source-level and disposable WinForms tests confirm the semantic selections; they do **not** prove how native color emoji layers render on the live monitor. Independent Reviewer checks boundaries, and owner visually approves before release. Do not merge or publish an updater without separate authorization.
