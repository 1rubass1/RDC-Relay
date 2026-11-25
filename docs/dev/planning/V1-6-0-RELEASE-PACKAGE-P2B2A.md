# RDC Relay 1.6.0 — P2b2a: offline full Host + GUI source-review package

**2026-11-19. Development branch only. NONINSTALLABLE / NONLAUNCHABLE / NOT RELEASE GO.**

## Purpose

The existing private `build-rc1-full.ps1` generates an `OWNER_FULL_RC1` pilot with its own shortcut handoff, account state, activation and metadata. The older `build-release.ps1` only builds the legacy 1.5.x GUI and intentionally rejects v1.6.0. Neither is a safe public 1.6.0 release builder.

P2b2a introduces a **distinct offline review artifact** containing the real source files needed by the separate Host + Owner GUI and a freshly compiled `RdcOwnerRuntime.dll`, plus a generated numeric `Source/version.txt=1.6.0`. It is strictly for content, compiler, hash, source and isolated-Sandbox inspection. **It is not yet a runnable product or installer.**

### Build

Run only in a reviewed **clean** `fix/rc1-tray-exit-prompt` checkout:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Scripts\build-v16-release-review.ps1 -Build
```

Omitting `-Build` returns a nonzero refusal. The builder verifies the approved original icon/tray asset SHA-256, compiles the full Host DLL with the exact C# compilation source set, creates a manifest with one size and SHA-256 per byte-exact member, independently validates it through `Installer/RdcReleaseReviewPackage.cs`, and verifies every ZIP entry SHA-256 against the prepared directory. It never reads Remote credentials, starts Host/GUI/Setup, modifies installed application/ARP/shortcuts, or pushes code.

Outputs are **only** under a fresh direct child of the current user's Temp folder, named `RDC-V16-REVIEW-<random32>`:

- `package\payload\` — 25 strictly allowlisted files, including compiled `RdcOwnerRuntime.dll`, separate Owner GUI, tray Host, translation JSON, approved icon/tray artwork and generated 1.6.0 version and review markers
- `package\review-manifest.json` — candidate-only SHA-256 list, explicit `installable=false`, `launchEnabled=false`, `publishable=false` and publisher `RUBASS`
- `RDC-Relay-1.6.0-FullHostGui-REVIEW.zip` — same payload and review manifest, exact 26 ZIP entries, no extra metadata or user secrets
- `RDC-Relay-1.6.0-Offline-Review-Check.exe` — independent, read-only console verifier stamped `1.6.0.0 / RUBASS`, not a launcher or Setup

**Security boundary:** the candidate manifest is **self-attested**: it verifies internal consistency, not publisher authenticity. Neither SHA-256 nor the review verifier is a code signature. The future public Setup must bind its own trusted (and eventually signed) manifest. No assumption of trusted distribution is made here.

### Fail-closed review protection

The builder **never** copies `Source/rc1-candidate.json`. Instead it generates `Source/release-review.json` (installable/launch disabled). It inserts `throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'` immediately after PowerShell's error preference in **COPIES ONLY** of four entrypoints: `remote-window.ps1`, `rc1-tray-host.ps1`, `rc1-quota-client.ps1` and `update.ps1`. Repository source remains byte-identical. This prevents manual launch even if someone deletes the review marker after extracting the ZIP. The read-only C# validator insists that all four entrypoint guards exist. The existing `RdcReleaseDurableStage` separately rejects `Source/release-review.json`, so these review bytes cannot be repurposed into an installable release merely by providing a compatible manifest.

### Sandbox-only verification

On a disposable **network-disabled Windows Sandbox**, copy the ZIP and standalone checker from the output folder, then:

1. Extract the review ZIP into a new folder (containing `payload\` and `review-manifest.json`).
2. Run `RDC-Relay-1.6.0-Offline-Review-Check.exe --verify "<extracted-folder>"`.
3. Expect `RDC_RELEASE_REVIEW_PACKAGE_PASS=25 FAIL=0` and `RDC_RELEASE_REVIEW_INSTALLABLE=FALSE`.
4. Attempt the checker with **no arguments**; it must exit 42 and refuse. Verify that the four scripts contain the review-only throw and are never invoked against a real Remote.

The review verifier and package do **not** display the live RDC Relay GUI. **Do not launch the copied Host/GUI or update scripts.** Sandbox testing of a genuinely installed and functioning 1.6.0 product requires P2b2b (release-aware Host/launcher) and P2b3 (transactional Setup), not this bundle.

### Tests and remaining risks

`Tests/Test-V16ReleaseReviewPackage.ps1` uses disposable synthetic file trees and real C# contract/CLI code to check exact member list, fresh numeric version, release metadata, byte/hash tampering, malformed manifest, extra files/RC1 marker, unsafe install/launch flags, independent checker invocation and default refusal, blocked entrypoint scripts, and explicit rejection by `RdcReleaseDurableStage`.

### Actual clean-commit build and independent artifact results

- Source build commit: `24611e7a6a086749ca2775a79ff1f8c0c32a68ac` on clean topic branch; `Scripts/build-v16-release-review.ps1 -Build` reported `RDC_V16_REVIEW_BUILD_PASS=1`, 25 payload members, no installation.
- Generated archive SHA-256: `0F516F293EFB8B0451D57B1D1D62EF9D36CD242DA2E3461CDD773A28028A3E37`.
- Offline verifier SHA-256: `1B184BC6FFCCF0E105C1D8914CB08B10F6B0047D6A22379A644077C2D9B43FE4`.
- Durable local STARMER test kit: `[local project root]\_archive\RDC_V16_Review_24611e7_20261119\`. Contains the SHA-verified ZIP and verifier, a read-only `Input`, separate writable `Output`, `RDC-Relay-Review.wsb`, and `README-SANDBOX.txt`. Neither the running STARMER Remote nor the installed app was changed.
- `Tests/Test-V16ReleaseReviewPackage.ps1`: **33 PASS / 0 FAIL** synthetic C# contract and compiled verifier; `Tests/Test-V16ReleaseReviewArtifact.ps1` run against **both** original and copied archive: **16 PASS / 0 FAIL each**, including extraction, exact ZIP members, CLI rejection without parameters, four blocked entrypoints, injected DLL byte tampering and restoration.
- Expanded staged Git-index source check (tree `b716f329c6bb1bb0096235d646806224f209b4ba`) had **6 suites / 191 PASS / 0 FAIL**. Compiled Host assembly and verifier are actual artifacts, not mocks. The `.wsb` is configured with Networking, vGPU, clipboard, input devices and printing disabled; Input is mapped read-only, Output separately writable.
- `Tests/Sandbox-V16ReleaseReviewGuest.ps1` is ready to run on Sandbox logon using only .NET ZipFile and the offline verifier; **actual guest run is NOT CHECKED** (reserved for user-led testing). It will write `Output/done.txt` and `Output/review-sandbox-report.txt`.

Pending: ZIP reuse and negative tamper tests in Windows Sandbox; removal of RC1-specific paths, visible version and pilot data handling from production Host; new real launcher that pins an authenticated installed release; a signed trusted package manifest and Setup; durable ARP/shortcut/update/uninstall publication and rollback; OS migration/restart trials. **None are implied by this review artifact.**
