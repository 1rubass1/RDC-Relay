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
