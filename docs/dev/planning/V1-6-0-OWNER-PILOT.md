# RDC Relay 1.6.0 — implementation, owner pilot and release gates

**Architect decision, 2026-10-24.** Owner wants to stop repeating fake-only prototypes, integrate the proven persistent Host + independently replaceable GUI into actual RDC Relay, install a candidate on **STARMER** for hands-on pre-release use, and consider **v1.6.0** as the next stable baseline **only after an explicit owner GO**.

## Current truth

- Published, installed production baseline: **v1.5.18**. Preserve installer/build, user settings, real Remote and a reversible rollback path.
- [P1/P2 fake-only research](https://github.com/1rubass1/RDC-Relay/pull/20) accepted in `development`. [P3A independent review](https://github.com/1rubass1/RDC-Relay/pull/22#issuecomment-6384285982) is PASS for the isolated owner-demo F1/F2 corrections (28 cleanup PASS, 9 owner-switch PASS, visible GUI 11 distinct processes, 20/20 portable ZIP source-member hashes). **P3 has not demonstrated real Remote continuity, physical owner mouse/UI acceptance, or execution of a freshly extracted ZIP.**
- Do not transplant `Tests/` into production or claim that a fake Remote UUID proves a real `@wonderwhy-er/desktop-commander@0.2.52` connection can survive GUI replacement. Validate upstream lifecycle against original Desktop Commander Remote documentation before enabling actual management.
- Existing production `Source/remote-window.ps1` has hazardous force-kill/singleton and ambiguous adopted-process shutdown paths. Never use the old `Stop-Remote` or `taskkill /T /F` as the implementation of full tray Exit. No owner pilot with unsafe Exit semantics.
- Three historical P1/P2 TEMP artifacts are NOT CLEAN and require separate owner permission for any cleanup. Not related to version 1.6 installation.

## Versioning

**Next stable target: RDC Relay v1.6.0.** Keep that tag and the stable update channel **unpublished** until owner approves after a live pilot.

**Owner pilot label: 1.6.0 RC1** (candidate identity must be displayed unambiguously in the GUI, build and logs; never masquerade as the publicly released stable 1.6.0). Current `Scripts/build-release.ps1` accepts only three-part numeric `Source/version.txt` values and current updater/manifest are tied to a stable channel. Therefore **do not simply put `1.6.0-rc.1` in `version.txt`** and expect the builder to work. Implement and test an explicit candidate-build path/metadata and update suppression or separately prove compatible prerelease parsing across builder, launcher and updater. No release tag/GitHub release/production manifest/update feed from a candidate.

## One implementation stream, not another fake-prototype chain

**Proposed workstream: PROG-006A-INTEGRATION / v1.6 candidate** on a *new topic branch from verified current `development`*, as a Draft PR. Programmer can modify the actual product source/launcher/installer/updater **in the topic branch only**, with first executions against disposable Remote stand-ins; no installed product or live STARMER Remote operations. Keep 1.5.18 behavior covered by before/after characterisation and preserve original public visual design/labels.

1. **Separate running process ownership:** persistent tray-owning Host with one replaceable GUI process. Normal X terminates only GUI; tray Open relaunches current GUI and rehydrates actual Host state/events; Minimize is not X. A broken GUI must not kill Host, restart Remote, lose log state or create a second supervisor.
2. **Actual Remote integration contract:** preserve exactly one verified owned/adopted Desktop Commander Remote and per-logon IPC; OS peer PID/session/birth identity; nonce/ACL/replay and bounded state queue; handle Host/GUI protocol skew, crash/restart and update. Test using fake Remote first, then separately owner-approved actual Remote trial only when safe. Do not take over or stop an existing active Remote merely because it matches a process name.
3. **Exit/ownership blocker:** before a candidate can control actual Remote, separately reproduce OS process-tree ownership/stop scenarios using only new disposable stand-ins with PID/birth/path proofs. Adopted/Unknown cases must fail closed; owned stop must be cooperative where possible and verified; no broad `taskkill`, no forced stopping of unrelated or live Desktop Commander processes, no implicit logout. Explicit tray **«Завершить RDC Relay…»** has the owner's agreed full managed-shutdown meaning and cannot be shipped as dummy Exit.
4. **Packaging and rollback:** update the explicit source/Setup/Portable ZIP/manifest allowlists for the new Host + GUI binaries/scripts, update/relaunch transaction and singleton logic. Isolate candidate deployment folder/mutex/IPC identities/update channel from installed v1.5.18. No automatic replacement, autostart, scheduled job, credential migration, public port or update-feed publication in a candidate build. Make a restore/rollback plan for 1.5.18 without deleting user accounts/credentials or unverified process trees.
5. **Independent focused review:** run legacy GUI/parsing/process/update regression suites, real Windows interactive X/tray/context menu/DPI checks in a sandbox, package and install/rollback dry run, process identity and negative/adversarial IPC gates (including cross-logon/SMB only in separately approved safe environment). Report explicit PASS/PARTIAL/NOT CHECKED; do not require the owner to adopt unsafe security bypasses to run extracted files.

## Deployment decision gates

| Gate | Authorized action | Not authorized |
| --- | --- | --- |
| G0 — now: coding | Design and implement v1.6 candidate in topic branch; fake/disposable process tests; document complete installer/rollback approach; independent Reviewer checks | No changes to installed RDC Relay, current real Remote, `main`/`stable`, public release or update channel |
| G1 — after candidate + safety PASS and owner permission | Back up known 1.5.18 installation/configuration, perform a deliberate **STARMER-only** switch to 1.6.0 RC1, inspect actual Remote/session and UI, provide exact rollback instructions | No force stop of unknown processes, unattended installation, automatic rollout or published stable tag |
| G2 — owner acceptance after a real pilot | User confirms physical X, tray open/Exit, real Remote continuity, account/journal state, updater and usability; resolve any blocking defect in candidate, independently review | No claim of stable 1.6.0 on green mock tests alone |
| G3 — **explicit second owner GO** | Promote reviewed candidate to stable `v1.6.0`, selectively release-eligible commits/files to `main`/`stable`, signed/hashed Setup + Portable + manifest and actual release asset audit | No bulk merge of dev docs/Tests into production; no publish without owner authorization |

**Important:** The owner's current statement approves the **direction of preparing v1.6 code/candidate** but not installation on STARMER, termination/restart of its live Remote, changes to installed software or publication of a stable release. Ask for an explicit, separate installation/switchover GO when the candidate is actually ready. Do not treat passive research acceptance as that permission.

## Completion target for the next Programmer assignment

Deliver a Draft implementation PR containing a **product-source integration**, not another test-only `Tests/Prototypes` preview, a buildable 1.6.0 RC1 **isolated candidate**, safe faux/OS ownership tests, release allowlist and rollback evidence, and a concise readme for the owner. If actual Remote or installation cannot yet be safely demonstrated, expose and document the specific blocked condition; stop before user-process operations. No new release branch/tag without owner GO.
