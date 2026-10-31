# PROG-006A-G8E — Root cause of owner `RC1_HOST_EARLY_EXIT_1` (2026-10-29)

**Branch:** `feature/v1.6-host-gui-owner-pilot`, Draft PR #23. This is the product shell/Host fix; the pinned Desktop Commander Remote `@wonderwhy-er/desktop-commander@0.2.52` was not stopped, relaunched or altered in this correction.

## Evidence from real failed owner installation

Owner screenshot after starting FULL StartupGuard Setup: `RC1_HOST_EARLY_EXIT_1`, following successful Setup file and primary shortcut staging.

The owner closed the diagnostic console before it could zip results. Its private temporary `timeline.jsonl` survived at `%TEMP%/RDC-RC1-Diagnostic-1e652c0cc14d48679eb33881d2025a6c` and was read without disclosing raw Remote logs or credentials.

UTC 2026-10-29:
- 18:11:54.791 — new Setup PID 576.
- 18:11:57.259 — Launcher PID 43488, child of Setup.
- 18:11:57.328 — new Host PID 24144, child of Launcher.
- 18:11:59.140 — new pinned Remote cmd PID 1752, child of Host.
- 18:11:59.263 — pinned Remote Node PID 4136, child of cmd.
- 18:11:59.818 — Host and Launcher absent. No GUI was observed.

WMI ProcessStart/StopTrace subscriptions raised `ManagementException`; therefore, these times come from polling and do not prove every short-lived subprocess/exception. The Host exception text was not preserved by the previous Launcher.

**Concrete source defect:** `Source/RdcOwnerRuntime.cs` already issued GUI tickets in `MANAGED_OWNER_RC1` mode, while `Source/RdcOwnerTicketStore.cs` `Create()` explicitly allowed only `FAKE_ONLY_RC1` and `OBSERVED_READ_ONLY_RC1`. Thus a valid managed GUI ticket was rejected as `RC1_TICKET_PAYLOAD_IDENTITY` after Host had already launched its own Remote. This is the demonstrated contract mismatch matching observed symptoms; the exact exception from the historical Host run was not directly captured.

**Additional high-risk evidence:** following rollback, two external pinned Remote launch trees coexisted: the orphan descendant of the failed RC1 Host (cmd PID 1752, parent Host 24144 already exited) and v1.5.18's new pinned Remote (cmd PID 25924, parent original shell). **NOT CLEAN:** neither was terminated by Programmer, because it is unknown which currently carries the Desktop Commander session. Never claim a successful end-to-end Remote lifecycle from this test.

## Product fix

1. `RdcOwnerTicketStore.Create()` now accepts exactly the previously specified `MANAGED_OWNER_RC1` in addition to FAKE/OBSERVED; generation, nonce, path, ACL, parent reparse and content/creation checks unchanged. Unknown and mismatched modes remain denied.
2. `rc1-tray-host.ps1` does **not** start a new Remote before opening the GUI, either on fresh Full Host or on Adopted-to-Managed promotion.
3. In `RdcOwnerRuntime.cs`, both public `TryAutoStartManagedRemote()` and the pulse schedule now require `guiAuthenticated && guiState==CONNECTED && !reopenAfterModeChange`. This makes a successfully authenticated GUI a prerequisite for creating the pinned Remote, reducing the risk of a remotely running orphan after GUI startup failure. External Remote detection and private kernel Job ownership still apply.
4. Added negative/positive `MANAGED_OWNER_RC1` ticket tests, managed startup contract checks and actual bounded Windows managed GUI/IPC verification without starting any real Remote.

## Verification

- Exact isolated ticket transaction: **15 PASS / 0 FAIL / exit 0**, including valid managed ticket, owned revoke, wrong-generation denial, unknown mode denial and foreign/tampered-file refusal.
- Real Windows isolated managed GUI/IPC: **PASS / exit 0**. New source Host rejected `TryAutoStartManagedRemote` before GUI auth; managed GUI acquired ticket, authenticated IPC and displayed a responsive HWND; GUI closed cooperatively, Host cleanup clean, and both pre-existing pinned Remote trees had unchanged PID/birth.
- Product compiled in source suites; original Source GUI used, no demo UI.
- Final `1.6.0 RC1 FULL` standalone Setup+Portable builder **exit 0**, verified manifest count 20, Setup SHA256 `236F2D96FA6F5F10F70E92431E9C84C5F69055CC61E0BE95CCAFE1654818D6AC`, Portable SHA256 `AD1F05F7A76BA53D90E374E047C4AC5C50CBBFC18EDD240465C82E7384AB682B`.
- Standalone Setup verification: **18 PASS / 0 FAIL / exit 0**.
- Final safe regression inventory: **23 of 23 PASS / 0 FAIL / exit 0**.
- Current Desktop candidate (not installed): `RDC-Relay-1.6.0-RC1-Full-ManagedGUI-Fix-Setup.exe` and matching `RDC-Relay-1.6.0-RC1-Full-ManagedGUI-Fix-Portable.zip`, both SHA256 verified against build. Previous StartupGuard files were moved without deletion to `Desktop/RemoteDesktopCommander/Old_Installers_2026-10-29/G8E_Superseded_StartupGuard`. The owner's separate `RDC.Relay.Setup.v1.5.18.exe` was left in place, original SHA256 `D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190` unchanged.

**NOT CHECKED:** a cold real Job-owned Remote start with both previous Remote trees absent, actual owner installation of newly rebuilt Setup, first managed connection/authentication, long-running tray/GUI operation and independent review of this fix. No stable publish, no PR merge, no modification of installed v1.5.18 or its Desktop rollback Setup.

## Next owner test boundary

Owner's v1.5.18 fallback remains mandatory. Do not force-stop PID by name or by a stale parent. To test newly managed Remote without duplicates, all pre-existing Remote trees must first be verified ended by a normal owner-controlled procedure (a planned reboot is a potential option but not performed here). Only then install current new FULL Setup and evaluate actual managed connection. Any subsequent failure: owner returns to 1.5.18 to preserve STARMER access; capture diagnostic ZIP and report. The historical orphan remains NOT CLEAN until its exact identity/exit is verified.
