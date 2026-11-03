# PROG-006A-G7 — harness integrity and injected owner-tree contract

Date: 2026-10-25 (Europe/Moscow). Programmer, STARMER Windows PowerShell 5.1.
Scope: `feature/v1.6-host-gui-owner-pilot`, Draft PR #23; G6 remains CONDITIONAL ACCEPT.

## G7 changes

1. **F1 mandatory sentinel** — `Tests/Invoke-Rc1OwnerOsSmoke.ps1` uses
   `Assert-Rc1MandatorySentinel` before any deletion. Exact canonical direct-TEMP
   path, no reparse, bytes, SHA256 and creation RunId/epoch binding must match.
   Missing, changed, unreadable or redirected sentinel makes `FAIL` and
   `NOT CLEAN`; never prints `OS_DISPOSABLE_CLEAN=TRUE`.
2. **F2 independent at-creation provenance** —
   `Tests/Rc1OsFixtureProof.ps1` creates a fresh private sibling
   `RDC-RC1-OS-PROOF-<GUID>` (protected ACL at directory creation), then
   `creation.json` with CreateNew/flush: run GUID, random epoch,
   canonical trial root/sentinel, original SHA256 of all 16 source files,
   source Git commit, creation/harness birth/session/PID and current SID.
   After exact OS-observed Host/GUI test and zero survivors, `exit.json` is
   CreateNew/flush and binds Host plus GUI PID, birth ticks, parent, session
   and executable to that epoch. Both records are outside the mutable trial
   root. Missing records are never reconstructed from filename shape.
3. `Tests/Remove-Rc1OsSmokeFixture.ps1` now refuses RunIds without both
   records, full hashes, exact root layout, non-reparse path, OS process
   ancestry and survivor inventory; it rechecks surviving file set and
   original hash before **each exact nonrecursive deletion**. `-ValidateOnly`
   is available. Anomalous, legacy or unproven fixture stays `NOT CLEAN`.
   No arbitrary path, broad recursive delete, force stop or historic cleanup.
4. `Source/RdcOwnerProcess.cs` adds an injected-only
   `RemoteTreeCooperativeExit`: Owned requires full pinned PID/birth/session/
   parent/executable/root/run epoch and exact observed descendants;
   Adopted/Unknown refuse. Preflight all identities before any request,
   request child -> parent -> optional Host with bounded waits, refuse on
   unknown child, transport failure, timeout or process survivor. No
   `Process.Start`/`Kill`, network or genuine Remote adapter in this module.
   Product `RdcOwnerRemoteState.RequireSafeStop` remains blocked.
5. **Prospective only, NOT executed:** `Tests/Rc1DummyRemoteActor.ps1` and
   `Tests/Invoke-Rc1DummyRemoteTreeTrial.ps1` outline an exact disposable
   PowerShell actor root + one child. Explicit `-Execute`, separate
   `-OwnerApprovedDummyTree` and `-IndependentPreGate` switches default
   to refusal. The actor has a 30 s self-exit, the controller validates
   PID/birth/session/parent and exact executable, writes cooperative private
   nonce stop signals child then parent, inventory-checks zero survivors,
   exact fixture/sentinel removal only on success. This script has **NOT**
   received independent pre-gate review or owner GO; it must NOT be executed.
   It never imports or contacts Remote v0.2.52.

## G7 measured tests

