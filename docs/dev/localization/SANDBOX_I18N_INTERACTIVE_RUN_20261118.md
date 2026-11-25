# RDC Relay 1.6.0 — interactive offline FakeOnly Sandbox

**2026-11-18. Test-only execution, no real Remote or installation.**

- Tested immutable Git source: bccf19abe69ada89e78b949ca4e05eca11c47b4e.
- One-click WSB: [local project root]\_archive\RDC_I18n_Interactive_bccf19a_20261118\RDC-I18n-Interactive.wsb.
- ZIP SHA256: c930d0b708f6b37a56960816befe727b1296cdf1d5467181f5bbe2c93248a6a2. Mapped source is read-only; host output is a separate dedicated directory. Networking/clipboard/audio/video/printer/vGPU are disabled in WSB.
- Guest status: MODE=FAKE_ONLY_RC1, NO_REAL_REMOTE=true, TRIAL_ROOT_NOT_USED=true, FAKE_HOST_PROCESS_ALIVE=true, HOST_PID=7740. Guest source SHA matches the archive commit.
- Both fake-host-stdout.txt and fake-host-stderr.txt were empty when checked, with the FakeOnly process still alive. This proves only a surviving guest Fake Host process; it does NOT prove all UI controls are visible or correctly scaled.
- Previous exploratory WSB failed with RC1_TRIAL_ROOT_BOUNDARY by design. The final script explicitly omits TrialRoot in a disposable Sandbox because TrialRoot is reserved for bounded 15–120-second automated OS trials.
- At last check, Windows Sandbox RemoteSession PID 31216 was present and the guest process remained alive. Owner should inspect the actual window and tray manually; close the Sandbox to discard the guest.

## Remaining UI/packaging localization after this handoff

- RESOURCE_KEY_INVENTORY.csv has 261 RU/EN pairs: 193 with explicit source references; 68 not yet wired directly into live displays. They break down as installer=35, owner fallback banner=20, tray title/status=10, legacy GUI=2, journal legacy-only empty text=1.
- Do not translate exact Remote Connection banner parser anchor or fixed raw provider event codes. The remaining Owner banner/tray phrases need display-only review, especially the vendor-provided header.
- Release Setup/Upgrade/Repair/Uninstall and fresh-install Windows language suggestion remain separate work from GUI visual acceptance. No release GO.

**State: interactive FakeOnly Sandbox ready for owner inspection, not production validation.**
