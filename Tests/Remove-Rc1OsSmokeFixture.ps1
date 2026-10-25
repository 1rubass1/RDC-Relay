# Conservative cleanup of failed, exact-owned disposable RC1 OS fixtures.
# NEVER accepts arbitrary paths, broad globs, or historic P1/P2 TEMP directories.
param([Parameter(Mandatory=$true)][string[]]$RunIds,[switch]$Execute)
$ErrorActionPreference='Stop'
if(-not $Execute){Write-Output 'NOT CHECKED: explicit -Execute required';exit 42}
$names=@('remote-window.ps1','rc1-tray-host.ps1','rc1-owner-gui.ps1',
 'RdcOwnerWire.cs','RdcOwnerRuntime.cs','RdcOwnerTicketStore.cs',
 'RdcOwnerRemoteState.cs','RdcOwnerProcess.cs','rc1-candidate.json','RDCRelay.ico',
 'divider-caustic.ps','divider-caustic-detail.ps','divider-particles.ps',
 'divider-particles-core.ps','update-notice.ps1','update.ps1')
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
function Assert-NoReparse([string]$p){
 $q=[IO.Path]::GetFullPath($p)
 while($q){
  if([IO.File]::Exists($q) -or [IO.Directory]::Exists($q)){
   if(([IO.File]::GetAttributes($q) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw ('REPARSE_REFUSED '+$q)
   }
  }
  $next=[IO.Path]::GetDirectoryName($q)
  if(-not $next -or $next -ceq $q){break};$q=$next
 }
}
function SameNames([string]$p,[string[]]$expected){
 $actual=@([IO.Directory]::GetFileSystemEntries($p)|ForEach-Object{[IO.Path]::GetFileName($_)})
 if($actual.Count -ne $expected.Count){return $false}
 foreach($entry in $actual){if(-not ($expected -ccontains $entry)){return $false}}
 return $true
}
$prepared=@()
foreach($id in $RunIds){
 if($id -cnotmatch '^[a-f0-9]{32}$'){throw 'NOT_CLEAN_ID_NOT_GUID'}
 $root=Join-Path $temp ('RDC-RC1-OS-'+$id)
 $src=Join-Path $root 'Source'
 $state=Join-Path $root 'owner-state'
 $sentinel=Join-Path $temp ('RDC-RC1-OS-SENTINEL-'+$id+'.txt')
 if(-not [IO.Directory]::Exists($root) -or
  -not [String]::Equals([IO.Path]::GetDirectoryName($root),$temp,[StringComparison]::OrdinalIgnoreCase)){
  throw ('NOT_CLEAN_ROOT_MISSING '+$id)
 }
 foreach($p in @($root,$src,$state,$sentinel)){Assert-NoReparse $p}
 if(-not [IO.Directory]::Exists($src) -or -not [IO.Directory]::Exists($state) -or
  -not (SameNames $root @('Source','owner-state')) -or
  -not (SameNames $src $names) -or
  [IO.Directory]::GetFileSystemEntries($state).Length -ne 0){
  throw ('NOT_CLEAN_UNKNOWN_ENTRIES '+$id)
 }
 foreach($name in $names){
  $p=Join-Path $src $name
  Assert-NoReparse $p
  if(-not [IO.File]::Exists($p)){throw ('NOT_CLEAN_MISSING_FILE '+$id+' '+$name)}
 }
 $marker=Get-Content -LiteralPath (Join-Path $src 'rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($marker.candidate -cne '1.6.0 RC1' -or $marker.liveRemoteEnabled -ne $false -or
    $marker.installable -ne $false){throw ('NOT_CLEAN_INVALID_MARKER '+$id)}
 $expected=[Text.Encoding]::UTF8.GetBytes('RDC RC1 disposable outside sentinel '+$id)
 if(-not [IO.File]::Exists($sentinel)){throw ('NOT_CLEAN_SENTINEL_MISSING '+$id)}
 $actual=[IO.File]::ReadAllBytes($sentinel)
 if($actual.Length -ne $expected.Length){throw ('NOT_CLEAN_SENTINEL_CHANGED '+$id)}
 for($i=0;$i -lt $actual.Length;$i++){
  if($actual[$i] -ne $expected[$i]){throw ('NOT_CLEAN_SENTINEL_CHANGED '+$id)}
 }
 $active=@(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{
  $_.CommandLine -and $_.CommandLine.IndexOf($root,[StringComparison]::OrdinalIgnoreCase) -ge 0
 })
 if($active.Count){throw ('NOT_CLEAN_PROCESS_REFERENCES_ROOT '+$id)}
 $prepared+=,@{Id=$id;Root=$root;Source=$src;State=$state;Sentinel=$sentinel}
 Write-Output ('PASS VERIFIED_DISPOSABLE_ONLY '+$id)
}
if($prepared.Count -ne $RunIds.Count){throw 'NOT_CLEAN_PREPARE_COUNT'}
foreach($owned in $prepared){
 # Preflight after the read-only pass, immediately before each exact-file removal.
 Assert-NoReparse $owned.Root
 if(-not (SameNames $owned.Root @('Source','owner-state')) -or
    -not (SameNames $owned.Source $names) -or
    [IO.Directory]::GetFileSystemEntries($owned.State).Length -ne 0){
  throw ('NOT_CLEAN_CHANGED_BEFORE_DELETE '+$owned.Id)
 }
 foreach($name in $names){[IO.File]::Delete((Join-Path $owned.Source $name))}
 [IO.Directory]::Delete($owned.Source,$false)
 [IO.Directory]::Delete($owned.State,$false)
 [IO.Directory]::Delete($owned.Root,$false)
 [IO.File]::Delete($owned.Sentinel)
 Write-Output ('PASS CLEANED_EXACT_FAILED_SMOKE_FIXTURE '+$owned.Id)
}
exit 0
