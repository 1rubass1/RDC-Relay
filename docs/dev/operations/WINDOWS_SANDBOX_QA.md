# Windows Sandbox: guest execution and application-control QA

Development-only operational reference. Verified on STARMER, 2026-11-25, Windows 11 build 26100, during RC1 34d0c97 testing.

## Native Sandbox command line (verified)

Windows 11 24H2 and newer Sandbox clients provide the official `wsb.exe` CLI. Prefer this over foreground-window automation, simulated keystrokes, clipboard transfer, or recreation of an existing guest just to execute a test.

From the host, discover and verify the intended disposable session:

```powershell
Get-Command wsb.exe
wsb list
wsb exec --help
wsb exec --id <verified-sandbox-id> -r ExistingLogin -c 'powershell.exe -NoProfile -NonInteractive -File C:\RDC-QA-INPUT\GuestTest.ps1'
```

Use the real session ID returned by list; the placeholder is not executable syntax. Require explicit target identity (if several sessions exist, resolve which is the approved guest; never guess). The above ExistingLogin route was verified with exit 0 and a guest-written comparison report. Do not confuse the CLI exit code with successful application installation: inspect the guest's actual test records. Use ExistingLogin for UI and HKCU tests; System context is not the normal user and must not be used to circumvent policy or authentication. Do not fall back to running guest-only scripts on the host.

Map only narrowly scoped, read-only input and separate writable result directories. Use hash-verified artifacts and a guest boundary check (WDAGUtilityAccount and expected mapped directories for this profile). Networking only for tests that require it. No host credentials, app state, live Remote, or entire Desktop mapping. Before upgrades, fully stop the previous guest Host and GUI by their approved lifecycle and verify the old processes are gone. Do not forcibly stop external Remote processes. Closing Sandbox destroys guest state; restart-persistence testing requires a separate persistent disposable VM.

Microsoft CLI reference: https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli
Configuration: https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file

## Application-control blocker (observed 2026-11-25)

In a fresh network-enabled guest, launching the exact RC1 34d0c97 Setup returned native error 4551 ("An Application Control policy has blocked this file") before installer execution. Setup SHA-256 matched the original build. Read-only inspection found SAC state 1, no SecHealthUI Appx package for the user or all users, SecurityHealthService and WinDefend stopped. Absence of the UI does not imply absence of code integrity enforcement. The signed Node.js 26.13.1 MSI passed signature verification but stalled at Preparing to install and timed out in a separate guest; its successful installation is NOT CHECKED. Do not conflate that MSI stall with the unsigned EXE refusal.

Controlled comparison in the SAME current guest, with matching archived hashes and identical local filenames in separate fixture directories. CreateProcessW with CREATE_SUSPENDED tested admission; admitted processes were terminated before user-mode execution. No control installer was installed:

| Artifact | Signature | Admission |
| --- | --- | --- |
| Stable 1.5.18 | NotSigned | DENIED_WIN32=4551 |
| RC1 615a40c (before Node provisioning) | NotSigned | DENIED_WIN32=4551 |
| RC1 84eb1ba (Node provisioning, before autostart) | NotSigned | DENIED_WIN32=4551 |
| RC1 34d0c97 (Node provisioning and autostart) | NotSigned | DENIED_WIN32=4551 |
| Microsoft Windows cmd.exe (control) | OS binary | Admitted, suspended, not executed |

Conclusion: new Node provisioning and autostart are not necessary for the current block. This does not prove identical future reputation decisions for each binary. Earlier successful Sandbox runs are recorded in the installer integration plan; prior policy state was not recorded, so the reason for the changed behavior is unknown. No rollback of the new functionality is justified by this evidence.

## Separate gates: test environment and release admission

- Restore a supported isolated developer test environment for unsigned RC1 artifacts, without weakening the host's protection. If Sandbox cannot provide a supported test configuration, use a persistent disposable Windows VM with documented developer test policy. Do not patch, evade, or silently disable security controls through the product or installer.
- Verify actual RC1 installation, tray/GUI visual acceptance, Remote connection and captured raw logs, session rotation/retention, startup registration/default OFF, native Startup apps listing, OS-disabled state, and background launch. Real Windows shutdown/reboot persistence requires the persistent guest. These remain NOT CHECKED for 34d0c97.
- Separately evaluate public distribution under Windows SmartScreen and Smart App Control, including clean install and upgrade with protections enabled. SmartScreen warnings may permit user continuation, subject to policy; Smart App Control has no per-app bypass. Unsigned files may be admitted based on cloud reputation, but new binaries and changing reputation cannot be relied upon. Local test trust is not proof of public trust.
- Assess supported distribution/signing alternatives, reputation, actual published binary behavior and any cost before selecting a release strategy. Trusted Authenticode signing is the Microsoft-recommended approach; no certificate purchase, signing service, public release or security change is authorized by this record. Do not promise universal unsigned installation. Preserve exact hashes and test the final Setup, launcher and other executable components, not merely source or a signed wrapper.

References:
- https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview
- https://support.microsoft.com/en-gb/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions
- https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/test-your-app-with-smart-app-control
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options

Status: CLI verified; application-control comparison completed; real RC1 acceptance blocked. Retain raw guest diagnostics outside Git. No active session identifiers or private logs in this document.

## Recovery of the disposable QA guest (verified 2026-11-25)

The owner explicitly authorized restoring installation in the existing disposable Sandbox. Using native wsb exec with ExistingLogin and guest-boundary/admin checks, applied the Microsoft-documented administrative SAC off setting (VerifiedAndReputablePolicyState 1 -> 0) and refreshed policy with CiTool.exe -r (exit 0). See https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol and https://learn.microsoft.com/en-us/questions/5641557/how-do-you-turn-off-smart-app-control-in-windows-s. This is a guest-only test configuration, not an installer feature or distribution solution. The exact same hash-verified RC1 Setup was admitted after the change. Installed the previously verified signed Node.js 26.13.1 MSI (exit 0, npm/npx files present), then the unmodified RC1 34d0c97 Setup in its normal zero-argument route (exit 0, all 27 manifest members verified). Native autostart remained OFF by default. The initial process-count checker used the wrong GUI script name; corrected read-only verification found exactly one Host and one OwnerGui (remote-window.ps1) and a live main window. QA auto-connect is explicitly OFF for owner-controlled connection testing. Installation and initial UI launch PASS; functional acceptance and protected public distribution remain open. The guest remains open. Sandbox discards this guest-local policy change on closure; do not change host policy or embed this setting in product code.
