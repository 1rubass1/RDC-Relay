# P3A fail-closed removal of a VERIFIED own-run fixture, never a generic folder.
param([Parameter(Mandatory=$true)][string]$FixtureRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'P3-Ownership.ps1')
try{
 $state=Join-Path $PSScriptRoot 'RunState'
 $bound=Get-P3BoundRun $state $FixtureRoot
 [void](Assert-P3Inventory $bound.Root $bound.MarkerData)
 $bound=Get-P3BoundRun $state $FixtureRoot
 [void](Assert-P3Inventory $bound.Root $bound.MarkerData)
 Remove-Item -LiteralPath $bound.Root -Recurse -Force -ErrorAction Stop
 if([IO.Directory]::Exists($bound.Root)){throw 'NOT CLEAN: fixture directory still exists'}
 Write-Output ('P3_OWNED_FIXTURE_REMOVED='+$bound.Root)
 exit 0
}catch{
 [Console]::Error.WriteLine(('NOT CLEAN: удаление запрещено: '+$_.Exception.Message))
 exit 2
}
