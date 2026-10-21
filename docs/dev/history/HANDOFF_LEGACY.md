> **LEGACY IMPORT, not current instructions.** Source: HANDOFF.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Handoff / Start Here

> **Newest 2026-10-20 handoff:** User screenshot confirms `Новый плагин`
> archive upload and separate `Создать MCP-приложение` button. The actual
> account permission to create a remote custom MCP app is NOT yet verified.
> Official docs distinguish external custom MCP (Business/Enterprise/Edu
> workspace permission path) from Plus/Pro-capable ChatGPT Sites-hosted
> plugins. A Site cannot reach private STARMER by magic; a secure transport
> is still needed. OpenAI's public demo MCP `roll_dice` was independently
> invoked from STARMER with PASS. The temporary public RDC ping tunnel was
> dismantled in the previous session. Full interpretation and next steps:
> `CHATGPT_PLUGIN_UI_REVIEW_2026-10-20.md`.
> Continue research/user-approved connectivity tests when user returns.
> Do NOT start 1.6 production refactor or change active Remote.


> **2026-10-20 latest experimental transport checkpoint:** Direct HTTPS
> public ingress via temporary Pinggy tunnel passed MCP initialize/list/call
> for a harmless ping. A separate Bearer-gated ping endpoint passed
> missing/wrong/correct-secret checks. **Not yet proven:** a ChatGPT
> custom MCP plugin connecting from this user's workspace or a production
> OAuth 2.1 security architecture. Official Cloudflare Quick Tunnel binary
> installed only in the experiment folder, but edge connection failed due DNS
> SRV lookup. See `SPIKE_1_DIRECT_HTTPS_MCP.md`.
> Keep v1.5.16 and production Remote untouched; never expose local execution
> tools via public temporary ping-only ingress.


> **2026-10-20 transport checkpoint (supersedes older "immediate next" wording):**
> OpenAI Tunnel Spike 0 was blocked at ChatGPT workspace access.
> Isolated **Direct HTTPS MCP Spike 1** has now passed LOCAL Streamable HTTP
> and local HTTP→stdio DesktopCommanderMCP fixture-read tests. The PUBLIC HTTPS
> + authenticated ChatGPT end-to-end test has **not** been done.
> New current experiment: `SPIKE_1_DIRECT_HTTPS_MCP.md`;
> sandbox: `_experiments/direct-https-mcp`.
> Continue with secure ingress/auth feasibility, NOT provider refactor or
> production UI changes; preserve stable v1.5.16.


> Этот файл предназначен для нового ChatGPT-чата или нового агента.
>
> Если контекст предыдущих разговоров потерян, начать с этого файла.

---

# 1. Project identity

Project:

```text
RDC-Relay
```

Development machine:

```text
STARMER
```

Project root:

```text
E:\Projects\GitSync\RDC
```

Active Git working tree:

```text
E:\Projects\GitSync\RDC\RDC-Relay Work
```

Archive:

```text
E:\Projects\GitSync\RDC\_archive
```

Strategic project documents (`HANDOFF.md`, `ROADMAP.md`, `TECHNICAL_DESIGN.md`, `SOURCES.md`, `SPIKE_0_OPENAI_TUNNEL.md`) live directly in the **project root**, not inside the active Git checkout.

GitHub:

https://github.com/1rubass1/RDC-Relay

---

# 2. Current production baseline

Published version:

```text
1.5.18
```

Existing RDC Relay installations on STARMER and workplace PCs were **not** replaced by the release workflow. A running client relaunched with `-SkipUpdate` on v1.5.16/v1.5.17 cannot install by clicking the update notice because of the fixed bug; close and reopen normally to trigger the regular startup updater, or install the released Setup. Closing RDC Relay disconnects Remote MCP temporarily.

Commit:

```text
5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb
```

Production release:

https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.18

Production branches/tag (verified 2026-10-20):

```text
main
stable
v1.5.18
```

Both `main` and `stable`, as well as annotated tag `v1.5.18`, point to `5b1fdf5`. Published release is non-draft, non-prerelease; Setup EXE and Portable ZIP have verified matching SHA256 digests. v1.5.18 fixes the update-notice click ignored on `-SkipUpdate` sessions; regression testing confirms that a visible older version is replaced by the newer stable version on the next background poll (normally about one hour), without replaying an unchanged offer. Previous `v1.5.17` at `a86fef5` remains available. Keep v1.5.12 (`4e47cee`) and v1.5.15 (`eace20c`) as historical reference points.

Current Desktop Commander package pin:

```text
@wonderwhy-er/desktop-commander@0.2.52
```

Do not move or rewrite the existing v1.5.12 tag.

---

# 3. Read these documents in order

1. `HANDOFF.md` — stable project identity, baseline and durable rules.
2. `WORKLOG.md` — current/incomplete work, recent changes, blockers and exact next step.
3. `ROADMAP.md` — what to do and in what order.
4. `SPIKE_0_OPENAI_TUNNEL.md` — immediate next experiment.
5. `TECHNICAL_DESIGN.md` — target architecture and contracts.
6. `SOURCES.md` — verified external references and what they support.
7. `README.md` / `CHANGELOG.md` — current product behavior/history.

