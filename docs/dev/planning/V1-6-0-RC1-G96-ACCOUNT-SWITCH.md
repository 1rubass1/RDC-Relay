# G96 — Restore owner-confirmed account switching (1.6.0 RC1)

**Status:** Programmer implementation STAGED / independent security review required / **LIVE NOT CHECKED**.
**Scope:** source commit `0b7a54c`, `feature/v1.6-host-gui-owner-pilot` Draft PR #23; preserve current installed Host/GUI/Remote and stable v1.5.18.

## Owner acceptance target

Stable v1.5.18: Account -> Switch account -> explicit warning -> stop current Remote -> pinned `remote --logout` -> relaunch pinned Remote -> browser device verification, where owner chooses the next account. RC1 must preserve this behavior without letting the replaceable GUI manage processes or credentials directly.

## Implementation and safety boundaries

- `Source/remote-window.ps1`: Managed Owner GUI opens a Yes/No warning including connection interruption and device authorization revocation. Cancel performs no action. Only Yes queues the existing authenticated `REMOTE_ACTION: SWITCH_ACCOUNT` route; legacy path and its original handler remain unchanged.
- `Source/rc1-owner-gui.ps1`: account-switch enablement follows `snapshot.capabilities.switchAccount`, not a GUI PID guess. Pending action and failed IPC disable the item; action acknowledgment says *started*, not *completed*.
- `Source/RdcOwnerRuntime.cs`: Host requires same authenticated GUI + fresh request + explicit `userConfirmed: YES`, `MANAGED_OWNER_RC1`, verified running Host-owned Job, and Ready state. Adopted/Unknown/FAKE modes remain denied. Only the Host stops its own Job and verifies no competing legacy GUI or Remote remains before attempting the device-wide logout. An unverified external presence or OS-scan error fails closed; never stop an external Remote.
- Logout runs in a **separate private kernel Job**, with exact pinned `npx.cmd --yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout`, owned private log and 60-second deadline. `RdcOwnerManagedProcess.TryGetCompletedExitCode` requires root exit plus *zero* active Job descendants. Only exit 0 permits automatic new Host-owned Remote launch; all other exits, timeout, ownership failure or launch failure become a visible Fault with no speculative restart. User may later click Start after inspecting the failure. Never manually edit `device.json` or MQTT key/certificate files.
- While logout is in progress, the GUI, Host action dispatcher, initial auto-start, and tray Exit refuse overlapping lifecycle actions. Existing private-log cleanup allows only new `logout-<guid>.log` files under exact owned state root. Account-scoped usage quota remains guarded by email matching; no quota OAuth secret reuse was added.
- `Scripts/build-rc1-full.ps1` marks **only the staged full candidate** `accountMutationEnabled=true`; source RC1 guard remains blocked, public updater/release disabled.

## Tests on STARMER (2026-11-08)

| Evidence | Result | Boundary |
| --- | --- | --- |
| `Tests/Test-V16OwnerAccountSwitch.ps1` | **9 PASS / 0 FAIL** | Static GUI/Host route, exact pinned args, new short-lived disposable *fake* `npx.cmd` success=0 and failure=23, private Job drained and temp cleanup |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **37 PASS / 0 FAIL**, exit 0 | Existing AST/compile/fake-only suites and G96 test; no real Host or Remote |
| `Tests/Test-V16OwnerBoundaryStatic.ps1` | **26 PASS / 0 FAIL** | Original WinPS 5.1 guards and updated Host capability binding |
| `Tests/Test-V16ProductHostGuiSource.ps1` | **22 PASS / 0 FAIL** | PowerShell AST and compiled genuine C# Host/IPC assembly |
| `Tests/Test-V16OwnedJobStop.ps1` | **7 PASS / 0 FAIL** | Separate bounded fake Job-tree stop test |
| `Tests/Test-V16StandaloneSetup.ps1` | **19 PASS / 0 FAIL** | Setup resource extraction/hash validation; no installation |
| Full package | **21 manifest members / hashes verified** | Setup + Portable separately staged, not executed |
| `git diff --check` | **PASS** | Line-ending warnings only |

STARMER Desktop staging, **not installed**:
- `RDC-Relay-1.6.0-RC1-AccountSwitch-Setup.exe`; SHA256 `1736039E1DA2938BAC34E0E946C55FB67CB1CF0ADE0F5D105206367C04252BB1`
- `RDC-Relay-1.6.0-RC1-AccountSwitch-Portable.zip`; SHA256 `593B5D8C767085F1BDCEC76667E7434AADB3A862B4990D58471B9E029494E897`

## Not verified / review gate

**NOT CHECKED:** physical user click/keyboard/menu focus, real pinned Remote revocation over network, browser verification and new account, real concurrent external Remote, timeout behavior against actual provider, interruption/restart recovery, installed GUI and rollback. No account credentials were revoked, no real Remote/Host stopped, no installation, no public release or stable merge.

**Next:** independent Reviewer examines Host ownership and process isolation, no-automatic-restart on logout failure, timeout and Exit races, account/capability UI routes, and product packaging. After review, owner explicitly schedules a controlled real account-switch test with appropriate backup/rollback and accepts disruption of the existing remote session. This report and PASS mock tests are **not** permission for a live logout.

**Upstream contract:** [official Desktop Commander Remote README](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md) distinguishes stop (keep credentials) from `remote --logout` (revoke device and remove saved authorization on confirmation).
