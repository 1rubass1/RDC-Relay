# PROG-006A-G8 — STARMER 1.6.0 RC1 FULL owner deployment (2026-10-28)

**Branch:** `feature/v1.6-host-gui-owner-pilot` · **Draft PR:** #23 · **Scope:** owner-authorized, no public stable channel · **Reviewer handoff:** REV-006A-G8 (independent, single integrated review).

## Actual product delivery

- New full original WinForms `Source/remote-window.ps1` is a separate replaceable OwnerGui process under persistent `rc1-tray-host.ps1`. X terminates GUI only. Main shortcut / Host tray reopens GUI; no second Host. Host owns authenticated peer-verified, versioned local IPC and current state, event replay, bounded sanitized journal and read-only Adopted monitoring.
- `Source/RdcOwnerManagedProcess.cs` creates only a NEW exact `@wonderwhy-er/desktop-commander@0.2.52 remote` via suspended `npx.cmd`, assigns it to a private Windows kernel Job before resume, and permits GUI-confirmed stop only if OS Job membership is proven. Explicit `START/STOP/RECONNECT` are available only for the newly Host-owned session. No `taskkill /T /F`, no name/PID stopping, no logout-as-exit, no adoption of stop rights from an external process.
- Full isolated Setup and Portable built using `Scripts/build-rc1-full.ps1`, containing actual Host/OwnerGui/source. Includes pinned manifest, per-file SHA and `FULL_HOST_GUI_RC1` mode, no public auto-updater or stable release.
- U1 manual upgrade can safely hand off an exact previous RC1 version when the same singleton mutex is free; retains previous attested release and shortcut backup and refuses foreign/reparse/active-host ambiguity. Old installed v1.5.18 program tree remains available.

## STARMER verified physical install

| Evidence | Actual result |
| --- | --- |
| Full Setup on owner Desktop | `RDC-Relay-1.6.0-RC1-Full-Setup.exe`, SHA-256 `B58F31633CB0D189CECD2699EC16E47046AD9E688D9573FCD2001830F5CF4C17` |
| Portable on owner Desktop | `RDC-Relay-1.6.0-RC1-Full-Portable.zip`, SHA-256 `15E884509A367F0D9937C7C8915AF4AB411C7349697E3BFF7E7633027BA2511E` |
| Owner-authorized Setup | **PASS**, exit code **0**; release `rc1-342e22e3d3dfe181349b8a5a` |
| Desktop `RDC Relay.lnk` | **PASS**, points to isolated `RC1 Pilot Launcher.exe --full` |
| Host process | **PASS**, PID **36872**, process persists across GUI replacement |
| GUI | **PASS**, initial PID **18376** exited on close; reopened PID **30084**, HWND **1051360**, window title contains `1.6.0 RC1` |
| Existing Desktop Commander Remote | **PASS — preserved**, PID **23444**, birth UTC ticks **639287982412603611** unchanged, exact one observed |
| Previous v1.5.18 binaries | **PASS — preserved** for recovery; primary Desktop shortcut intentionally switched |
| Historical NOT CLEAN TEMP / stable updater / main / stable | **NOT MODIFIED** |

## Regression matrix

| Scope | Result | Exit code |
| --- | --- | --- |
| RC1 safe regression suites | **PASS**, 21/21 | **0** |
| U1/manual upgrade negative suite | **PASS**, 16/0 | **0** |
| Owned kernel Job OS stop negative suite (new temporary dummy only) | **PASS**, 7/0 | **0** |
| Disposable 10-cycle native Host/GUI/IPC, X/reopen, outsider/oversize negatives | **PASS**, 45/0; zero process survivors; attested exact cleanup | **0** |
| Existing live Remote read-only Host/GUI IPC smoke | **PASS**, 1 GUI, 1 authenticated snapshot client, 1 event client | **0** |
| Real FULL Setup, Windows Host/GUI HWND and main shortcut | **PASS**, see physical evidence above | **0** |
| Host-owned REAL Remote startup, stop and reconnect | **NOT CHECKED**; live process is old external Adopted, not imported as owned | n/a |
| Owner physical all-menu/DPI/notification UX and account mutation | **NOT CHECKED / PARTIAL**; account switch still denied, official device links/help available | n/a |

**Diagnostic disclosure:** During iterative development one standalone G7 fixture-provenance regression failed with **26 PASS/2 FAIL/exit1** after a 17th attested Source member was added; cause was two hard-coded assumptions that exactly 9 members remain after 7 deletions. The test now computes expected count from the manifest; dedicated rerun **28 PASS/0 FAIL/exit0**, final full suite **21/21/exit0**. Earlier manually injected disposable owned-Job log-read diagnostic was also unsuccessful; exact test-only process was allowed to finish, and the original test-specific directory was attested and cleaned. These early failures were not mislabelled as product PASS.

## Owner operation / safe rollback

**Current live mode:** external Remote still exists, so RC1 labels it **Adopted/read-only** and correctly disables Stop/Reconnect/account mutation. This is the **full production-capable binary**, not an observer-only package; a *new* Remote started by the Host after owner safely ends the previous session becomes Managed/Owned. The Agent must not remotely stop the existing Remote because doing so would sever its own access.

For routine shell checks, click the desktop `RDC Relay` shortcut, inspect state/journal and Account/Help links, close via X and reopen from tray or shortcut. Host and Remote must remain active. Do not use the old v1.5.18 X to switch while its Remote lifecycle may be linked.

For a rollback after a problem, the owner can close **only the new RC1 GUI and Host** through its own tray (Adopted Remote must continue), then restore the preserved previous desktop shortcut target / previous v1.5.18 application using its existing recovery path. Do not erase Remote credentials, historic TEMP, backup releases, or existing Remote process. A new Host-owned Real Remote lifecycle trial requires explicit measured evidence after current session is safely ended; keep real Remote mutation **NOT CHECKED** until done.

**Review request:** Audit ownership/reparse/ticket/IPC, genuine full Setup↔Host↔GUI and rollback, Job membership and fake-tree negatives, physical shell switch/stable preservation, the fixture count regression fix and residual account switch/Owned real-Remote NOT CHECKED. This is one integrated **REV-006A-G8** in existing Draft PR #23; no independent approval is implied by Programmer-run tests.