---

# 4. What RDC Relay is today

RDC Relay 1.5.16 is **not an MCP client**.

It is a Windows GUI/supervisor around:

```text
npx --yes @wonderwhy-er/desktop-commander@0.2.52 remote
```

It supervises:

- process lifecycle;
- authentication/connection state;
- remote-session log;
- tool activity;
- transport/local MCP failures;
- automatic recovery;
- account actions;
- UI state.

Current architecture:

```text
RDC Relay UI / supervisor
        │
        ▼
Desktop Commander Remote Device
        │
        ▼
Desktop Commander Remote hosted MCP
        │
        ▼
ChatGPT
```

Local execution ultimately uses DesktopCommanderMCP.

---

# 5. Why the architecture is changing

Desktop Commander Free Remote currently advertises:

```text
10,000 tool calls/month
```

Desktop Commander's local MCP server is advertised as free/open source/no monthly limit.

The project is therefore investigating a transport path that keeps the local DesktopCommanderMCP execution engine but does not send every tool call through Desktop Commander Remote:

```text
ChatGPT
   ↓
OpenAI Secure MCP Tunnel
   ↓
tunnel-client on STARMER
   ↓
local DesktopCommanderMCP
```

This must be proven before refactoring production.

---

# 6. Major design decision

Correct abstraction:

```text
ConnectionProvider
```

Not:

```text
CommanderBackend
```

Reason:

RDC Relay manages connection lifecycle, health and recovery. It does not directly implement filesystem/shell tools.

Planned providers:

```text
DesktopCommanderRemoteProvider
OpenAITunnelProvider
later: ZrokProvider
```

---

# 7. Immediate next task

**Do not start by editing remote-window.ps1.**

First execute:

```text
SPIKE_0_OPENAI_TUNNEL.md
```

The spike is intentionally outside production integration.

Goal:

```text
ChatGPT
→ OpenAI Secure MCP Tunnel
→ tunnel-client
→ @wonderwhy-er/desktop-commander@0.2.52 local stdio MCP
→ STARMER
```

Need to prove:

- account/workspace feasibility;
- tunnel creation/selection;
- restricted runtime key;
- tunnel-client health;
- ChatGPT MCP discovery;
- read tool;
- controlled write tool;
- reconnect.

Only after a **GO** result should provider refactoring start.

---

# 8. External facts already researched

Verified on 2026-10-07:

- OpenAI Secure MCP Tunnel exists and is officially documented.
- It supports private/local MCP servers.
- It supports stdio MCP commands.
- Host requires outbound HTTPS; inbound public port is not required.
- It exposes health/readiness/metrics surfaces.
- ChatGPT can use a Tunnel connection where account/workspace permissions permit.
- Runtime tunnel principal requires Tunnels Read + Use.
- OpenAI `tunnel-client` upstream is Apache 2.0 at time checked.
- Desktop Commander local MCP can run over stdio.
- Desktop Commander local MCP is advertised as free/open source/no monthly limit.
- Desktop Commander Free Remote currently advertises 10,000 tool calls/month.
- zrok/OpenZiti MCP Gateway exists as a later vendor-independent candidate.

Not yet verified:

- availability of Tunnels for this user's exact OpenAI organization/workspace;
- exact Windows tunnel-client behavior on STARMER;
- end-to-end DesktopCommanderMCP tool calls through the tunnel;
- actual reconnect behavior;
- OpenAI tunnel-specific usage limits/costs for this account.

See `SOURCES.md`.

---

# 9. Production 1.5.12 important properties

1. Updater uses transactional staging/replacement/rollback.
2. Setup uses transactional staging/replacement/rollback and mutex coordination.
3. Long stop/restart/logout/reconnect operations do not block UI thread.
4. Primary Tab traversal is limited to action buttons.
5. Custom buttons use opaque owner drawing and no longer show stale-pixel artifacts.
6. Account/help menu selection interior uses 50% alpha while border remains opaque.
7. Re-launch can reactivate existing GUI.
8. A stale GUI process that holds single-instance mutex but loses its top-level window can be recycled.
9. GPU software fallback is reported as skipped rather than false GPU success.
10. Release gates include:
    - GUI logic self-test;
    - button paint/keyboard test;
    - UI lifecycle tests;
    - installer/updater transaction tests.

Do not regress these while introducing providers.

---

# 10. Existing visual architecture that should not be casually rewritten

RDC Relay has a GPU divider/particle indicator.

Important existing concept:

```text
single native popup "sandwich"
```

Layers:

```text
halo particles
→ transparent caustic detail
→ white soft core
```

There are four shader sources/binaries:

```text
divider-caustic
divider-caustic-detail
divider-particles
divider-particles-core
```

Provider work should not touch this rendering unless state mapping requires a small controlled change.

---

# 11. Git workflow conventions

