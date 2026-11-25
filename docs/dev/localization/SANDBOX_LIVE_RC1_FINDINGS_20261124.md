# RDC Relay 1.6.0 RC1 — network Sandbox manual QA, 2026-11-24

**Scope:** live disposable Windows Sandbox, code-review diagnosis of user-reported UI defects, source-only corrections and independent tests. **Not a public release or production installer validation.** The owner explicitly requested that this Sandbox remain running for further manual tests.

## Live guest baseline and reproducible evidence

- Sandbox kit (outside Git): `[local project root]\_archive\RDC_NET_RC1_89e7fc0_20261124`.
- Current running RC1 guest Setup SHA-256: `FB09998A99C72CDFCF44336F5B2A1E55338865543FC3E581B233257FCD37A0B5`. It was built from clean source commit `89e7fc0` and is **older** than the corrections described below.
- Guest 1.5.18 installation verified (HKCU Installed Apps + disk version). RC1 pilot Setup installs private Host/GUI and intentionally preserves the 1.5.18 Installed Apps identity; this is **not** a full transactional public 1.6.0 upgrade.
- `Networking=Enable`, `vGPU=Disable`; there is **no mapping** for host Desktop or host account data. A separate host-backed `Output` is writable only for reports, `Input` read-only. Original bootstrap records `DNS_MCP=true`, `TCP443_MCP=true`, `HTTPS_MICROSOFT=false`; the last result was a PowerShell HTTP check failure, not proof that Remote services are unreachable.
- Screenshot `Sandbox-Capture-ReadOnly.png` outside Git was obtained via read-only PrintWindow of the already-open Sandbox HWND. It shows a wide **white bar at the 7px movable divider and overlapped decorative area**, two apparent surface layers disappearing during a drag, a connection fault, a Russian event history, and bottom `не определён` account placeholder. No user controls, account or Remote state were changed to capture it.
- GUI activity history visibly contains `managed action denied: FileNotFoundException`. In the accepted Host source, `RdcOwnerRuntime.ResolvePinnedNpx()` checks exactly three allowed locations for `npx.cmd`, then throws `FileNotFoundException("RC1_PINNED_NPX_MISSING")` if none exists. The fresh Sandbox was bootstrapped with 1.5.18/RC1 installers **without Node.js**, so missing pinned `npx.cmd` is the leading explanation of this error. Actual guest-path check remains pending, see helper below. **Do not claim an authenticated Remote session or a successful connected test.**

## Localization analysis and code changes

1. `Source/remote-window.ps1` rendered the unknown footer account as the hardcoded Russian text `не определён`. Owner mode now obtains `gui.account.unknown` from the validated RU/EN resource; legacy UI retains the original literal.
2. `Source/rc1-owner-gui.ps1` now re-renders that placeholder **on language switch only when no account email is known**, while preserving real email text byte-for-byte. It localizes the account-info tooltip via `gui.account.infoTooltip`. RU/EN resources contain `не определён` and `Not identified`.
3. The lower activity pane and Help → Show Journal **retain existing historical lines in the language in which they were added**. This is deliberate: `Format-Rc1JournalLine` translates a newly received sanitized Host event; `Add-CompletedEvent` and `Add-Rc1OwnerDetailedEvent` keep its original rendered text. The `получено / received` receipt phrase is likewise recorded once per event; changing old records retroactively could misrepresent audit evidence.
4. New Host action acknowledgements (account switch accepted, action confirmed) were a real source of **new untranslated Russian events** even when English was selected. They now use `journal.ack.switchAccountAccepted` and `journal.ack.actionConfirmed` bilingual display keys, with the validated action code left unchanged.
5. `Show Journal` currently provides a bounded, sanitized authenticated Host/Remote diagnostic history (up to 512 event lines with GUI receipt times), not raw stdout or a PowerShell terminal transcript. Direct raw Remote stdout may contain paths, arguments, tokens or other private data. Any future raw diagnostic viewer/export requires separate opt-in, proper redaction and sandbox tests; do **not** silently change the existing security boundary.

## Software render fallback

Windows Sandbox was launched with `vGPU=Disable`; Microsoft documents that this uses WARP software rendering rather than virtual GPU. The current Owner shader uses WPF `ShaderEffect` and an independent layered `Popup` HWND to compose the moving caustic/particle glow; its initialization checks only shader-file presence, not graphics capability. On a low render tier, a popup may appear as an opaque white rectangle, consistent with the owner's screenshot. This remains a **working graphics diagnosis** until the guest WPF render tier is measured.

- `Source/remote-window.ps1` now checks `[System.Windows.Media.RenderCapability]::Tier >> 16` **in Owner mode only**. Tier 0/1 or a failed tier query disables the WPF GPU object and its popup before construction.
- The existing **7px draggable WinForms divider** then paints a dark-bordered, orange-to-purple GDI+ gradient. It uses no layered popup, no animation timer and no Remote interactions. Hardware tier 2 keeps the existing shader unchanged. A shader initialization failure after a permitted tier still falls back to a native painted divider.
- No intentional change to mouse-up geometry, saved pane heights, modal-window logic, historical GUI 1.5.x behavior or Host state/IPC.
- `Tests/Test-V16GpuSoftwareFallback.ps1` renders the **real Owner Paint handler** into an off-screen bitmap and checks colored ends, dark border, absence of white pixels, unchanged legacy look and preserved drag route. `Tests/Test-V16GpuModalOcclusion.ps1` continues covering actual WPF modal behavior.

## Safe guest diagnostics and prerequisites

The mapped guest input contains `Check-Rdc-Guest-Diagnostics.cmd`, which only reads presence/absence of pinned Node shim files, WPF render tier, and whether a UI error file exists. It writes `Output/rc1-sandbox-diagnostics.txt` on STARMER. It does not copy raw Host logs, secrets, process arguments or device identifiers, run installers, touch Remote or close the VM.

The official Node.js **26.13.1 LTS x64 MSI** from `https://nodejs.org/dist/v26.13.1/node-v26.13.1-x64.msi` was downloaded **to the Sandbox Input folder only**, not installed on STARMER or in the guest. SHA-256 matched the upstream published `0398ced8446e119478c724d1aa37c5afd6aa1a76fceab12787eb9714c5ed8b45`; Windows Authenticode status was `Valid` for OpenJS Foundation. If the guest diagnostic confirms missing Node, the owner can manually open the guest-mapped MSI and then use the existing RC1 Start button. This is guest-only functional dependency provisioning, not a release dependency solution or automatic credential pairing.

## Tests / remaining acceptance

- 10 source-level suites: **299 PASS / 0 FAIL** (account footer, software fallback, RU/EN Owner GUI language and journal, fallback banner, GPU modal lifetime, header layout, Host source compile, Russian header status).
- Current locale index reproducible: **266 keys per language, 256 source-bound, 10 intentionally unwired**, `Audit-Remaining68.py` PASS, `Check-V16OwnerI18nBindingCoverage.py` PASS.
- Pending: manual guest execution of the diagnostic helper; confirming WPF Tier and `npx.cmd` absence, installing Node in Sandbox, actual Remote OAuth/connection, tier-2 vGPU screenshot comparison, full updated RC1 package/reinstall in the *existing* Sandbox **only after the owner closes the old RC1 Host normally**, and real user visual acceptance. Do not close the active Sandbox to satisfy a test.
- Public installer, rollback of registered Windows metadata and stable update feed are still out of scope. The installed STARMER client and any live Remote were not modified by this task.

**No release GO. No Github push or modification of stable-update filters.**
