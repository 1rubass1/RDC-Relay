# ARCH-017 — Architect disposition of REV-006A-INTEGRATION-G0

**Date:** 2026-10-24  
**PR:** [#23 — real v1.6 owner pilot integration](https://github.com/1rubass1/RDC-Relay/pull/23)  
**Reviewer:** [REV-006A-INTEGRATION-G0 / CONDITIONAL PASS](https://github.com/1rubass1/RDC-Relay/pull/23#issuecomment-6386986262)  
**Status:** G0 safety preflight accepted **conditionally and as noninstallable evidence only**; full `PROG-006A-INTEGRATION` remains **IN PROGRESS / NOT INSTALLABLE**; PR #23 stays Draft / NO MERGE.

## 1. Review evidence and decision

Independent STARMER Windows PowerShell 5.1 Reviewer execution: `Test-V16OwnerContract.ps1` **17 PASS / 0 FAIL / exit 0**; `Test-V16BuildIsolation.ps1` **25 PASS / 0 FAIL / exit 0**; deliberate wrong assertions exit 1; eight inherited fake/AST-only regression suites each exit 0; repeated build and packaging refuse to overwrite; candidate updater refuses early; stable Setup and Launcher compile without the blocking define. Reviewer verified seven archive member hashes but did not execute Setup, Launcher, install a candidate or contact real Remote. Historic PROG-004 pinned parity remains NOT CHECKED because a trusted archived source digest was unavailable.

The only **new actionable G0 finding F1** is that `Scripts/pack-rc1-preflight.ps1` and `Tests/Test-V16BuildIsolation.ps1` validate manifest entry counts and allowlisted membership without **unique exact-set digest coverage**. One duplicate allowed entry can replace another required digest while keeping the count unchanged. The initial archive contains correct files, but accepting the scheme as a release integrity gate without negative tests would be wrong.

**Architect decision:** accept G0's protective, deliberately noninstallable intent, **do not merge as complete RC1**. Do **not** create a standalone packer-only Programmer → Reviewer → Architect loop. Incorporate the narrow F1 correction **as the first merge-blocking checkpoint in the same substantive product Host/GUI integration workstream**, followed by one independent implementation review of all completed work. The next task is not another `Tests/UserDemo` or fake-only PR.

## 2. Required G0-F1 correction (first deliverable in existing PR #23)

1. Enforce manifest `files` **exactly once for every allowlisted file**, with ordinal/case rules documented, no duplicate names, no missing entries, no extra members, no empty/malformed SHA-256, and no redirection via paths/reparse points. Require exact set equality for staging and ZIP, not just `Count` or allowed-member subset; every ZIP entry must have exactly one attested manifest digest and a matching freshly computed SHA-256.
2. `Test-V16BuildIsolation.ps1` must independently assert that exact names and digests agree across manifest/staging/ZIP. Add disposable tampered-manifest negative cases: one allowed name duplicated and another missing; unexpected archive entry; changed member hash. Assert nonzero and **no trusted output ZIP success**; preserve existing unrelated artifacts. For the existing preflight packer, require a distinct fresh test output root rather than overwriting retained dist files.
3. Preserve the `RDC_RC1_BLOCKED` Setup/Launcher fail-closed behavior and `RC1_UPDATE_BLOCKED` updater marker. No execution of installable user software or update feed.

## 3. Main implementation, not another prototype

Continue **PROG-006A-INTEGRATION** in `feature/v1.6-host-gui-owner-pilot` / Draft PR #23. Owner's priority is a concrete private 1.6.0 RC1 for later STARMER pilot, not repeated safe-but-inert receipts. Programmer should make actual changes under `Source/`, launcher, installer, update transaction, as needed. Isolated tests MUST use dummy Remote and synthetic accounts/logs only until a later explicit authorization.

**Minimum integration deliverables:**

- **Persistent product Tray Host** owns monitoring, log reading, reconciled Remote/process identity and state independent of GUI; no second Host/Remote from relaunch. Ownership decision seam must be bound to OS-observed identity before any destructive operation, not merely synthetic claims.
- **Replaceable product GUI** preserving existing RDC Relay visual structure and labels, account/status/terminal/journal and update presentation. Normal X really exits GUI process, not `Hide/Show`; double-click/context menu opens a new process from current code; Host and fake Remote session/log cursor persist across A→B. No duplicates, no long blocking WinForms IPC calls, bounded reconnect/version mismatch paths and gap/event recovery.
- **Secure Host↔GUI contract** derived from P1/P2 but adapted to product, OS PID/session/creation identity, ACLs, bounded frames/timeouts, replay/generation, explicit verb authorization, source/install path pinning and tests. No assumed production security based solely on fake-only P1 passes.
- **Safe owned/Adopted/Unknown Remote rules**: existing monolithic `taskkill /T /F` and no-HWND `Stop-Process` heuristic cannot become Host stop/Exit. Unknown/Adopted/mismatched must not be killed. Explicit `Завершить RDC Relay…` means full verified managed shutdown; do not ship dummy Exit or claim success with an orphan. Put stop behind fail-closed gate until separate disposable OS-tree tests and owner approval. Do not call `remote --logout` as Exit.
- **Real candidate packaging path** (once engineering guards are proven) must produce separately identified private `1.6.0 RC1` Setup/Portable payloads with Host, GUI, explicit manifests/digests, launch and rollback logic; isolate install path, IPC/mutex, shortcuts and update feed from v1.5.18. An inert `RDC_RC1_BLOCKED` ZIP is not an installable candidate; don't silently remove the block ahead of safe acceptance. Avoid writing stable `1.6.0` release artifacts/tags/channels.

**Code/acceptance stages within ONE workstream:** first F1 and exact package tests, then Host/GUI+IPC against fake Remote, then independently review product-source behavior and non-destructive installer dry-run; provide explicit outstanding conditions before the Owner is offered G1 STARMER install. Do not spin off an additional generalized fake-only research program.

## 4. Hard approval gates retained

**Not authorized now:** disposable Windows process-tree OS trials (distinct from existing fake tests), real Remote start/adopt/stop/logout/reconnect, installation/switchover on STARMER, touching installed RDC Relay 1.5.18/credentials/logs, production `main`/`stable`, public update feed or publishing v1.6.0. Prepare the narrowly scoped OS test plan but seek **separate explicit owner GO** before executing it. Afterwards require independent safety review and another explicit owner G1 for candidate installation. Never bridge these authorizations.

Actual process ancestry, cooperative exit and life of pinned Desktop Commander Remote v0.2.52 must be validated; current upstream `main` documentation is only guidance, not a proof of pinned Windows behavior. Don't bypass local security restrictions or touch working Remote to manufacture a green result.

**Historical NOT CLEAN:** two older P1 TEMP roots and unknown-provenance P2 TEMP root remain untouched; no ACL/ownership/deletion/elevation authorized. RC1 must retain v1.5.18 rollback baseline. User's eventual **stable v1.6.0** approval is **after** a successful owner pilot, not implicit in engineering authorization.

## 5. Handoff and Reviewer scope

**Next:** Programmer continue existing `PROG-006A-INTEGRATION` on **same PR #23**, starting G0-F1; prioritize the real persistent Host/replaceable original GUI and the isolated candidate packaging path. Provide real source diffs, selftest and negative evidence, builds and exactly documented remaining blockers. An independent Reviewer reviews the integrated candidate once a meaningful implementation is ready, rather than independently approving an isolated F1-only micro-PR. PR #23 remains Draft and is not installable in its current form.