- Use Git.
- Do not push without explicit user approval.
- Do not rewrite published tags/releases.
- Keep production baseline recoverable.
- New provider architecture should use a new feature/minor branch, suggested:

```text
develop/1.6.0-providers
```

- Commit Spike artifacts only if the user asks or after they are cleaned of secrets.
- Never commit credentials.

---

# 12. Machine-work conventions

When working on STARMER:

- batch Remote Desktop Commander calls where practical;
- avoid unnecessary repeated device calls;
- do not launch visual Preview unless needed/requested;
- preserve installed working runtime unless a test explicitly requires replacement;
- do not destroy production config during a transport spike.

## UI review rule — user-approved workflow (2026-10-20)

For changes to layout, controls, animations, motion, timing or visual feedback:

1. Run a non-destructive preview of the actual UI on STARMER, without disturbing installed production or the active Remote session.
2. **Ask the user to inspect and approve the visual result directly** before calling the appearance final or publishing a release. Automated tests are necessary but do not replace the user's visual assessment.
3. **Do not routinely capture large screenshot/frame series (e.g. 80 frames) for appearance review.** Prefer direct user inspection. Use only a few targeted screenshots when a specific rendering defect requires diagnosis; explain the reason first if extensive automated frame capture is truly needed.
4. Keep visual changes focused and reversible; after approval, run the relevant regression tests and release gates.

This preference is also recorded in the GitHub repository's `README.md` under `Development review rules`.

For Spike 0, use a dedicated temporary/profile directory where possible.

---

# 13. Security rules

Never write real API keys into:

- repository;
- markdown documentation;
- command-line examples committed to Git;
- logs;
- ChatGPT handoff files.

OpenAI tunnel runtime key should eventually use:

```text
DPAPI CurrentUser
or
Windows Credential Manager
```

Runtime key:

```text
Tunnels Read + Use
```

Admin key:

- only for tunnel CRUD if absolutely necessary;
- do not persist in RDC Relay daemon setup.

Prefer manual tunnel creation for MVP.

---

# 14. Provider architecture summary

Target:

```text
RDC Relay UI
    │
Supervisor / State Machine
    │
Normalized RdcEvent
    │
ConnectionProvider
    ├── DesktopCommanderRemoteProvider
    └── OpenAITunnelProvider
              │
          tunnel-client
              │
      DesktopCommanderMCP
```

Later:

```text
ConnectionProvider
    └── ZrokProvider
```

---

# 15. Normalized event direction

Provider-specific facts should become events like:

```text
provider.starting
provider.auth-required
provider.connecting
provider.ready
provider.stopped
provider.failed

transport.offline
transport.recovered

executor.offline
executor.recovered

tool.started
tool.succeeded
tool.failed
```

Common supervisor applies these events.

Do not duplicate an entire second supervisor for OpenAI.

---

# 16. What NOT to do next

Do not simultaneously start:

- Google OAuth;
- custom user database;
- device registry;
- custom cloud broker;
- own MCP execution engine;
- zrok production integration;
- large UI rewrite;
- provider refactor before proving OpenAI tunnel feasibility.

That multiplies independent risk.

---

# 17. Expected sequence after Spike 0 GO

```text
1. Create develop/1.6.0-providers
2. Add Source/connection-providers.ps1
3. Introduce normalized RdcEvent model
4. Wrap current Remote behavior as DesktopCommanderRemoteProvider
5. Prove behavior parity
6. Add OpenAITunnelProvider
7. Add minimal provider selector UI
8. Add protected credential storage
9. Add packaging/version/hash policy for tunnel-client
10. Field test
11. Release 1.6.0 when stable
```

---

# 18. Multi-device strategy

Do not build broker first.

First MVP:

```text
RDC - STARMER
RDC - LAPTOP
RDC - OFFICE
```

Separate connections/tunnels.

Only if this becomes operationally painful consider:

```text
ChatGPT
→ RDC MCP Broker
→ user/device routing
```

Google/OIDC identity belongs to that later control-plane layer.

---

# 19. How to report Spike 0 results

Create or update a results section in `SPIKE_0_OPENAI_TUNNEL.md`.

Record:

- date/time;
- tunnel-client version;
- SHA256;
- tunnel ID only if it is not considered sensitive by project policy; otherwise masked;
- profile name;
- health URL;
- doctor result;
- ChatGPT visibility;
- discovered tools;
- read test;
- write test;
- reconnect test;
- measured timings;
- errors;
- GO / NO-GO decision.

Never record API key.

---

# 20. Definition of a good handoff to the next agent

A new agent should be able to answer these questions from repository docs alone:

1. What is current production?
2. Why are providers being introduced?
3. Why OpenAI Tunnel first?
4. What is proven and what is not?
5. What exact experiment should run next?
6. What files may eventually change?
7. How are secrets handled?
8. What existing behavior must not regress?
9. When does zrok enter the plan?
10. When does multi-device/broker enter the plan?

If any of these become unclear, update the documentation before proceeding further.
