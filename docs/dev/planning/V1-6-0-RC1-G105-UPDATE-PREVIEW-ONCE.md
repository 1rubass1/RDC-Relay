# G105 — Stop repeated Owner update-notice demo animation

**Date:** 2026-11-10. **Status:** Programmer code stage verified, bundled in following G106 candidate; no installed app changed.

## Owner request

The Owner RC1 animated update notice has already passed repeated visual checks; the owner wants **no ongoing automatic replay**. Keep the accepted 25px footer and one-pixel taller gold update button, label/font/animation curve, fake-preview safety and existing normal updater paths unchanged.

## Diagnosis

The Owner RC1 build deliberately enables `ownerUpdateDemoMode` and invokes `Start-RdcUpdateNoticePreview('1.6.0 RC2')` at GUI Shown. Old preview timer ran every 100ms, revealing after 1.8s, hiding after ~5.8s, and starting a new cycle after ~1.4s — hence the repeating fake-update animation. The genuine non-preview update notification already stops animating once the notice is fully expanded; only the demo loop needed removal.

## G105 correction

- `Source/update-notice.ps1`: preview timer now starts once, waits 1.8 seconds, then marks preview shown, **stops/disposes itself**, and shows the existing three-stage expanding animation **once per GUI launch**. The fake notice then remains expanded and static until the GUI is closed or explicitly hidden; the existing test-only `VisualPreviewOnly` restriction still prohibits installation or button activation. `Start-RdcUpdateNoticePreview` refuses subsequent calls when already shown, ensuring no replay within the same GUI.
- `Tests/Test-V16OwnerUpdateDemo.ps1`: exercises real production WinForms preview timer by raising the true Tick event without a message pump; verifies single reveal, timer disposal, no restart on second invocation, no historic 5.8s/1.4s repetition schedule, unchanged button/font/geometry and noninteractive demo behavior.
- No change to real release notification, Host, Remote, account/OAuth, installer launch, preferences or actual update endpoint. This stage is source-only; G106 combines it with the separately requested palette adjustment in the next candidate.

## Tests

`Tests/Test-V16OwnerUpdateDemo.ps1` **16/16 PASS** (previous 12 checks plus four one-shot checks) on STARMER; no live GUI/Remote or updater network contacted.

**NOT CHECKED:** physical Owner GUI's single animation on user-installed build and whether leaving the fake RC2 notice visible after the one-time reveal matches long-term desired UX. This is a demo UI, not a real available RC2 release.
