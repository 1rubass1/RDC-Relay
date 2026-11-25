# RDC Relay 1.6.0 — Interactive Owner GUI / tray, offline FakeOnly Sandbox

**Goal:** allow the product owner to click and visually inspect the actual new Owner GUI/tray in both Russian and English, without an installed client, Remote, sign-in or credentials.

## What runs

- A disposable Windows Sandbox is launched from a .wsb file under [local project root]\_archive (not in the installed RDC Relay folder). The configuration explicitly disables network, input devices, vGPU, clipboard and printer forwarding.
- Only one read-only host input mapping (source.zip, SHA256, revision.txt and Tests/Sandbox-V16I18nInteractive.ps1) and one writable guest output mapping are used.
- The guest extracts the immutable source archive into C:\RDC-I18n-Preview and launches Source/rc1-tray-host.ps1 with **-FakeOnly only**. Its harmless fake Host state lives in the disposable guest user's LocalAppData. The strict -TrialRoot option is intentionally not used: it is reserved for automatic 15–120 second tests and rejects arbitrary paths. There are no -Full, -ObserveExisting, account authorization or actual Remote launch arguments.
- The GUI and tray are real WinForms source-level components with synthetic Host state. Account controls that would act on Remote are unavailable in FakeOnly mode. Language choice and Help can still be inspected; no actions affect STARMER installed apps.
- Guest bootstrap writes Output/interactive-status.txt and fake-host-stdout/stderr.txt. Input is verified by SHA256 before extraction; on any failed integrity check it refuses to start.

## Owner visual checklist

1. On STARMER double-click the prepared RDC-I18n-Interactive.wsb under [local project root]\_archive\RDC_I18n_Interactive_<commit>_<date>.
2. Sandbox opens a disposable desktop. Look for the RDC Relay window; if it is not frontmost, use the tray overflow icon and RDC Relay menu > Open window.
3. Open Language / Язык from the tray (or Account menu when enabled); switch English, then Russian. Check title, connection status, quota, main actions, Help/About and diagnostic journal, menus, tooltips and labels.
4. Close the GUI window with X, then reopen from the tray. The FakeOnly Host stays running; no Desktop Commander Remote process exists.
5. Exit the FakeOnly app via tray > Exit RDC Relay, then close the Sandbox window to discard guest state.
6. If a screenshot is desired, take it INSIDE Sandbox or report visible issues; do not copy passwords/token/real account state. Clipboard redirection is disabled by design.

## Limitations

- FakeOnly does not exercise real managed/observed Remote, account authorization, actual update installation, Host recovery, real network, Setup/Repair/Uninstall or migration/rollback.
- Confirmation dialogs Stop, Reconnect and Account Switch are already exercised via real factory screenshots and safe default-No automated tests. In FakeOnly mode they are not necessarily reachable by clicking unavailable Remote actions.
- Windows scaling 125%, 150%, 200%, high-contrast themes and screen-reader inspection still need separate manual attention.
- The generated .wsb lives outside Git and is regenerated only from a known committed SHA. Do not substitute the currently installed main RDC Relay application.

**State:** manual GUI acceptance test fixture, not release GO.
