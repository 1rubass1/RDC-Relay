# PROG-006A-P2 — interactive Tray Host / Replaceable GUI demo

STARMER; Windows PowerShell 5.1; **isolated fake Remote only**. The sandbox is NOT the installed RDC Relay. It starts only a named P2 Host and its own GUI child, both from a fresh %TEMP%\RDC-P2-<32-hex-GUID> directory. IPC names use rdc-p2-* rather than rdc-p1-*. SystemIcons.Information is the temporary, recognizable P2 test symbol; DES-002 icon redesign remains separate.

## Launch interactive demo

From a non-elevated Windows PowerShell 5.1 window in the SAME interactive Windows desktop:

    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "E:\Projects\GitSync\RDC\RDC-Relay PROG-006A-P2\Tests\Start-InteractiveP2.ps1"

The launcher prints P2_DEMO_DIRECTORY, P2_DEMO_HOST_PID, P2_DEMO_GUI_PID, P2_DEMO_FAKE_REMOTE, P2_DEMO_TRAY_VISIBLE and GUI build. The P2 SANDBOX tray icon and independent GUI A should be visible in the current Windows session. If necessary inspect the Windows notification-area overflow, not the installed RDC Relay icon.

## A -> B procedure, using real physical UI

1. Observe the **GUI Build A** in the title and header. The Host PID and fake Remote UUID appear in the footer. The synthetic journal contains no actual user/Remote data; Remote Start, Stop, Reconnect, Account buttons are **disabled**.
2. Physically click **X** on *P2 SANDBOX GUI A* (not on the installed application). Its process should disappear from Task Manager. The P2 tray icon must stay.
3. Copy the exact P2_DEMO_DIRECTORY printed above and run:

       powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Projects\GitSync\RDC\RDC-Relay PROG-006A-P2\Tests\Set-P2DemoBuild.ps1" -FixtureRoot "<P2_DEMO_DIRECTORY>" -Build B

   This checks the strict P2-specific temporary path, that GUI is no longer running and a fixture Host exists; it changes ONLY the copied disposable GUI file. The installed Source is never edited.
4. **Double-click P2's own tray icon.** This dispatches the real NotifyIcon.DoubleClick handler; it launches a NEW GUI process from current GUI script. GUI **Build B** must have a different PID/title and gold (instead of orange) build accent. Host PID and fake Remote UUID must match A.
5. Double-click again while GUI B is open; no second GUI must appear. The right-click **Open demo GUI** command uses the same handler. The **Stop P2 test Host** menu entry refuses to stop while GUI exists and shows a brief explanation.
6. Close B using X; then right-click the P2 tray icon and select **Stop P2 test Host (close GUI first)**. That ends ONLY the disposable Host; no Remote/user process is killed.
7. After verifying the Host PID is gone, clean ONLY the exact P2 fixture directory:

       powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Projects\GitSync\RDC\RDC-Relay PROG-006A-P2\Tests\Remove-P2DemoFiles.ps1" -FixtureRoot "<P2_DEMO_DIRECTORY>"

   The cleanup helper refuses live sandbox Host/GUI, non-P2 directories, reparse-point root or unexpected files. **It never targets historical RDC-P1-* TEMP artifacts.**

## Automated checks

Full fake-only matrix, P2 application, 10+ GUI process cycles, A/B code replacement, security regression cases and previous P0/P1 regressions:

    powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "E:\Projects\GitSync\RDC\RDC-Relay PROG-006A-P2\Tests\Test-Arch016P2Lifecycle.ps1"

For a short debugging iteration use -Fast; that deliberately downgrades the inherited-regression row to PARTIAL.

Independent **visible WinForms window** test:

    powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "E:\Projects\GitSync\RDC\RDC-Relay PROG-006A-P2\Tests\Test-P2VisibleWindow.ps1"

It creates a genuinely visible tray/GUI in interactive session 8, obtains each native GUI HWND and real child PID, verifies it belongs to its own launched Host, posts **WM_CLOSE** ONLY to that verified GUI HWND (same native close route as X), edits ONLY the fixture GUI source A to B, invokes the shared tray Open function through isolated test-only IPC, verifies B has a new PID/HWND and the Host PID/mock Remote ID are stable, then closes its owned processes cooperatively. THIS DOES NOT PROVE A PHYSICAL HUMAN X OR TRAY DOUBLE CLICK; both remain **NOT CHECKED** until owner-observed demonstration. No global cursor/mouse automation, extra desktop sessions or Explorer restart.

## UI and access boundaries

- The test window borrows **reference** colors/geometry from NATIVE_UI_GEOMETRY.md: #1D2024 background, #121417 read-only log, #7B5FA2 separator, orange build A / gold build B indicator. It intentionally does NOT clone installed UI or its icon.
- Standard native Form/title/X, a real status label, read-only mock journal and event stream, Windows DPI autoscaling, accessible control names, a keyboard-focusable About button, and non-working actions explicitly disabled rather than faking success.
- Windows Forms timer checks completed async IPC tasks and retains focus responsiveness; test-only clock/pulse plus hostile stalls validate that no pipe read blocks that GUI timer. Avoid flashing or unnecessary motion; plain text accompanies status colors. High-DPI, high contrast, Narrator/screen reader and pixel-accurate alignment remain **NOT CHECKED**.
- Windows reference: https://learn.microsoft.com/en-us/windows/apps/design/motion/ ; https://learn.microsoft.com/en-us/windows/win32/winauto/accessibility-best-practices
- Fluent 2 reference: https://fluent2.microsoft.design/accessibility ; https://fluent2.microsoft.design/motion/
- No tests use live Desktop Commander Remote, system permissions, user installations, real logs, SMB, releases or production branches.

## Historical artifacts

Two historical %TEMP%\RDC-P1-* directories from prior P1 development remain **NOT CLEAN**; their ACL, owner and contents must not be changed or removed here. Every new P2 sandbox directory is separate and GUID-scoped.
