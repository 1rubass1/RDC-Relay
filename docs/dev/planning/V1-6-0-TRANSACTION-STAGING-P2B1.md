# RDC Relay 1.6.0 — P2b1 non-activating durable release stage

**2026-11-19 | Implemented on isolated topic branch | NOT a public Setup or release GO.**

## Why this phase exists

The approved Owner Host/GUI runs separately from the legacy 1.5.x single-window GUI. The current public `build-release.ps1` still builds the legacy 1.5.x single-window product and deliberately refuses v1.6.0. The private `build-rc1-full.ps1` packages a distinct `PRIVATE_FULL_RC1` overlay with temporary candidate flags. Publishing either as a public 1.6.0 installer would violate the release boundary. Before any new Setup modifies shortcuts or Installed Apps, it needs an immutable release payload and a deterministic recovery record.

## Implemented

- `Installer/RdcReleaseDurableStage.cs` — stand-alone C# immutable payload staging core. It **does not** launch Setup, Remote, a GUI or Host; it never writes registry, Installed Apps, shortcuts, OAuth storage or the existing 1.5.18 installation. It accepts a caller-provided, **trusted** complete file list of relative paths, exact sizes and SHA-256 hashes. This list must eventually be embedded into a reviewed public Setup, not read untrusted from the same folder as a payload.
- Preflights: absolute distinct source/store roots, reject reparse ancestors and members before traversing (no recursive symlink traversal); strict bounded relative names, reserved Windows devices, case-insensitive file/directory collisions, unknown extra files, source/destination size/hash mismatches, oversized members, extra staged files and private `rc1-candidate.json`. Requires the separate tray Host script, Owner GUI and `RdcOwnerRuntime.dll` markers; therefore a legacy-only GUI package is refused.
- A full payload is first copied to `releases/.staging-<digest>-<random>` with each file hash rechecked, `FileStream.Flush(true)`, and an exact embedded ledger. Only verified data can be moved within the same volume to immutable `releases/release-<content-hash>`. Already prepared releases are reverified and returned idempotently; a different release is staged side by side, leaving the previous release intact for future rollback.
- Two alternating small journal slots `.rdc-stage-journal-0/1` record monotonic generation, operation identity, and phases `WRITING → MOVING → READY`, each with a SHA-256 checksum and atomic file replace. File locking prevents concurrent staging. A malformed/colliding journal fails closed; the hash is an **integrity check**, not a signature or authentication of a publisher.
- `Recover(...)` never guesses during `WRITING`; a fully verified `MOVING` stage can complete its directory rename, and a `READY` release is verified. `AbandonIncomplete(...)` can, **only for a matching unfinished WRITING transaction**, move its exact inert temporary stage to `.aborted-<identity>`, record `ABORTED`, and then permit a fresh preparation. It leaves all old releases and aborted evidence intact; nothing is silently deleted.
- `PrepareWithFault` artificial fault injection is wrapped in `#if RDC_INSTALLER_TEST`. The ordinary production compile only exposes `Prepare`, `Recover`, and `AbandonIncomplete`; it cannot request an injected fault.

## Test evidence

`Tests/Test-V16ReleaseDurableStage.ps1` compiles the real C# source together with `Tests/RdcReleaseDurableStageAssertions.cs` **only with** `RDC_INSTALLER_TEST`, runs disposable synthetic byte payloads under the current user's Temp, and removes only the known test fixture after checking for reparse paths.

**44 PASS / 0 FAIL**: full staging; source exactness and sha, idempotent same-version repeat, side-by-side replacement preserving old bytes, failpoints after begin/copy, before/after atomic directory move, crash recovery, explicit quarantine-and-retry, wrong manifest rejection, corrupt journal refusal, tampered release rejection, path traversal, source extras, legacy-only marker rejection, case-insensitive collision, and exclusive lock. A second compile without `RDC_INSTALLER_TEST` verifies the fault injection method is absent.

An expanded local regression (new stage + legacy release builder gate + release decision, UI and language + blocked RC1 source packaging and negative archive tests) passed **8 suites, 264 PASS / 0 FAIL**. The exact **Git staged tree** (`9f9804187dfafcf5362743e0f90db9c733f0c218`) was separately archived into a new disposable Temp directory and passed the same eight suites with **264 PASS / 0 FAIL**. The historical G4 blocked fixture was updated to compile current Host C# with `RdcUiLanguage.cs`; its review-only ZIP membership and prohibition on release/Remote stayed unchanged. A production compile without `RDC_INSTALLER_TEST` was also checked for absence of the `PrepareWithFault` entrypoint.

This is **simulated process failure** verification only; physical power loss, NTFS metadata flush and Windows reboot recovery are NOT CHECKED. Do not call the public installer crash/power-loss safe on this evidence.

## Remaining blocking tasks

1. **P2b2 trusted full-Host release package and launcher:** a dedicated public v1.6.0 build with no RC1/pilot flags, release version identity, safe executable metadata, exact assets and embedded/hard-bound trusted member hashes. Do not clear the 1.6 blocker in the legacy public builder.
2. **P2b3 transaction publication:** verified per-user install root, no concurrent running Remote/Host, strict legacy 1.5.18 and RC1 pilot ownership detection, shortcut/ARP/uninstall and updater consistency for the exact path; a **durable** metadata commit/recovery mechanism (not the old in-memory `RdcReleaseMetadataSnapshot` alone).
3. **P2b4 disposable OS matrix:** fresh, stable migration, pilot overlay, active Remote refusal, downgrade, repair/uninstall, hash tampering, injected copy and registry failure, abrupt termination and real OS restart; 125–200% GUI scaling and bilingual first-run continuity.
4. Independent code/security review, exact release allowlist audit, owner approval before any real-user install, merge, GitHub push/tag or stable-feed publication.

**Decision: GO for the next bounded installer-transaction implementation slice. NO GO for public Setup 1.6.0 or changes to STARMER's installed app.**
