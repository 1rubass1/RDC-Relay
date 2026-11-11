# G116 — Owner main-window bottom-edge compression without artificial one-row slack

**Date:** 2026-11-11. **Status:** Programmer implementation candidate, staged for owner visual and independent Reviewer. **NOT A PUBLIC RELEASE.**

## Owner request and diagnosis

When dragging the **bottom edge of the main RDC Relay Owner GUI upward**, the window stops shrinking while the central horizontal divider still has approximately **one text row of unused vertical slack**. The user wants the two scrollable text blocks to collapse automatically as far as the actual window geometry permits. Do not confuse this with the compact Help dialog or the manually dragged central divider.

The previously approved normal-size banner and journal baselines were retained: the six-line header in `Get-Rc1HeaderBannerMinimum` and eight RichEdit journal rows in `Get-Rc1ActivityRowReserve`. The former Owner main-form `MinimumSize` was constrained by a legacy expression including `+48` beyond header, footer and preferred pane minimums; on STARMER this resulted in a **401px outer height** and about one RichEdit-row of remaining slack. Also, the previous Owner pane clamp had a fixed 48px fallback minimum.

## Implementation scope

- `Source/remote-window.ps1`: only in **OwnerGui**, compute main-form bottom-edge minimum from fixed 78px header + 38px footer + 7px draggable divider + 1px for each of the two text viewports + **actual Windows frame height** (`form.Height-form.ClientSize.Height`). Do not add a fixed 48px safety surplus. Keep the unchanged window width constraint and fixed main header/footer. Legacy non-Owner minimum and old behavior are unchanged.
- `Get-Rc1CompressedActivityHeight` proportionally fits the activity pane when available content is below the **preferred sum** of the original header and journal minima. The upper pane gets the remaining space; reserve at least 8px for its 7px divider and a pixel of text viewport. No extra row is reserved. At normal height, central splitter clamping continues to preserve the six-line banner and journal baseline.
- `Get-EffectivePaneMinHeight` and `Get-ClampedActivityPaneHeight` allow manual splitter adjustment down to the **physical** 1px activity + 8px upper viewport minimum only when the Owner window is already below the prior preferred pane sum. The retained 7px divider remains interactive; scrolling/logging and Host/Remote operations are unchanged.
- Main `contentHost.Resize` automatically updates the activity-pane height with the proportional fit as the user drags the bottom edge. The initial window layout uses that same fit when launched on a display shorter than the old preferred size, rather than accidentally initializing the lower area at 1px.

## Verification

- `Tests/Test-V16ActivityPaneMinimum.ps1`: **26/26 PASS** (actual production functions extracted via PowerShell AST; RichEdit/Consolas measured line pitch; normal-size six-line header and six-event journal constraints retained; shrinking content host 230px → 9px with both pane sizes decreasing; manual compact splitter drag; **actual hidden WinForms main-form fixture** resized through 520/430/401/385/350/320/300/250/210/185px and physical lower bound, verifying docked top/bottom and panes consume exactly the available client height, no one-row gap; legacy non-Owner 125px minimum unchanged).
- `Tests/Invoke-V16Rc1SafeRegression.ps1`: **48/48 PASS**, exit 0; existing activity-pane test included once.
- `Tests/Test-V16StandaloneSetup.ps1` against the newly compiled standalone EXE: **19/19 PASS**.
- `Scripts/build-rc1-full.ps1 -Build`: 21 hash-checked embedded payload members.
- STARMER Desktop current private RC1 candidate:
  - `RDC-Relay-1.6.0-RC1-FullHeightResize-Setup.exe`, SHA256 `62B0A8B8A618D2463499CF84EBF364B7F748435CBB3EC84A2FCA38C53B7BC7AC`
  - `RDC-Relay-1.6.0-RC1-FullHeightResize-Portable.zip`, SHA256 `AA3F8245DA818943C5973D4E97C5114C606EBBC3B16F81018F5A5A01B948EFD1`
- Previous G115 pair validated with SHA256 and archived at `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G116_Superseded_CompactHelp`; v1.5.18 stable rollback EXE independently hash-checked and preserved.

## Limitations and safety

**NOT CHECKED:** Owner-installed physical display resizing, DPI changes in live GUI, real-time WPF shader/overlay visual quality at tiny heights, independent Reviewer. The minimum **cannot** go through fixed top/footer, the seven-pixel divider or Windows non-client decorations. These are physical layout constraints, not an extra text-row minimum. No public release or merge. Running Host, GUI, Remote, installed 1.5.18, Windows registry, shortcuts and account/OAuth data were not touched.
