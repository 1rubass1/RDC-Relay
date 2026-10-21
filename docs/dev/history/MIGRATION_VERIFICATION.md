# RDC Relay — Playbook migration verification

**Date:** 2026-10-22. **Scope:** migration and branch/document boundaries only. No new runtime tests.

- **PASS**: 23 Markdown files scanned as valid UTF-8, with known token/email patterns rejected.
- **PASS**: 58 links between active/current Markdown records resolve on STARMER. Links inside frozen legacy archives are historical and not treated as current navigation contracts.
- **PASS**: original local archived Markdown SHA256 checks match migration manifest. Source remains intact in `_archive/pre-playbook-2026-10-22`; original `.pen` additionally backed up locally.
- **PASS**: three tunnel identifiers in the historical Spike 0 Git copy redacted; two account-label email values in the public Pen Git copy replaced with `ACCOUNT-PLACEHOLDER`; no actual values printed in the audit.
- **PASS**: Pen source after redaction parses as JSON; original design saved locally. Bitmap assets are copied unmodified.
- **PASS (static)**: current `Scripts/build-release.ps1` uses an explicit `Source/` payload allowlist for updater manifest, Setup embedded resources and Portable archive. No governance/research/design files in its copy list.
- **PASS (existing binary)**: existing v1.5.18 Portable ZIP on STARMER has 12 entries and contains no Markdown, `.pen` or development directories.
- **NOT CHECKED**: a newly built Setup EXE from the migration branch; migration did not run a new release build, publish, stop Remote, or replace installation.
- **NOT CHECKED**: actual ChatGPT custom MCP authorization; unrelated to documentation migration.

Development source: PR #1 into `development`, not `main` or `stable`. Public development branches are **not private storage**. This verification is a snapshot, not a permanent guarantee for future packaging changes.
