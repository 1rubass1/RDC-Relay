# RDC Relay — adopted engineering decisions

## RDC-ADR-001 — AI Engineering Playbook governance
**Accepted:** 2026-10-21, user. RDC Relay agents follow private AI Engineering Playbook read-only; role selection is per working chat. Architect owns architecture and cross-role coordination; Programmer, Designer and Reviewer join for their genuinely assigned scopes. Current task status is [COORDINATION/BOARD.md](COORDINATION/BOARD.md), not the historical worklog.

**Reason:** Durable handoff, clear responsibility and evidence-based reviews with minimum bureaucracy.

## RDC-ADR-002 — Versioned, classified project knowledge
**Accepted:** 2026-10-22, user. Consolidate relevant project documentation into the **existing** RDC Relay GitHub repository following the Playbook's `PROJECT_INDEX`, `PROJECT_CONTEXT`, `DECISIONS`, `COORDINATION/BOARD` structure and categorized `docs/dev`. Keep only **one editable authoritative current** location for each fact. Reconcile stale roadmap/status notes; preserve source documents as frozen, clearly non-authoritative history.

**Reason:** Agents operating from GitHub should be able to recover state without local-only STARMER notes. Migration preserves byte-exact originals locally and includes sanitized copies for historical traceability. The dev documentation is a change to development workflow, not application behavior.

## RDC-ADR-003 — Dev-only branch and release/data boundary
**Accepted:** 2026-10-22, user. Use long-lived `development` branch since `develop/*` exists and Git cannot contain both refs. The project knowledge base and Pen design belong **only to development branches**; `main`/`stable` release commits and release artifacts must exclude them. Release preparation must select shippable files explicitly, not merge development wholesale.

**Security qualification:** RDC Relay GitHub is **public**, so development branches are public. No real credentials, private tunnel IDs, active endpoints, sensitive user/device/account data or unredacted logs in any Git branch. Such material stays in authorized protected local stores. Existing `Scripts/build-release.ps1` explicitly whitelists product payload; validate built artifacts before every release.

## RDC-ADR-004 — Stabilize existing core incrementally before new provider
**Accepted:** 2026-10-23, owner. **Scope:** gradual *behavior-preserving* improvement to RDC Relay's existing supervision, process ownership and transport-status derivation, with regression characterization **before** refactoring.

**Decision:** Do not rewrite the existing 6,676-line PowerShell GUI, switch language/runtime, revise visual design or introduce a second `ConnectionProvider` prematurely. First obtain deterministic isolated tests for current lifecycle/log/state behavior, then extract minimal pure observation parsing and explicit process ownership boundaries in separately verifiable steps. Preserve release v1.5.18 and functioning Remote until independently validated candidate. Do not alter `main`/`stable` or published payloads in a documentation/planning task.

**Reasons:** Reduces risk of breaking production or killing user processes while introducing testable seams needed by a later self-hosted transport. Stop if behavior changes without an approved requirement. Implementation details and gates: [current roadmap](docs/dev/planning/ROADMAP.md), [2026-10-23 audit, draft PR #3](https://github.com/1rubass1/RDC-Relay/pull/3).

**Not decided:** A self-hosted gateway, active network exposure, specific parser/event interface, paid provider, model configuration or delegation of CLI executors. Each requires appropriate evidence and authorization. The user's original goal of an unmetered-by-Remote transport remains intact.

## RDC-ADR-005 — Hide RDC Relay window to system tray, keep Remote active

**Accepted direction:** 2026-10-23, owner. Normal user **X** should dismiss the visible RDC Relay window into the Windows notification area without stopping the existing Remote process **or** the background GUI-host supervisor. An icon in the tray opens the **current live window** again. At the decision's original capture, PROG-005A had not started; its mock-only baseline and independent review were subsequently completed and accepted in development. Tray/runtime implementation has not started.

**Superseding owner clarification — 2026-10-23 (development workflow):** ordinary X must **actually close/dispose the GUI instance** so a programmer can edit GUI code and reopen a **fresh instance built from the modified source**, while the *existing* Desktop Commander Remote process continues uninterrupted. Reopening a hidden Form created from the old script does **not** satisfy this requirement. A durable tray host and Remote lifetime must therefore be independent of the replaceable GUI instance; the exact process/IPC split requires separate Architect design and independent safety proof. The goal is rapid GUI iteration **without restarting Remote**. This supersedes the original same-Form Hide/Show implementation recommendation below but does not change the previously approved explicit tray Exit = verified full managed shutdown. No Source implementation approved yet.

**Prior implementation idea (SUPERSEDED):** WinForms `NotifyIcon` + cancellation of `FormClosing` and `Form.Hide()`/`Show()` on the same instance. That approach preserves an old GUI implementation in memory and is **not acceptable as the final development workflow**. Standard Minimize remains unchanged.

**Safety gates:** existing single-instance fallback uses `MainWindowHandle=0` after ~5 seconds as a reason to force-stop a GUI peer. This heuristic is **incompatible with an intentionally hidden window**. Before shipping tray behavior, make duplicate launcher handling **non-destructive**, preferably same-user IPC reactivation; no live process kill. Add isolated tests for X, restore, updater/WindowsShutdown and second launch while hidden, with Reviewer and owner UX acceptance.

**Owner clarification — accepted 2026-10-23:** the explicit tray command **«Завершить RDC Relay» means COMPLETE SHUTDOWN**: stop the currently managed Remote and its **verified belonging** launcher/child processes, stop supervisor and UI timers/readers, dispose NotifyIcon and exit RDC Relay. **No RDC Relay-managed Remote must intentionally remain running.** This is distinct from normal X → Hide and is **not `remote --logout`** (preserve credentials). Both Owned and positively identified Adopted Remote are in scope **only after identity verification and a safe stop contract**; external/ambiguous/unrelated processes must never be killed. If stop fails/ownership is uncertain, report incomplete shutdown and do **not** silently exit leaving an unmanaged Remote. Owner approval is of **desired behavior**, not approval for today's unchecked `taskkill /T /F`. Disposable OS-process safety tests, Reviewer and implementation gates remain required.

**Trace:** [Tray lifetime contract](docs/dev/architecture/TRAY-LIFECYCLE-DESIGN.md), [ownership safety plan](docs/dev/architecture/PROG-005-PROCESS-OWNERSHIP-PLAN.md), [board](COORDINATION/BOARD.md).

## Pending architectural decisions
- Whether ChatGPT custom MCP / Sites can securely access the owner's environment: actual entitlement and authenticated end-to-end route unproven.
- Provider architecture and concrete auth/transport choices remain conditional on a controlled GO/NO-GO research gate, not endorsed by migration.