| Check | Result | Exit | Scope |
| --- | --- | --- | --- |
| `Test-Rc1OsFixtureProvenance.ps1` | **17 PASS / 0 FAIL** | **0** | file-only negative: missing/modified sentinel; forged GUID without proof; changed hash; inconsistent epoch; unknown entry; exact own test fixture cleanup |
| `Test-V16OwnerTreeStop.ps1` | **16 PASS / 0 FAIL** | **0** | fake-injected ancestry/stop and no-force negative conditions |
| `Invoke-V16Rc1SafeRegression.ps1` | **19 suites PASS / 0 FAIL** | **0** | 17 inherited + 2 new G7 suites |
| `Invoke-Rc1OwnerOsSmoke.ps1 -Execute -Cycles 1` (post-fix) | **15 PASS / 0 FAIL**, private source/attestation/sentinel cleaned | **0** | original GUI A->B + Host IPC, no actual Remote |
| `Invoke-Rc1OwnerOsSmoke.ps1 -Execute -Cycles 10` | **43 PASS / 0 FAIL**; Host PID **43560**, UTC ticks **639285135355346422**, 11 unique GUI PIDs, 11/11 IPC and 0 survivors; exact own root+proof cleaned | **0** | 10 native WM_CLOSE on original complete GUI |
| `-Execute -Cycles 1 -InjectConstructorFailure -InjectStartFailure` | **19 PASS / 0 FAIL**; Host PID **56212**, GUI **14972 → 53612**, singleton/IPC ticket recovery, 0 survivors; own root+proof cleaned | **0** | approved FAKE_ONLY injected failure |
| `-Execute -Cycles 1 -ProbeDuplicateHost` | **18 PASS / 0 FAIL**; original Host PID **25976**, duplicate launcher **53340** refused exit 1, GUI **15876 → 41036**, 0 survivors; own root+proof cleaned | **0** | approved FAKE_ONLY duplicate test |
| G7 dummy Remote actor tree | **NOT CHECKED** | guarded default **42** | new owner GO + independent pre-gate required |
| Genuine pinned Remote 0.2.52, install, rollback, stable feed | **NOT CHECKED / NO-GO** | — | no authorization |

**First G7 integration trial (negative diagnostic):** a fresh one-cycle disposable
Host/GUI test passed its operational 14/15 measured assertions but failed
G7 process-proof serialization: PowerShell argument expansion of
`@($processRows)` made the new final `exit.json` unattainable, yielding
`RC1_OS_SMOKE_PASS=15 FAIL=1`, exit 1. Exact root
`%TEMP%\RDC-RC1-OS-329977f0e2c244d4bfb6458cef151d90` and private proof
are **NOT CLEAN / intentionally preserved**. Its original at-creation proof exists
but the missing exit proof must **not** be invented retrospectively. No
Host/GUI survivor was observed in this run; this is not authority to delete.
The subsequent code fix passes the explicit array via `$processRows.ToArray()`.
Historic three P1/P2 TEMP roots remain separately **NOT CLEAN / untouched**.

### Boundaries, caveats, next Reviewer gate

The per-run sidecar has a protected ACL and CreateNew semantics but is not a
signed, cryptographically authenticated record resistant to a malicious
**same-logon** principal who can rewrite both proof and fixture. Validation is
a sequence of filesystem/CIM checks, not an atomic OS transaction; malicious
concurrent TOCTOU is not proved impossible. Fail closed on discovered changes;
do not claim absolute hostile-process safety. Source test fixtures with
synthetic process observations do not prove real OS child-stop behavior.

Independent `REV-006A-G7` should audit F1/F2 actual code paths, negative
assertion quality, file/proof binding, race windows, source tree eligibility,
the non-executed prospective trial actor and fake cooperative exit contract.
G6 OS matrix **remains 5 PASS / 5 PARTIAL / 14 NOT CHECKED**; OS-04...10,
OS-16/24 are **NOT CHECKED** until separately approved dummy-owned tree
trials. RC1 candidate remains `installable=false / publishable=false`, Setup/
Launcher blocked, PR Draft and unmerged.

### Minimal later owner approval request (AFTER REV-006A-G7 pre-gate)

> Разрешаю один отдельный запуск `Tests/Invoke-Rc1DummyRemoteTreeTrial.ps1`
> на STARMER после положительного независимого pre-gate: максимум один
> новый root `powershell.exe` и один его child `powershell.exe`;
> только новый `%TEMP%\RDC-RC1-DUMMY-<GUID>`, отдельный sentinel,
> окно жизни каждого процесса до 30 секунд, запрос кооперативного выхода
> сначала child, затем root, независимая CIM-проверка нулевых выживших;
> никаких принудительных убийств. При неопределённости оставить точный
> каталог `NOT CLEAN`. Не трогать Desktop Commander Remote, v1.5.18,
> исторические TEMP, установщик, updater, аккаунты, main/stable.

This future wording is a **request**, not approval. No installation, release,
real Remote process or new dummy-Remote tree was run during G7.
