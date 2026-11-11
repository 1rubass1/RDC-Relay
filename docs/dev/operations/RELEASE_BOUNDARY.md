# RDC Relay — development and release boundary

**Adopted with Playbook migration, 2026-10-22.**

## Branch policy
- `development` is the permanent **dev-only** integration branch. Historical branches are named `develop/*`, which prevents creation of a branch named exactly `develop` in Git.
- Topic branches, including `docs/playbook-onboarding`, target `development`; document/data changes must not be merged into `main`/`stable`.
- `main` is the tested application branch; `stable` is the release update channel. Both initially remain at v1.5.18.
- **Never fast-forward/merge all of development into main**. Release preparation must select and review only release-eligible source commits/files. A documentation migration PR is not release approval.

## Dev-only files prohibited in release commits and payload
`AGENTS.md`, `PROJECT_INDEX.md`, `PROJECT_CONTEXT.md`, `DECISIONS.md`, `COORDINATION/`, `docs/dev/`, raw experiment files, Pen artifacts, internal reports and private logs must not ship in published source branches, installer, Portable ZIP, update manifest, installed payload or release asset downloads.

The current `Scripts/build-release.ps1` uses an explicit `Source/` file allowlist for update manifests, Setup embedded resources and Portable ZIP. **Code inspection** confirms that it does not copy `docs/dev/` or root governance files. This is not a substitute for validating each actual release artifact.

Run the dev-only [Check-ReleaseBoundary.ps1](../tools/Check-ReleaseBoundary.ps1) on the intended checkout, optionally passing `-PortableZip <built archive path>`. It checks public Git data patterns, main/stable commit file paths, the packager allowlists and ZIP entries. It is a guard against common mistakes, **not** proof of confidentiality, installer security or actual release acceptance.

## Pre-release gate
1. Check release-branch diff for dev-only files and secrets; **do not** silently cherry-pick internal records.
2. Audit actual compiled Setup resources, Portable ZIP members, manifest entries and attached release assets for unwanted files, personal data or credentials.
3. Run task-appropriate unit, UI, route and integration regressions on the identified candidate build; record PASS/FAIL/NOT CHECKED.
4. Preserve transactional rollback; human visual approval for subjective changes and user authorization before production/stable/tag publishing.

## Local RC1 installer housekeeping on STARMER

- After a new candidate passes isolated build/manifest checks and its Desktop Setup/Portable SHA-256 hashes are verified, keep **only the newest pair** as loose Desktop RC1 installer files. Keep the stable `RDC.Relay.Setup.v1.5.18.exe` rollback separately and unmodified.
- Move the immediately superseded RC1 pair to `Desktop/RemoteDesktopCommander/Old_Installers_YYYY-MM-DD/Gxx_Superseded_<description>/` after checking source and destination hashes and refusing destination collisions. Historical installer-only archives can be cleared **only with explicit owner authorization**, preferably to Windows Recycle Bin so accidental removals remain recoverable. Do not silently delete historical archives.
- The `Desktop/RemoteDesktopCommander/1.6.0-RC1/` installed app, its backups and `releases/` may hold active rollback/transaction state. Never treat these as stale installers. Also exclude `RDC-RC1-Logger/`, the original launcher's files/backups, user credentials, and all historical TEMP directories from installer cleanup.
- The 2026-11-08 G96 cleanup was owner-authorized: 69 known EXE/ZIP files in two `Old_Installers_2026-10-28`/`2026-10-29` archives were sent to Recycle Bin (no reparse points or other file types); the current 2026-10-29 archive was recreated with only the verified G95 predecessor Setup/Portable. The G96 pair and stable 1.5.18 remained on Desktop, verified byte-for-byte by SHA-256. No installed application, live Remote, diagnostic logger, or credentials were changed.

## Secrets: public repository warning
**Public GitHub `development` branches are public, not secret storage.** Do not commit real tunnel IDs, private endpoint hostnames, active access URLs, personal identifiers, OAuth/API keys, tokens, credential files, private logs or unredacted diagnostic archives. Keep secrets only in protected local storage and exclude them from ALL Git branches, not merely the release. Imported test IDs were redacted; exact originals are backed up only locally on STARMER.

This migration changes documentation and branch organization, not the running app or live Remote session.
