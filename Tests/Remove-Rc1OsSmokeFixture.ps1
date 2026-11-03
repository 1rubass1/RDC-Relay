# G7 failed-fixture cleanup: refusal unless BOTH independently created proof files
# and all sixteen original hashes/OS process records validate. No broad cleanup.
param([Parameter(Mandatory=$true)][string[]]$RunIds,[switch]$Execute,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
if(-not $Execute){Write-Output 'NOT CHECKED: explicit -Execute required';exit 42}
. (Join-Path $PSScriptRoot 'Rc1OsFixtureProof.ps1')
try{
 if($RunIds.Count -lt 1 -or $RunIds.Count -gt 8 -or
    @($RunIds|Select-Object -Unique).Count -ne $RunIds.Count){
  throw 'NOT_CLEAN_RUN_IDS_DUPLICATE_OR_INVALID_COUNT'
 }
 # Preflight every requested run before any deletion, then revalidate each at use.
 foreach($id in $RunIds){
  [void](Remove-Rc1AttestedFixture -RunId $id -ValidateOnly)
  Write-Output ('PASS ATTESTED_PREFLIGHT '+$id)
 }
 if($ValidateOnly){Write-Output 'RC1_ATTESTED_VALIDATE_ONLY=TRUE';exit 0}
 foreach($id in $RunIds){Remove-Rc1AttestedFixture -RunId $id}
 exit 0
}catch{
 Write-Output ('NOT CLEAN: '+$_.Exception.Message)
 exit 1
}
