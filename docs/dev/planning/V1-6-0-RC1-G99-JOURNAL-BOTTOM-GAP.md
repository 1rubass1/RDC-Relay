# G99 — Owner activity journal bottom-gap correction

**Status:** Programmer staged candidate / isolated tests PASS / installed visual verification NOT CHECKED.
**Date:** 2026-11-10. **Branch:** `feature/v1.6-host-gui-owner-pilot` (Draft PR #23).

## Owner feedback

Owner visually accepted G98 mixed-font body and emoji rendering, but reported the lower event journal gained a bottom gap of about 2–3 text rows, fluctuating and increasing as the activity pane was enlarged. The requested UI keeps the existing compact 9pt/10pt fonts, the six-row minimum, and a roughly single-row bottom margin without losing older events or disrupting the restored Desktop Commander line-art logo.

## Root cause — measured on STARMER, not estimated

G98 used the isolated **17px unconstrained Segoe UI Emoji 10pt font pitch** as the journal's row-capacity divisor. But the actual production `RdcLogBox.ApplyCompactLineSpacing()` explicitly fixes RichEdit paragraph pitch to the **15px Consolas 10pt body font**.

A new isolated test compiled the actual `RdcLogBox` C# class from `Source/remote-window.ps1`, applied the same paragraph-spacing method and Owner emoji formatting function, and measured **39 consecutive row advances in each of three cases**: plain text, emoji on every row, and alternating emoji. All measured row advances were exactly **15px**. The G98 17px divisor thus discarded up to ~2px of content capacity **per displayed event**, producing excess bottom whitespace that grows with journal height.

## Correction

- `Get-Rc1ActivityRowReserve` now uses only the measured Consolas 10pt RichEdit row pitch, matching actual `ApplyCompactLineSpacing()`. It no longer inflates Owner `ownerJournalLinePitch` with the unconstrained Segoe Emoji font.
- `Get-Rc1JournalVisibleRowCapacity` remains a conservative whole-row counter: `clamp(1..64, floor(ClientHeight / actualPitch) - 2)`, preserving one whole blank text row above and at least one below, with normal integer-pixel remainder less than another row.
- On STARMER, Owner header minimum stays **93px** (six Consolas 9pt banner rows); lower event pane minimum returns **137px** (eight 15px text rows including two blanks plus 17px horizontal scrollbar); preferred minimum Form height **401px**. Dynamic 64-entry history, resize release behavior, overlay scrollbars, selection and Restore/Host/Remote all unchanged.
- Fonts **unchanged from visually accepted G98**: main text Consolas, only emoji spans Segoe UI Emoji. No UI font switch added.

## Verification

| Check | Result | Scope |
| --- | --- | --- |
| `Tests/Test-V16OwnerJournalBottomGap.ps1` | **7/7 PASS** | Actual production C# RichEdit, 40-line plain/all-emoji/alternating samples, range of journal viewport heights from **120 to 360px**; bottom gap **15–29px** regardless of emoji composition; legacy capacity unchanged |
| `Tests/Test-V16OwnerEmojiFont.ps1` | **27/27 PASS** | Mixed-font spans and colors preserved; capacity contract no longer uses G98 worst-case pitch |
| `Tests/Test-V16ActivityPaneMinimum.ps1` | **18/18 PASS** | Real measured pane metrics, 137px lower, 93px upper, 401px preferred window minimum |
| `Tests/Test-V16OwnerAdaptiveJournal.ps1` | **17/17 PASS** | Event retention, dynamic resizing, six entries at minimum |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **39/39 PASS**, exit 0 | Full isolated contract/compile/mock regression including account switch G96 |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS**, exit 0 | Embedded standalone Setup extraction and launch-route structure, no install |
| Full RC1 build | **21 payload members** | SHA verified, new Setup and Portable staged without executing |

### New G99 candidates on STARMER Desktop

- `RDC-Relay-1.6.0-RC1-JournalGap-Setup.exe`: SHA256 `06B9EA9AEB9D76036702BD1BE6B8CAA258D052183D79BFE3F989840F7B23F9EE`.
- `RDC-Relay-1.6.0-RC1-JournalGap-Portable.zip`: SHA256 `1DEF440AD8AB62DE82CD321159EA14810AC79854F8C40BF84B3DF026BDCBAC59`.

Previous G98 MixedEmoji pair was hash-verified and moved to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G99_Superseded_MixedEmoji/`. Stable rollback `RDC.Relay.Setup.v1.5.18.exe` SHA unchanged. The installed application, live Host/Remote, account and credentials were not modified.

## Remaining acceptance

**NOT CHECKED:** owner's actual installed G99 journal after repeatedly dragging the divider at various heights, case with fewer recorded events than fit (a larger blank area is unavoidable when no history exists), other display DPI. A whole-line layout can have up to one line of pixel remainder, so with sufficient retained events the expected bottom gap is about one to strictly less than two rows (**15–29px at STARMER**), rather than G98's growing 2–3 rows. Independent Reviewer checks consistency; owner visual acceptance is still needed. Do not merge into stable or publish as a release without separate approval.
