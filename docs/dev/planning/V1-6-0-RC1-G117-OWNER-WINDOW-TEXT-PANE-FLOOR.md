# G117 — Correct main-window minimum height to text-pane limits

**2026-11-11 · Owner correction and Programmer implementation.** Private test candidate; NOT RELEASED. This **supersedes incorrect G116 sizing behavior**. Independent Reviewer and owner-installed visual approval pending.

## Owner's exact intent

When the **bottom border** of the main RDC Relay Owner GUI is dragged upward, it must stop **at the usable limits of the two text blocks**, without a spare line between the actual pane limits and the window's minimum. Owner did **not** ask to eliminate the pane minima: the G116 change incorrectly allowed both text areas to collapse to near-zero and looked bad.

## Root cause and safe correction

- Previous pre-G116 whole-form floor used `78 + 38 + headerMin + activityMin + 7 + 48`, which counted the 7px divider **again** even though it was already included in measured `headerMin`, plus an arbitrary 48px allowance. Because that was an outer-form minimum, it also failed to distinguish the actual Windows non-client frame from content.
- G116 went too far: used `78 + 38 + 7 + 2 + windowFrame` and introduced an alternate proportional compression path permitting nearly 1px text panes.
- **G117** Owner main-form minimum is now precisely **78px fixed top + 38px fixed bottom + measured six-line header pane minimum (including 7px divider) + measured eight-row journal pane minimum (including 17px scrollbar) + actual WinForms non-client frame height**. The Owner formula has neither the obsolete +48 nor duplicate +7.
- Fully removed G116 `Get-Rc1CompressedActivityHeight`, compact-mode 1px clamping, adaptive compressed `contentHost.Resize` path and small-screen 1px startup variant. Restored the G115 baseline `Get-EffectivePaneMinHeight`, `Get-ClampedActivityPaneHeight`, `contentHost.Resize`, and initial pane setter. No intentional changes to central divider manual interaction or journal rendering.
- Existing legacy stable/non-Owner window minimum is unchanged. Small or unusual physical displays are a separate compatibility case and do not authorize silent collapse of both Owner text blocks.

## Verification

- `Tests/Test-V16ActivityPaneMinimum.ps1` restored to its pre-G116 validated contract: **18/18 PASS**, preserves measured six-line Owner header and eight-line journal minima plus legacy path. This is deliberate, not a discard of unrelated work.
- `Tests/Test-V16OwnerWindowMinimumContract.ps1` **11/11 PASS**, a new test using actual production PowerShell AST functions and real, hidden WinForms Form+TableLayoutPanel with docked 78px top/38px footer, measured text panes, 7px separator and 17px lower scrollbar. Varies bottom-border height across the former and new thresholds and below the minimum. Checks both panes **never shrink below real text limits**, no remaining dead row at exact form minimum, normal six and eight line slots fit, and WinForms rejects undersized requests. Also rejects return of the nearly 1px G116 behavior.
- Full isolated regression `Tests/Invoke-V16Rc1SafeRegression.ps1`: **49/49 PASS**; the new Contract test is included once. Standalone Setup `Tests/Test-V16StandaloneSetup.ps1`: **19/19 PASS**. Full `Scripts/build-rc1-full.ps1 -Build`: 21 hash-validated payload members.
- G117 STARMER Desktop test candidate:
  - `RDC-Relay-1.6.0-RC1-TextPaneFloor-Setup.exe`, SHA256 `72145AA6534091710B737AA30989209ECEE63A7980671A66ED90409AC7599C22`
  - `RDC-Relay-1.6.0-RC1-TextPaneFloor-Portable.zip`, SHA256 `0B2886B9A0778C527EFB9CD6C3C7FC69EC6EEA90D0853705459B0B430D0D47B7`
- G116 pair validated by original hash and archived at `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G117_Superseded_Overcompressed`; stable v1.5.18 rollback installer SHA independently validated and preserved.

## Remaining gates and preservation

**NOT CHECKED:** physical owner-installed GUI resizing on real monitor, high-DPI changes, WPF divider animation while shrinking, independent Reviewer. Neither live Remote/Host, installed stable RDC Relay, registry, user shortcuts, accounts nor credentials were changed. **No public release, no merge.**
