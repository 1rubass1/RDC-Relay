# RDC Relay 1.6.0 — tray remaining-percent tooltip, batch 07

**Source-level integration, 2026-11-19; NOT a live Remote or release approval.**

## Display contract

- The real `NotifyIcon.Text` now renders `RDC Relay | 73% | Ready` (localized status) with **exactly two vertical separators**, without RC1, version or release channel in the hover text; those belong in Help/About. The center token always contains the latest verified `remote_calls_left_pct` percent, or `--%` when unknown (matching the main window). Windows' native tooltip remains responsible for pixel layout; only the middle *field* is centered, not the text pixels.
- In FakeOnly mode, the status uses `Test: ` / `Тест: ` as a presentation-only prefix, rather than a third `|` separator. It does not claim a real account or quota.
- The **existing** Host quota OAuth client is still the sole official network source: `who_am_i` approximately every **30 minutes** when a verified Host-owned Ready account has consent and the user has not disabled quota display. This implementation does not add an OAuth flow, client, timer, browser, or network request.
- The persistent Host reads the same `RDCRelayOwnerPilot/remote-usage-cache.json` file used by GUI every **15 seconds**, even when the GUI window is closed. It applies the same account match, provenance marker, 0–100 numeric bound, 60-minute age limit (future skew <= 2 minutes), and bounded file read. If the service is unavailable, the last verified value may persist until it expires; the UI must not pretend to update more frequently than the underlying service.
- Loss of Host-owned Ready identity, account switch or user quota-display opt-out clears the shown percentage at the next **250ms Host heartbeat**, without waiting for a 15-second cache read. Missing/expired/corrupt/wrong-account data becomes `--%`; a genuine **0%** displays `0%`.
- Tooltip/locale changes never reset the existing 40ms icon animation, allocate new icon resources, mutate machine states, or change Remote ownership.

## Isolated regression evidence

- `Test-V16TrayV04Visual.ps1` now tests official synthetic cache validity/expiry/account isolation, 73% -> 28%, 0%, invalid percentage, `--%` fallback, exact two separators and RU/EN language persistence. 49 approved icon frames and GDI resource-bound checks remain intact.
- `Test-V16OwnerTrayMenu.ps1`, `Test-V16ProductHostGuiSource.ps1`, `Test-V16OwnerQuotaFooter.ps1` and `Test-V16QuotaDisplayToggle.ps1` preserve existing contracts. **224 PASS / 0 FAIL across these five suites** as of the first run.
- No real OAuth, paid tool call, actual account data, installation, or running Desktop Commander Remote was used. Tests create only synthetic local temp files and an invisible WinForms NotifyIcon.

## Open validation

- In a future disposable Sandbox / Owner GUI build, confirm hover text at Windows scaling 100%, 125%, 150%, 200% and language switching. The currently open Sandbox is an older, immutable revision.
- Validate the 30-minute background refresh and 60-minute expiry under a real consenting account in a separately approved integration test. Never assume a fast UI repaint means a new service reading.
- The official `remote_calls_left_pct` field is **one source-provided metric**. It does not provide separate 5-hour and weekly values, so this tooltip must not claim it computes their minimum.

**Release GO remains closed.**
