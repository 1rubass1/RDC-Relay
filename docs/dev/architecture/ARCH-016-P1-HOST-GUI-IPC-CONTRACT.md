# ARCH-016-P1 — контракт Host ↔ GUI, безопасность IPC и приёмочные испытания

**Статус:** Architect design baseline · 2026-10-23 · B1.  
**Основание:** утверждённая владельцем модель X = уничтожить GUI, но сохранить живые Tray Host и Desktop Commander Remote; double-click tray = новый GUI из обновлённых файлов; явный «Завершить RDC Relay» = в будущем безопасно завершить **всю проверенно управляемую** группу процессов. [ADR-005](../../../DECISIONS.md), [ARCH-016-P0 boundary](ARCH-016-P0-HOST-GUI-BOUNDARY.md), [Architect/Reviewer verdict](ARCH-016-P0-ARCHITECT-ASSESSMENT.md).

**Область:** архитектурный контракт и матрица испытаний. **НЕ доказательство готовой IPC-защиты и НЕ разрешение трогать реальный Remote.** P0/REV-016 подтвердили 15 PASS + два отрицательных сценария только на fake Remote в [PR #15](https://github.com/1rubass1/RDC-Relay/pull/15). P0-код `TrayHost.ps1` нельзя переносить в рабочий Host как есть: blocking `ReadLine`, слабая авторизация и отсутствие session/rendezvous.

## 1. Выбор архитектуры и граница ответственности

```text
   User shortcut / tray click           One logical instance per user logon
                |                                        |
                v                                        v
   Safe launcher / rendezvous ----> Persistent Tray Host (PowerShell 5.1, STA)
                                      + WinForms ApplicationContext
                                      + NotifyIcon; user-level single Host lock
                                      + GUI process factory / identity registry
                                      + supervisor / event store / log reader [LATER]
                                      + Remote process identity and controls [LATER]
                                                  |
                                  localhost-only, authenticated, bounded IPC
                                                  |
                                      Replaceable GUI process (STA)
                                      + WinForms layout and visual feedback
                                      + bounded view model / rendering only
                                      + X => process exits, Host stays alive
```

**Host owns:** singleton identity/rendezvous, running application/session generation, GUI launch registry and Windows PID/creation-time validation, `NotifyIcon` and menu, future Remote lifecycle/adoption, monitor/watchdog, log file cursor, authoritative connection state, event sequence and update/relaunch orchestration. **Host is NOT an arbitrary shell/tool executor.** Until separate PROG-005 safety gate Host must use **fake Remote only**, without live WMI adoption/start/stop or user credentials.

**GUI owns:** WinForms Form, visual state rendering, current GUI build stamp, animation/timing and local UI preferences (window size, scroll), accessibility and harmless user input. Each launch executes the latest **new GUI script in a new PowerShell process**. It does **not** own Remote process handles, log file reader, reconnect loop, updater, or Node/npx; `X` releases GUI resources and exits the GUI **only**. GUI crash/version error never stops Host or Remote.

**Explicit Exit is future PROG-006B:** user invokes tray action; Host first safely stops *verified managed* Remote + launcher/children and confirms exit, then disposes Host/icon and any GUI. This is NOT `remote --logout`; credentials remain. If ownership unclear or stop fails, Host remains available and visibly reports failure. No exit/stop IPC verb in PROG-006A.

**Windows logoff/shutdown/updater** are distinct controlled Host paths, not ordinary X; behavior needs later safe integration. Old single-GUI no-HWND five-second forced kill MUST NOT be moved into Host or new launcher. If Host is present but activation fails, show bounded diagnostic; do not kill or start another Remote.

## 2. Threat model: threat actors and assets

**Assets:** continuity of live Remote/MCP tool execution, integrity/availability of Host process and UI loop, correct process ownership, account/credentials (never cross GUI IPC), private log content, input commands and GUI update source integrity.

**Trust boundaries:** user/OS click → launcher; GUI executable from disk → Host; locally connected Named Pipe peer → Host; Host event reader → GUI; update/rollback executable and installed path → child GUI. A same-user malicious executable may have equivalent OS privileges and cannot be perfectly isolated using SID+PID/nonce alone; claim **same-session containment and accidental/untrusted-client resistance**, NOT a security boundary against fully compromised user account. If the threat includes hostile equal-privilege local code, use stronger OS policy/signature/installation isolation after a separate review.

| Threat ID | Risk | Required control | Failure behavior |
| --- | --- | --- | --- |
| T01 | Client connects without newline or sends unbounded bytes; Host freezes | Non-UI async bounded **byte-counted** framing, per-operation deadlines, backpressure, max concurrent clients | Cancel/close offending connection; Host heartbeat/tray remains responsive |
| T02 | Client forges `HELLO|PID` or PID is reused | OS-observed Named Pipe peer PID + creation-time/handle + expected Host-spawned GUI registry + Windows Session ID + launch generation, not client string | Refuse connection, no state leak/process action |
| T03 | Another logon session or remote SMB pipe client | Protected DACL using current **logon SID**, deny NETWORK; where available use Win32 `PIPE_REJECT_REMOTE_CLIENTS` and validate effective behavior | Connection denied before commands |
| T04 | Malicious server impersonates Tray Host; GUI leaks data / sends commands | GUI verify OS-reported **server PID/session**, known host process identity from protected rendezvous + challenge/nonce/host generation; verify installed source trust per launch | GUI refuses and exits with message; Host remains running |
| T05 | GUI's untrusted/old build performs disallowed mutation | Protocol allowlist and per-verb authorization; `GET_SNAPSHOT`, `GET_EVENTS`, `DETACH` only in fake-only scope; no `Stop`, `Restart`, `Logout`, `END_TEST_HOST` product verb | Reject, audit bounded error; zero side effects |
| T06 | Two GUI windows / two Hosts / abandoned pipe | Session-scoped Host mutex + independently verified rendezvous; one GUI launch slot in Host, atomic transition STARTING→CONNECTED→EXITED; never kill via `MainWindowHandle` | Reuse/activate correct GUI or fail closed; no duplicate Remote |
| T07 | Lost event, delayed reply or Host restarted during update | Versioned snapshot + Host generation and monotonic revision/sequence, request IDs, gap detection, reconnect/resync | GUI requests new snapshot; never replay control action |
| T08 | Log/event spills secrets, giant payload or infinite subscription | Redact/log allowlist, maximum tail/events/bytes, single bounded queue per peer; no credentials/paths by default | Truncate with explicit `moreAvailable` flag |
| T09 | Path-swap / accidental launch from foreign project copy | Absolute vetted GUI path, trusted install/worktree root, normalized path and reparse checks; GUI process handle+start-time registry, safe release update | Refuse launch; no user-process termination |
| T10 | GUI or pipe hangs/crashes while Remote running | Per-client workers + cancellation, Host supervision independent of GUI and IPC, clear error state | Host/Remote continue; next GUI opens from fixed code |
| T11 | Fake test verbs or broad command dispatch leak into product | Build-time/test-run gate; explicit separate test pipe names and codepaths; deny by default, no arbitrary PowerShell/shell execution | Build/test fails on leaked product verbs |
| T12 | Same-SID app can access a private pipe | Combine logon SID, actual OS peer validation, nonce tied to child generation, allowlist and least privilege; document residual same-privilege threat | Refuse if any validation fails; no claim of protection vs account compromise |

Security is not established by a random pipe name, ordinary current-user SID DACL, `Connect('.')` (client choice only), PowerShell command-line PID, or connect timeout alone.

## 3. Named Pipe transport v1 (proposal for isolated PROG-006A only)

**Protocol boundary:** local Windows desktop session, Windows PowerShell 5.1 and installed .NET Framework; no TCP, no HTTP, no public listener, no dynamic executable action. **Do not assume .NET's `NamedPipeServerStream` exposes all Win32 security flags on every runtime.** If `PIPE_REJECT_REMOTE_CLIENTS` cannot be achieved via the intended managed constructor, write an isolated, audited Win32 shim or prove explicit DACL/NETWORK rejection in OS tests. Document the exact API support before coding.

**Server properties:** Host owns listener with `PipeOptions.Asynchronous` / overlapped I/O, a worker or asynchronously awaited task for every request; all UI objects get updates only via WinForms `BeginInvoke` or a thread-safe message queue. Neither Host WinForms Timer nor GUI rendering Timer performs sync `ReadLine()`, `Wait()` or `Result` on untrusted IPC.

**Frame format:** exactly 4-byte unsigned little-endian length + UTF-8 JSON message. Enforce length **before allocation/JSON decoding**, no newline framing. Initial suggested limits (acceptance targets, subject to measured adjustment without weakening invariants): request <= **8192 bytes**, response <= **65536 bytes**, log tail <= **128 entries**, event batch <= **128 entries**; malformed 0 length/negative signed conversion/overflow/partial/extra data is rejected. Limit max concurrent clients (design target **2**, including rendezvous) and per-client queued messages. Do not allocate by malicious declared sizes, and use finite buffered readers/writers. All wire numbers and strings type-checked and normalized; reject unknown verbs/fields where unsafe.

**Timing targets for fake-only tests:** connect/HELLO <= **2000 ms**, each frame read/write <= **1000 ms**, abandonment/partial frame <= **1500 ms** wall-clock after acceptance, worker cancellation <= **1000 ms**. These are **proposed time budgets**, not demonstrated product performance. Test that **Host heartbeat makes progress during an attacker-held connection**, GUI never hangs indefinitely on lost response, cleanup reports any unconfirmed worker. Bound end-to-end wait, not only the connect phase; cancellation must close underlying pipe reliably on Windows PowerShell 5.1.

**Protocol schema** (conceptual JSON payload under length prefix; sensitive data deliberately absent):

```json
{"type":"HELLO","protocol":1,"requestId":"uuid","guiBuild":"B",
 "hostGenerationExpected":"uuid-or-null","clientNonce":"per-launch-nonce"}
{"type":"WELCOME","protocol":1,"requestId":"uuid","hostId":"uuid",
 "hostGeneration":"uuid","sessionId":123,"challengeResponse":"opaque"}
{"type":"GET_SNAPSHOT","protocol":1,"requestId":"uuid","hostGeneration":"uuid"}
{"type":"SNAPSHOT","protocol":1,"requestId":"uuid","hostId":"uuid",
 "hostGeneration":"uuid","revision":42,"lastEventSeq":125,
 "remote":{"ownership":"unknown","processAlive":"unknown",
           "transportReady":"unknown","authState":"unknown",
           "toolActivity":"unknown","fault":null},
 "logTail":[],"updatedAtUtc":"2026-10-23T00:00:00Z"}
{"type":"GET_EVENTS","protocol":1,"requestId":"uuid",
 "hostGeneration":"uuid","afterSequence":125,"limit":128}
{"type":"EVENT_BATCH","protocol":1,"requestId":"uuid",
 "hostGeneration":"uuid","firstSequence":126,"lastSequence":130,
 "events":[],"gap":false,"moreAvailable":false}
{"type":"DETACH","protocol":1,"requestId":"uuid"}
{"type":"ERROR","protocol":1,"requestId":"uuid",
 "code":"UNAUTHORIZED_OR_VERSION_MISMATCH"}
```

**Auth handshake semantics:** identity first, payload second. Host creates GUI with a registered expected *real* PID, creation time and verified working session; GUI connects to protected rendezvous, verifies real server PID/session/creation time; Host independently resolves client PID and session via OS pipe handle, matches registered GUI and **one-time per-launch challenge bound to Host generation**. Nonce material is not a command-line parameter or public log entry; use private protected channel/handle or an equivalent verified mechanism, not a publicly readable token. Mutual verification, app-path integrity and privilege model must be demonstrated in isolated tests before marking this schema accepted. `guiBuild` and `HELLO` PID are diagnostic only, not authentication. A second client/duplicate GUI is denied. Host refresh/update rekeys generation and invalidates stale GUI sessions.

**Control authority in PROG-006A:** None over real Remote. Only read-only `GET_SNAPSHOT`, `GET_EVENTS`, harmless `DETACH`; `OPEN_GUI` is **Host-internal** tray action or a separately authenticated launcher rendezvous with no Remote start. No STOP/RESTART/LOGOUT/reconnect/exit command wired to Host. `END_TEST_HOST`, `CLOSE_GUI`, `TRAY_DOUBLE_CLICK` belong ONLY to `Tests/` synthetic fixture and must not appear in production IPC allowlist.

## 4. Host and GUI state-machine contracts

**Host lifetime:** `UNINITIALIZED → STARTING → READY → SHUTTING_DOWN → EXITED`. Startup waits for unambiguous singleton. No window handle heuristics or force stop. GUI lifecycle independently: `NONE → SPAWNING → HANDSHAKING → ATTACHED → CLOSING → NONE`; `FAILED` after crash/missing-host/version rejection and no automatic process kill. A known older GUI may be closed voluntarily, but Host must not terminate an unrelated PID or the real Remote.

**Snapshot state:** `hostId` stable across GUI replacement and regenerated only upon actual new Host; `hostGeneration` changes on Host restart/updater transition; `revision` monotonically increases on material changes; `eventSeq` strictly monotonic per Host generation. Consumers detecting skipped seq, changed generation or incompatible schema request full snapshot and reset local presentation cache. No replay of commands or GUI-side supervision after reconnection.

**Remote fields are separate dimensions:** processAlive (`true|false|unknown`), ownership (`owned|adopted|external|unknown`), transportReady (`true|false|unknown`), authState (`unlinked|authenticating|linked|unknown`), toolActivity (`idle|active|unknown`), fault (`null|code+source+sinceUtc`). Never infer Remote readiness from a PID, heartbeat or fake UUID. In PROG-006A these values are **synthetic only**, clearly tagged `fake:true`; no real `Find-ExistingRemote`, `Start-Remote`, `Stop-Remote`, `remote --logout`, `taskkill` or actual log path.

**Event ring:** one authoritative Host-side bounded buffer (design default 256 compact events) with sequence, source and UTC time; GUI receives bounded initial tail and subsequent paged changes. Missed events/gap cause full resync and visible last-known freshness, not arbitrary duplicate state mutations. Real credential material and real log values are not part of the mock schema.

**GUI failure and concurrency:** last genuine GUI process exiting must release rendering controls and UI timers; Host retains event ring/monitor, `NotifyIcon`, Host PID and fake Remote session. A→B GUI source update opens latest on disk, not an old Form. Repeated tray click while GUI connected activates existing GUI; overlapping two launches serialized. If a UI copy cannot start, Host remains available and reports error. UI does not block on any pipe read; show loading/error state with finite wait and permitted retry.

**Full shutdown / update:** deferred. Product tray «Завершить RDC Relay» must eventually perform verified controlled Remote stop (PROG-005B + PROG-005 + PROG-006B) before Host exit; fake-only test `END_TEST_HOST` is NOT product UI. Installer transactional update/exit code 42 and Windows logoff/shutdown need separately reviewed lifecycle. Never attempt production Exit via old `taskkill /T /F`.

## 5. Acceptance matrix — isolated fake-only gate PROG-006A → REV-006A

Every row produces PASS/FAIL/NOT CHECKED with fixture PID, Host generation, GUI build, response/heartbeat timing and cleanup; synthetic negative controls must return nonzero. No real Remote, user PID, installed app, credentials, system Explorer restart, released installer or production branch is permitted.

| ID | Required case / fault injection | Pass criterion |
| --- | --- | --- |
| P1-01 | Fake Host no GUI | Host tray loop and synthetic watchdog advance; zero GUI/Remote launch |
| P1-02 | GUI A→X→edit→GUI B | GUI PID/build differ; same Host PID/fake Remote UUID; revised source loaded |
| P1-03 | Open spam/race 10 cycles | At most one active GUI; no deadlock/leaked test children |
| P1-04 | GUI throws before HELLO and after HELLO | Host continues; next corrected GUI attaches; no ghost registration |
| P1-05 | Frame has valid length + valid JSON | Exactly one correlated response; type/limit enforcement |
| P1-06 | Oversized frame header, integer overflow, zero/invalid len | Reject **before allocating or decoding payload**, Host continues |
| P1-07 | Partial header, partial body, no newline/never-complete payload | Deadline disconnect; Host heartbeat continues and tray event still dispatched |
| P1-08 | Client connects then never sends bytes; server never replies | Both ends bounded, GUI rendering responsive; no blocking UI Timer |
| P1-09 | Fast clients flood frames/instances | Max concurrency/queue enforced; no unbounded memory/thread increase; monitor remains live |
| P1-10 | Foreign PID claimed in HELLO, stolen expected GUI PID string | Reject using OS-observed identity; no false successful login |
| P1-11 | Same user, different Windows logon session / network SMB pipe attempt | Denied; if environment unavailable, mark **NOT CHECKED**, prevents product-IPC GO |
| P1-12 | GUI connects to spoof Host pipe | GUI rejects wrong server PID/session/generation; no state/control leak |
| P1-13 | Client tries `END_TEST_HOST`/`STOP`/`LOGOUT`/arbitrary command | Rejected with no mutation; test-only verbs remain outside product protocol |
| P1-14 | Stale nonce, reused nonce, replayed request ID | Reject duplicate/stale handshake/request as appropriate; no duplicate side effects |
| P1-15 | Wrong schema/protocol version and Host generation | Fail closed; no Remote launch; UI shows diagnostic |
| P1-16 | Sequential events and injected missing sequence | `revision` monotonic; gap detected, GUI snapshot resync |
| P1-17 | Ring overflow / slow GUI / giant log event | Bounded memory & payload, `gap/moreAvailable` signaled, no credentials |
| P1-18 | Host already running; launcher double-launch | No second Host, no forced shutdown of first, no duplicate fake Remote |
| P1-19 | Unknown/stale Host rendezvous / failed update | Fail closed, no destructive singleton heuristic; Host and fake Remote unaffected |
| P1-20 | GUI update path substitution / untrusted location | Unsafe launch refused with diagnostic; no shell injection |
| P1-21 | Physical tray double-click/right-click and X in isolated visible desktop | **Separate user-approved UI-only sandbox**: GUI returns/actually closes; keyboard, DPI and feedback verified. NOT CHECKED by headless fake suite |
| P1-22 | Test runner assertion fails with GUI active | Nonzero process exit, bounded cooperative fixture-only cleanup, zero verified test-owned processes and pipe release or precise NOT CLEAN |
| P1-23 | Regression suites | P0 15 + 2 negative, PROG-005A 27+21, previous 46+32/parity and UI/Npx PASS; no Source changes unless explicitly separately approved |
| P1-24 | Release boundary | Dev-only tests/docs excluded from installer/ZIP; `main`/`stable` unchanged; true ZIP remains NOT CHECKED unless supplied |

**Gate A — architecture design:** this document accepted as implementation guidance and backlog updated. No code/OS behavior is proven by writing it.

**Gate B — narrow mock-only Programmer implementation:** independently assigned from `development`, isolated files in `Tests/Prototypes/` or `docs/dev/`; can improve P0 protocol, fake Host/GUI and fixture only **after explicit handoff**, with named-pipe disposable processes but no real Remote. Negative tests and Reviewer required. If writing `Source/` becomes unavoidable, stop and request Architect approval; no editing production launcher by default.

**Gate C — secure-product Host:** NOT granted. Only after Gate B independent Reviewer reports safe framing/identity/session/rendezvous, separate signed/installer/update and Remote ownership plan, and owner-go for any live trial. Full Exit (PROG-006B) and process tree (PROG-005B/PROG-005) are separate explicit gates.

## 6. Contract decision record / unresolved engineering questions

- **Chosen:** 2 processes (durable Tray Host + fresh GUI), local Named Pipes with strict framing, no UI-thread blocking; process identity + session authorization; Host authoritative state/Remote, GUI presentation-only; security first with fake-only evidence.
- **Not chosen:** same-Form `Hide/Show`; `Form` recreation within old loaded PowerShell process; forced stale-PID kill; TCP listener; trusting PID text or pipe name as an authentication secret.
- **Implementation choice to validate in fake-only work:** exact Win32/.NET Framework 4.x interop for `PIPE_REJECT_REMOTE_CLIENTS`, logon SID extraction, actual client/server peer PID + start-time verification, secure per-launch nonce handoff and deadlines that also cover OS WMI lookup hangs. If a proposed API is unavailable, use an alternate verified native implementation, not relaxed identity checks.
- **Known environmental limits:** a full malicious same-user process cannot be excluded by SID/IPC alone; authenticated equal-privilege local code is a residual threat. Real disconnected Remote, launcher process independence, live logs, protocol/device credentials, update rollback and real Exit are NOT CHECKED.
- **UX/designer dependency:** original app/desktop shortcut/tray icon is not accepted by owner; dedicated future Designer task DES-002 to develop icon identity and assess legibility/contrast. Reuse existing icon unchanged until a separate owner-approved design brief and new assets are accepted.

## 7. Reference sources

- Microsoft Learn: [Named Pipe Security and Access Rights](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights); [Named Pipes](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipes); [CreateNamedPipe / PIPE_REJECT_REMOTE_CLIENTS](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipea).
- Microsoft Learn: [GetNamedPipeClientProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid), [GetNamedPipeClientSessionId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientsessionid), [GetNamedPipeServerProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeserverprocessid).
- Microsoft Learn: [NamedPipeServerStream.WaitForConnectionAsync](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstream.waitforconnectionasync).
- Microsoft Learn: [Windows app icon design and contrast](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-design); [Fluent 2 iconography](https://fluent2.microsoft.design/iconography/).
- Desktop Commander upstream pinned Remote (core interactions): [Remote Device README](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md).
- Project: [PROG-005 ownership plan](PROG-005-PROCESS-OWNERSHIP-PLAN.md), [Tray UX contract](TRAY-LIFECYCLE-DESIGN.md), [Board](../../../COORDINATION/BOARD.md).

**Verification status:** Architecture/design analysis + official API documentation review completed. No code was implemented, no Windows Named Pipe security/visual/full Remote continuity tests executed for P1. The 24 acceptance rows are **PENDING**, not PASS.
