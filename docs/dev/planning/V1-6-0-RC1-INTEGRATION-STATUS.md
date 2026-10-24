# PROG-006A-INTEGRATION — 1.6.0 RC1 G0 engineering checkpoint

**2026-10-24 · Programmer · [Draft PR #23](https://github.com/1rubass1/RDC-Relay/pull/23) · Branch:** \`feature/v1.6-host-gui-owner-pilot\` from verified \`development@fbc4527\`.
**Disposition: BLOCKED — NOT A USER-INSTALLABLE 1.6.0 RC1.** Do not deliver as an installer, switch STARMER or merge without further Architect and independent Reviewer gates.

## What has actually been implemented in production files

1. \`Source/RdcOwnerProcess.cs\` is a compilable production-source kernel seam for owner process evidence, lifecycle stop eligibility and a bounded monotonic event journal. Evidence pins PID, UTC birth ticks, Windows session, parent PID, exact install root, executable path and per-run ID; an Adopted or Unknown Remote is never eligible for stop. If a process is verified as Owned, the decision still requires **both** explicit owner OS-test authorization and user confirmation. The code has **no process start, stop, kill, WMI, credential, file-delete or Remote network side effects**. \`StopNotImplemented\` intentionally refuses the unapproved product stop.
2. \`Installer/Setup.cs\` and \`Installer/Launcher.cs\` have compile-only \`RDC_RC1_BLOCKED\` guards returning **42 before any actual payload transaction or process launch**. When the compile symbol is absent, stable semantics are unchanged.
3. \`Source/update.ps1\` explicitly refuses to run against any source folder containing \`rc1-candidate.json\` **before any network / installed-process operation**. Existing stable installations without this marker are not affected. \`Source/version.txt\` deliberately remains \`1.5.18\`; no \`1.6.0\` stable manifest is generated or published. \`Source/rc1-candidate.json\` carries the distinct \`1.6.0 RC1 / BLOCKED_PREINSTALLATION\` marker.
4. \`Scripts/build-rc1-preflight.ps1\` compiles a bounded evidence-only DLL and two **blocked** Windows executables into \`dist/v1.6.0-RC1-BLOCKED-PREFLIGHT\`. It validates a strict branch and blocked metadata and defaults to fake-only contract and deliberate failing-assertion checks; refuses an existing output folder instead of overwriting it. \`Scripts/pack-rc1-preflight.ps1\` verifies each member hash and creates a separate, **noninstallable** ZIP without user configuration, Remote credentials, stable updater, executable launcher activation, installer payload, service, autostart, release tag or network publishing.
5. \`Tests/Test-V16OwnerContract.ps1\` and \`Tests/Test-V16BuildIsolation.ps1\` provide reproducible fake-only process-evidence and static/hash/allowlist validation, with a negative failure-control in each.

**Not implemented:** an actual persistent production Tray Host supervising Desktop Commander Remote, a replaceable production WinForms GUI client backed by its Host state/event IPC, integrated production lifecycle/Remote controls, protected ownership of a real launcher tree, real GUI and update transaction across restart, and a functioning RC1 installer. **These are explicit blockers, not silently assumed complete.** No fake P3 Host/GUI was copied into production.

## Originating architecture and upstream Remote contract

Relevant project documents: \`TRAY-LIFECYCLE-DESIGN.md\`, \`ARCH-016-P0-HOST-GUI-BOUNDARY.md\`, \`ARCH-016-P1-HOST-GUI-IPC-CONTRACT.md\`, \`ARCH-016-P1-ARCHITECT-ASSESSMENT.md\`, \`PROG-005-PROCESS-OWNERSHIP-PLAN.md\`, and \`docs/dev/planning/V1-6-0-OWNER-PILOT.md\`.

Original upstream Desktop Commander Remote: [wonderwhy-er/DesktopCommanderMCP/src/remote-device/README.md](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md). Actual Remote agent runs locally with the invoking user's permissions, recommended command \`npx @wonderwhy-er/desktop-commander@latest remote\`; session data persists under \`~/.desktop-commander-device/device.json\`. Ctrl+C stops the agent while preserving credentials; \`remote --logout\` **deletes local saved Remote credentials** and is categorically forbidden as an app Exit shortcut. RDC currently pins \`@wonderwhy-er/desktop-commander@0.2.52\`. Documentation of upstream package evolution is not proof of safe Windows process-tree exit for this pinned version.

## Precise unresolved integration gates (no implicit permissions)

1. **Production Host ownership:** Move \`Find-ExistingRemote\`, \`Start-Remote\`, \`Stop-Remote\`, reconnect deadlines, \`Open-Reader\` and \`Read-LiveLog\` from the original GUI's owner context to the persistent Host. The monolith currently binds these functions to UI/global state; the new code must preserve 1.5.18 state and event/visual semantics. No new Host process managing live Remote has been started.
2. **IPC and GUI:** Evolve accepted fake-only P1/P2 contracts into an explicitly product-owned versioned, authenticated local pipe with OS-observed PID/session/birth, bounded frames/workers, replay windows/epoch, snapshots/event-gap recovery, and GUI/Host version skew handling. New GUI runs from current file in a separate process; X exits only its own GUI, Host and Remote state/log reader never die with X. Original visual control classes/animations/accounts/logs/updater behavior require regression confirmation. No unreviewed mock Host replacement is accepted as a production IPC implementation.
3. **Safe stop:** Legacy \`Stop-Remote\` uses \`taskkill /T /F\` and current GUI singleton has a no-HWND forced \`Stop-Process\` heuristic. Neither may control the pilot. \`Unknown\` and \`Adopted\` must fail closed; do not treat executable/PID-name matches as ownership. Before enabling Remote and full Exit, **owner must separately authorize** disposable OS-process tree tests from \`V1-6-0-RC1-OS-TRIAL-PLAN.md\`, including child-process birth/pid/path evidence, stopped/unknown/adopted, reusable PID and failed cooperative exit. No such tests were run under this task.
4. **Installer/updater:** The current \`build-release.ps1\` accepts only three-number versions; current Setup and Portable packaging embed a stable update payload and reuse stable install/shortcut/registry paths. RC1 must use a distinct install directory, mutex, per-logon pipe, icon/identification and pinned manifest, with update-feed publishing entirely disabled; stable \`1.6.0\` remains unpublished. The proof-only package intentionally cannot install and has no actual Remote payload.
5. **Real owner pilot:** Only an explicit G1 owner GO may authorize staging on STARMER and touching a live Remote. Until then **not checked**: real Remote PID/UUID continuity, physical X/tray/menu, GUI account/journal restoration, DPI/accessibility, candidate uninstall/install/rollback, cross-logon and SMB. Do not use an update or install path as a shortcut to perform these checks.

## Actual measured evidence (STARMER, Windows PowerShell 5.1)

| Check | Status and evidence |
| --- | --- |
| New owner-process safety contract | **17 PASS / 0 FAIL**, exit 0; deliberately wrong assertion exits **1** |
| Blocked-only preflight compile | **PASS, exit 0**; RdcOwnerProcess.dll, compile-symbol-blocked Setup and Launcher; no execution of either exe |
| Preflight archive | **PASS**; 7 allowlisted entries, all archive SHA-256 digests match source files; noninstallable marker confirmed |
| Package/source gate regression | **25 PASS / 0 FAIL**, exit 0; injected assertion exit **1** |
| Existing mock-only Remote characterization, classifier, process ownership, window lifecycle, UI lifecycle, update notice click+refresh, npx recovery | **8 PASS / 0 FAIL** |
| Historical PROG-004 classifier parity | **NOT CHECKED**: test requires explicitly supplied, SHA-256-pinned 003A original baseline; default no-arg invocation exits 1. An archived 003A branch's \`remote-window.ps1\` SHA-256 \`E658172F...\` does not equal test's pinned \`7D0BC553...\`; not an application regression verdict |
| Production real Host/GUI/live Remote integration | **NOT CHECKED / BLOCKED** — not implemented; no live changes |
| Disposable OS process-tree test, installer, true rollback, physical UX, published update feed | **NOT CHECKED / NOT AUTHORIZED** |

No claim of complete \`1.6.0 RC1\` candidate or G1 permission follows from a green static/fake-only suite.

## Safe eventual STARMER staging and rollback — procedure only, NOT EXECUTED

**Before G1:** obtain independent full-code REVIEW PASS, complete production Host/GUI/IPC and product ownership/Exit implementation, and an explicit owner GO for *both* disposable OS-tree trial and subsequent STARMER pilot installation. Collect a manifest of the existing 1.5.18 install directory, files and SHA-256, version, shortcut targets, process PID/birth/session and current Remote state **without logging credentials**; preserve the original installed tree, registered shortcuts, preferences, logs and \`~/.desktop-commander-device/device.json\` unchanged.

**Candidate staging (future authorization only):** use a separate owner-scoped \`%LOCALAPPDATA%\RDCRelayOwnerPilot\1.6.0-RC1\` directory, distinct AppUserModelID, mutex/pipe prefix, shortcuts only with opt-in, no autostart, no stable update manifest, no updating 1.5.18. Refuse symlink/reparse roots or unexpected files. Confirm full installer payload hashes before any launch. A real candidate shall display \`1.6.0 RC1\` unmistakably in every UI/about/status context.

**Pilot go/no-go:** verify no second real Remote was spawned, that the real verified Remote PID/birth/session/connection survives GUI X and a replacement GUI process, and that Host maintains monotonically ordered event/log state; exercise explicit Exit **only** for clearly owned and review-approved process trees. If the Host discovers an existing Remote of ambiguous ownership, preserve it and abort rather than adopting authority to kill.

**Rollback (future authorization only):** gracefully close only the verified candidate GUI/Host without touching unknown or adopted Remote, verify their own process exit using OS PID/birth, then return to unchanged original 1.5.18 launcher. Candidate files may only be removed after validating exact owner-scoped path, no live processes, no reparse points and a completed transaction. No deleting or resetting saved Remote credentials/account files or historic TEMP directories. If any process identity or stop route is uncertain, **stop rollback operations and escalate**; do not force-stop the real Remote.

**Current rollback:** none required because no candidate was installed or activated; production v1.5.18 remains unchanged.

## Handoff

\`PROG-006A-INTEGRATION\` is **blocked/partial**, not done. Reviewer should audit the G0 code and evidence as an explicitly non-deployable safety checkpoint. Architect must reassign substantial Host/GUI integration work and approve separate disposable OS-tree test rights before a deployable RC1 can be completed. Never merge this Draft PR as a completed RC1.


## 2026-10-24 — substantive PROG-006A-INTEGRATION follow-up (same Draft PR #23)

**Current disposition: PARTIAL real product-source integration, still NOT INSTALLABLE / NOT READY for live Remote or STARMER switchover.** This section supersedes G0's old statement that no product Host/GUI code exists. It does **not** certify that an actual OS Host/GUI lifecycle test or the real Remote integration has passed.

### Completed — G0 F1 (Reviewer + Architect blocker)

- `Scripts/rc1-package-integrity.ps1` provides strict **ordinal/case-sensitive**, 1:1 unique manifest, staging and ZIP filename coverage. Each expected file has one 64-character uppercase SHA-256, computed from staging; every ZIP member must match its own **manifest-attested** SHA-256 (the manifest entry itself is also hashed). Filesystem path components/reparse points, unknown directories/filenames, duplicate ZIP entries, wrong case and traversal names are denied.
- `Scripts/pack-rc1-preflight.ps1` validates before writing; creates a GUID-named incomplete archive and verifies all entries before publishing it via non-overwriting move. A `-FixtureRoot` parameter accepts **only** a direct `TEMP/RDC-RC1-F1-<GUID>` and is for negative tests, not a general arbitrary-path packaging command.
- `Tests/Test-V16PackageManifestNegative.ps1`: **16 PASS / 0 FAIL / exit 0**, real invocation of packer against newly generated disposable source copies, duplicate replacement, missing digest, edited bytes, rogue staged file, extra and duplicate ZIP entries, wrong case/path traversal. Tampered source leads to **nonzero packer exit and no trusted archive**.
- `Tests/Test-V16BuildIsolation.ps1`: **28 PASS / 0 FAIL / exit 0**, including the 16-case negative suite, exact set and hash validity. Legacy G0 no-overwrite policy remains. No old ZIP overwritten. Deliberately injected error still expected to exit nonzero.

### Completed — real product-source Host / original GUI split, but fake-only runtime

- **Persistent RC1 Host source:** `Source/rc1-tray-host.ps1` and `Source/RdcOwnerRuntime.cs`. Dedicated per-install/per-logon mutex, NotifyIcon and context actions; latest GUI is launched in a *new Windows PowerShell process* from the **actual full product `Source/remote-window.ps1`**, not from a copied P3 demo Form. Duplicate GUI activation is non-destructive, does not rely on a missing HWND as proof of a hang, and cannot force-kill a process.
- **Original GUI integration:** The full existing WinForms script gains `-OwnerGui -OwnerTicketPath` mode. It reuses the exact product controls/geometry, suppresses its legacy process/adoption/reconnection/updater/singleton side effects, identifies itself as **1.6.0 RC1**, disables real Remote/account actions, uses a distinct RC1 AppUserModelID and new `Source/rc1-owner-gui.ps1` as its host-bound state/event observer. Normal X exits only GUI in this mode; Host and its event revision persist by design. The old normal 1.5.18 path remains for unaffected installed stable builds; when an adjacent RC1 marker exists, accidental unflagged normal launch is explicitly rejected.
- **Protected local IPC:** `Source/RdcOwnerWire.cs` adapts the accepted length-prefixed Named Pipe transport into the product namespace/prefix. It uses logon-SID DACL, NETWORK denial, OS-observed pipe peer PID/session, PID UTC birth comparison, max 8192-byte request and 65536-byte response, 2 async workers and finite deadlines. Host dispatch checks actual spawned GUI PID/birth/session, private nonce, generation, version and monotonic request ID/sequence. Exposed verbs only `HELLO`, `GET_SNAPSHOT`, `GET_EVENTS`, `DETACH`. Bounded 128-event ring, 64-event page and gap/re-snapshot. GUI polling runs via background Task, not a synchronous WinForms Timer read. The ticket's DACL applies **before any secret bytes** are written.
- **Fake-only Exit:** In the fake-only Host, explicit confirmed exit signals the **own GUI** via a monotonically increased close generation; Host leaves its message loop only after that GUI exits. No actual Remote process is present. A future owned/adopted real-Remote full Exit **remains blocked** and is not covered by this behavior. No `taskkill /T /F`, `Stop-Process -Force` or `remote --logout` exists in the new Host IPC/Exit route.
- **No real Remote activation:** `Source/rc1-tray-host.ps1` requires explicit `-FakeOnly` and refuses by default. Any actual Remote supervisor, process adoption, log reader and account data flow remain out of service until separately authorized OS-tree trials. This is still a production-source integration path, **not** acceptance of fake state as a working real connection.

### Compiled product-source, packaging and measured results

| STARMER Windows PowerShell 5.1 check | Actual |
| --- | --- |
| New Host + protected IPC C# .NET Framework compilation | **PASS / exit 0**, compile-only, DLL never executed as Host |
| New/modified PowerShell parser for original GUI, owner GUI, tray Host, F1 scripts | **PASS, 0 parse errors** |
| `Test-V16ProductHostGuiSource.ps1` checks product-source wiring, guarded lifecycle, IPC/identity/connection-gap source contract plus compiler | **19 PASS / 0 FAIL, exit 0** (**static/compile only**, not actual GUI interaction) |
| Prior 8 mock/AST regression suites after changes to product `remote-window.ps1` | **8 PASS / 0 FAIL, each exit 0** |
| G0-F1 package/isolation | **28 PASS / 0 FAIL, exit 0**; separate 16 negative probes PASS |
| `Scripts/build-rc1-owner-staging.ps1` (original GUI + real Host source + IPC + four precompiled shaders + icon + updater code + compile-guarded Setup/Launcher) | **PASS / exit 0**, **18 allowlisted members**, staged in ignored dist only |
| `Tests/Test-V16OwnerStagePackage.ps1` source/ZIP exact manifest checks | **44 PASS / 0 FAIL, exit 0**, injected test error exit **1** |
| Repeat owner-source-stage builder (existing output) | **REFUSED / exit 1**, previous ZIP SHA256 unchanged |
| Owner-source review ZIP (NOT INSTALLABLE) | **160,010 bytes / SHA-256 `5BA94A0F048CB91E455FF179A2BA6778B54D540CA3442DD37D91463916048523`** |
| Actual dedicated GUI A→X→B, tray double-click, IPC resilience, process identity, Host PID persistence | **NOT CHECKED** — would create new OS process trees; separate owner authorization absent |
| Genuine Remote 0.2.52 ownership, stop/reconnect, log/updates, account status | **NOT IMPLEMENTED / NOT CHECKED**, do not contact live Remote |
| Standalone isolated **installable** Setup / Portable, verified installation and rollback | **BLOCKED / NOT CHECKED**, no owner G1 GO |

**The new 18-member archive is a review-only source/compile receipt, NOT a 1.6.0 RC1 installer.** No stable update manifest, old stable launcher, real log, credentials or device session files are included. Candidate marker remains `installable=false` / `publishable=false`, Installer/Launcher stay compile-guarded, and the stable feed remains unchanged. Original G0 preflight ZIP was not replaced.

### Remaining non-negotiable gates

1. **Remote and original state/log ownership:** the RC1 Host currently stores fake authoritative state and events. Migrate and test the actual monolith's `Find-ExistingRemote`, `Start-Remote`, `Read-LiveLog`, reconnect FSM, account/journal/update presentation and event continuity into Host **without** calling the old force-kill `Stop-Remote`. This is substantive engineering work still outstanding, not done by new C# scaffolding.
2. **Real IPC/WinForms execution verification:** compile/static source checks do not prove nonblocking timers, OS-peer PID/security under malicious peers, version skew, crash/rollback, real X and tray mouse or snapshot/event delivery. Reviewer/owner must approve and execute a narrowly scoped isolated process-tree test before permitting a GUI/Host run. No such new process-tree was run here.
3. **Safe full Exit for real Remote:** independently verify actual launch ancestry, Owned/Adopted/Unknown, PID reuse/absence, shutdown and failure reporting using separately owner-authorized disposable OS process trees. `remote --logout` removes saved credentials and is never a generic Exit. Review the exact pinned `@wonderwhy-er/desktop-commander@0.2.52` behavior; upstream latest README and release changes alone do not prove a graceful Windows Ctrl+C contract.
4. **True RC1 installer/portable:** separate version, path, AppUserModelID, mutex and pipe prefix are present in source; actual Setup transaction, auto-update suppression bound to installed root, rollback and G1 staged installation still need implementation, install/uninstall dry-run and independent review. The current blocked return code 42 remains active; never silently bypass it.
5. **Human gate:** actual RC1 UI, X/remote continuity, full Exit, DPI/accessibility, high contrast, owner visual comparison, real saved accounts and STARMER pilot **NOT CHECKED**. Publication of v1.6.0 or any stable update channel is prohibited until later owner GO.

**Safety:** No new RC1 Host or GUI process tree was launched. No real Desktop Commander Remote was started, adopted, stopped or reconnected; installed v1.5.18, `main`, `stable`, release manifests and three historic NOT CLEAN P1/P2 TEMP folders were not touched. No physical mouse interaction, Windows Explorer restart, system ACL/security-policy changes, install, publish or credential read. This continuation is offered for **one substantive independent integration review**, with **PARTIAL/NO-GO** explicitly recorded instead of a fictitious install-ready RC1.
