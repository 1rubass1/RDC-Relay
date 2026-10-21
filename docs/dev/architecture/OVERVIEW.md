# RDC Relay — architecture overview

> Product baseline is v1.5.18. The multi-provider design below is a **proposal**, not implemented production functionality.

## Current
```text
WinForms/WPF RDC Relay GUI
  -> local PowerShell supervisor and status/event parsing
  -> pinned Desktop Commander Remote (@wonderwhy-er/desktop-commander@0.2.52)
  -> official Remote transport, DesktopCommanderMCP executor
```
Runtime code: `Source/remote-window.ps1`, `Source/update-notice.ps1`; graphics/shaders under `Source/`. Installer and updater are transactional. Preserve single-instance behavior, GUI responsiveness, local process ownership, status semantics and rollback.

## Conditional future provider seam
```text
          common UI / state supervisor
                     |
               normalized RdcEvent
                     |
              ConnectionProvider
                /         \
DesktopCommanderRemote   future authenticated MCP transport
          |                         |
official Remote          sandboxed local DesktopCommanderMCP
```
Provider owns transport-specific lifecycle/health/parser; supervisor owns normalized state and visual feedback. Process alive, transport online, local executor ready and tool call success are separate facts. Tool event visibility may be full/partial/none. Explicit provider selection requires safe stop, bounded readiness, rollback and persisting only after success. Stop only processes truly owned by that provider.

## Invariants
- Do not disturb production Remote or run conflicting executors.
- No public general execution through demo HTTP bridge.
- Fail closed when auth is absent/invalid; protect credentials with a verified storage mechanism, not command line/plaintext.
- Backoff, bounded logs, meaningful faults and health proofs; never infer tool success from a live process.
- Existing v1.5.18 runtime/installer/update tests remain release gates.
- UI uses Windows App Design / Fluent 2 where applicable and user visual acceptance.

## Pending validation
OpenAI Tunnel workspace connection was blocked. Direct HTTPS/MCP loopback and public ping worked separately, but authenticated ChatGPT-to-device path and safe tool exposure are unproven. Detailed 36-section previous [technical design](PROVIDER_TECHNICAL_DESIGN_LEGACY.md) is an archive of **proposed** interfaces (including stale baselines), not authority to implement without user sign-off.

New material decisions are logged in [DECISIONS.md](../../../DECISIONS.md); evidence in [RESULTS_MATRIX.md](../research/RESULTS_MATRIX.md).
