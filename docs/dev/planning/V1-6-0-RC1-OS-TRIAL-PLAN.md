# v1.6 RC1 — separately authorized disposable Windows OS-process trial

**PLAN ONLY / NOT AUTHORIZED / NOT EXECUTED.** Current approval is to implement code and run fake-only logic tests; no new real process-tree trials have been authorized. Never launch/stop/disconnect/log out real Desktop Commander Remote, change installed v1.5.18, alter security policy, or touch historical P1/P2 TEMP.

## Preconditions for a separate owner GO

- Owner explicitly authorizes fresh disposable *stand-in* processes on STARMER, their sandbox location and the scope of execution.
- The independent Reviewer inspects harness ownership proofs and negative exit handling **before** any test process starts.
- Each disposable process is started from a fresh GUID test root under user TEMP, with exact exe/script, parent PID, PID, UTC birth ticks, OS session and test epoch captured at spawn from OS APIs.
- Revalidate PID, birth, executable path and whole expected parent/child chain immediately before *cooperative* stop. Do not trust PID, ownership or session reported through IPC. Unknown, adopted, old/reused PID, missing child, noncooperating process or unexpected filesystem link is **NOT CLEAN / FAIL**, never a target for forced kill.
- No broad process-name cleanup, taskkill, Stop-Process -Force, Explorer restart, ACL ownership takeover, privileged symlink creation or account credential changes.

## Matrix (none executed yet)

| ID | Disposable condition | Acceptance |
| --- | --- | --- |
| OS-01 | Own GUI closes with native WM_CLOSE | Only GUI exits; Host and fake Remote session remain |
| OS-02 | Ten source A→B process replacements | New GUI identity per run; Host PID/birth and fake Remote identity unchanged |
| OS-03 | Rapid duplicate launcher and tray-open | One Host, one GUI, zero unintended start |
| OS-04 | Verified parent/owned stand-in Remote child chain | Cooperative exit only after test owner confirmation |
| OS-05 | Adopted stand-in with matching process name | Deny stop |
| OS-06 | Unknown parent, orphan or unrelated process | Deny stop, preserve files |
| OS-07 | PID reuse, different birth tick | Deny stop |
| OS-08 | Different session, image path or epoch | Deny stop |
| OS-09 | Parent exits but child survives | Never report CLEAN |
| OS-10 | Child ignores graceful stop | Bounded timeout and NOT CLEAN; no forced kill |
| OS-11 | GUI without a visible HWND | Never kill based on age/no HWND |
| OS-12 | Invalid IPC peer/nonce/replay/version/oversize | Refuse, Host remains responsive |
| OS-13 | TEMP path symlink/junction/reparse or unexpected entry | Refuse launch, open and deletion |
| OS-14 | External sentinel beyond test root | SHA-256 unchanged |
| OS-15 | Crashed GUI and missed event sequence | Host preserves queue, new GUI recovers snapshot |
| OS-16 | Approved owned full Exit | Own GUI and verified child group stop first; Host last; no logout |
| OS-17 | Protocol-incompatible new GUI | No live Remote effect, Host continues |
| OS-18 | Concurrent foreign installation/same-user process | No cross-instance process control |

Every case must provide PASS / FAIL / PARTIAL / NOT CHECKED, exact test-owned PIDs, creation ticks and session, preservation of foreign/user processes, negative injected assertion nonzero, verified absence of test-owned survivors, and explicit non-clean reports. A failed cooperative stop is **not** permission to force a stop.

## Separate real Remote acceptance after these tests

If all disposable cases pass and Reviewer accepts them, obtain a **new owner authorization** for actual STARMER Remote lifecycle. Upstream [Desktop Commander Remote device docs](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md) say Ctrl+C stops the local process while retaining saved credentials, whereas remote --logout deletes locally saved credentials. This app must not use logout as an Exit shortcut. Merely finding an existing matching Remote by name never transfers authority to stop it.

This document is a test plan, not an execution report.
