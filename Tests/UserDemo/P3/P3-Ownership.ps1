# P3A: narrow owner-run validation. A marker proves consistency, not trust
# against hostile code running as the same Windows user.
$script:P3ExpectedFiles=@('Host.ps1','Gui.ps1','DemoGui.ps1','P1Core.cs','P1Wire.cs','rdc-banner.png')
$script:P3VolatileFiles=@('controller-auth.json','gui-ticket.json','gui-pulse.txt','pause-gui-ipc.flag')
function Assert-P3NoLinks([string]$Path,[bool]$LeafMayBeMissing=$false) {
 $full=[IO.Path]::GetFullPath($Path)
 $drive=[IO.Path]::GetPathRoot($full)
 $relative=$full.Substring($drive.Length)
 $walk=$drive
 foreach($part in ($relative -split '[\\/]')){
  if([string]::IsNullOrEmpty($part)){continue}
  $walk=[IO.Path]::Combine($walk,$part)
  if(-not ([IO.File]::Exists($walk) -or [IO.Directory]::Exists($walk))){
   if($LeafMayBeMissing -and [String]::Equals($walk,$full,[StringComparison]::OrdinalIgnoreCase)){return}
   throw ('NOT CLEAN: missing path component '+$walk)
  }
  if(([IO.File]::GetAttributes($walk) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw ('NOT CLEAN: reparse point '+$walk)
  }
 }
}
function Assert-P3DirectRoot([string]$Candidate,[bool]$RequireExists=$true) {
 if([string]::IsNullOrWhiteSpace($Candidate)){throw 'NOT CLEAN: empty fixture root'}
 $path=[IO.Path]::GetFullPath($Candidate).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
 if(-not [String]::Equals([IO.Path]::GetDirectoryName($path),$temp,[StringComparison]::OrdinalIgnoreCase) -or
   [IO.Path]::GetFileName($path) -cnotmatch '^RDC-P3-[0-9a-f]{32}$'){
  throw ('NOT CLEAN: not an exact direct TEMP child: '+$path)
 }
 if($RequireExists -and -not [IO.Directory]::Exists($path)){throw ('NOT CLEAN: own root absent: '+$path)}
 Assert-P3NoLinks $temp
 Assert-P3NoLinks $path (-not $RequireExists)
 return $path
}
function Assert-P3MetadataFile([string]$Path){
 if(-not [IO.File]::Exists($Path)){throw ('NOT CLEAN: missing metadata '+$Path)}
 Assert-P3NoLinks $Path
}
function Read-P3Json([string]$Path){
 Assert-P3MetadataFile $Path
 return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop)
}
function Assert-P3Identity([object]$M,[object]$O,[string]$Root){
 $parts=[IO.Path]::GetFileName($Root).Substring(7)
 if([string]$M.RunId -cnotmatch '^[0-9a-f]{32}$' -or [string]$M.RunId -cne $parts -or
  [string]$O.RunId -cne [string]$M.RunId -or
  [string]$M.RunProof -cnotmatch '^[0-9a-f]{32}$' -or
  [string]$O.RunProof -cne [string]$M.RunProof -or
  [int]$M.Schema -ne 1 -or [int]$O.Schema -ne 1 -or
  [string]$M.HostPID -cnotmatch '^[0-9]+$' -or
  [long]$M.HostPID -le 0 -or [long]$O.HostPID -ne [long]$M.HostPID -or
  [long]$M.HostStartTicks -le 0 -or [long]$O.HostStartTicks -ne [long]$M.HostStartTicks -or
  [string]$M.HostGeneration -cnotmatch '^[0-9a-f]{32}$' -or
  [string]$O.HostGeneration -cne [string]$M.HostGeneration -or
  -not [String]::Equals([string]$M.Root,$Root,[StringComparison]::OrdinalIgnoreCase) -or
  -not [String]::Equals([string]$O.Root,$Root,[StringComparison]::OrdinalIgnoreCase)){
  throw 'NOT CLEAN: launch identity does not match independent marker and fixture record'
 }
}
function Assert-P3Inventory([string]$Root,[object]$M){
 $hostFile=Join-Path $Root 'Host.ps1';$guiFile=Join-Path $Root 'Gui.ps1'
 $all=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)
 $matched=@($all|Where-Object{
  ([string]$_.CommandLine).Contains(' -File "'+$hostFile+'"') -or
  ([string]$_.CommandLine).Contains(' -File "'+$guiFile+'"')
 })
 foreach($p in $matched){
  if([int]$p.ProcessId -eq [int]$M.HostPID){
   # CIM reports local CreationDate; compare authoritative process start ticks.
   $born=[Diagnostics.Process]::GetProcessById([int]$p.ProcessId)
   try{$ticks=$born.StartTime.ToUniversalTime().Ticks}finally{$born.Dispose()}
   if($ticks -ne [long]$M.HostStartTicks){throw 'NOT CLEAN: Host PID exists but birth time mismatched'}
  }
 }
 # A running process named by exact fixture command line always blocks removal,
 # including one created as a negative test, even if its start time is unknown.
 if($matched.Count){
  throw ('NOT CLEAN: test Host/GUI still running, PID(s): '+($matched.ProcessId -join ','))
 }
 # PID reuse alone never authorizes deletion. If the historic PID exists
 # for something else, do not treat it as an owned live Host.
 return $true
}
function Assert-P3Fixture([string]$Root,[object]$M,[object]$O){
 $path=Assert-P3DirectRoot $Root
 $allowed=@($script:P3ExpectedFiles)+@($script:P3VolatileFiles)+@('p3-owner.json')
 $entries=@([IO.Directory]::GetFileSystemEntries($path))
 foreach($entry in $entries){
  Assert-P3NoLinks $entry
  $name=[IO.Path]::GetFileName($entry)
  $attrs=[IO.File]::GetAttributes($entry)
  if(($attrs -band [IO.FileAttributes]::Directory) -ne 0 -or $allowed -cnotcontains $name){
   throw ('NOT CLEAN: unknown/nested fixture entry '+$name)
  }
 }
 foreach($name in $script:P3ExpectedFiles){
  $f=Join-Path $path $name
  Assert-P3MetadataFile $f
  $expected=$O.FileHashes.$name
  if([string]::IsNullOrEmpty([string]$expected) -or
   (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -cne [string]$expected){
   throw ('NOT CLEAN: modified/unrecognized fixture file '+$name)
  }
 }
 if([string]$O.RunId -cne [string]$M.RunId){throw 'NOT CLEAN: inconsistent provenance'}
 return $path
}
function Get-P3BoundRun([string]$StateRoot,[string]$OptionalFixtureRoot=''){
 $statePath=[IO.Path]::GetFullPath($StateRoot)
 Assert-P3NoLinks $statePath
 $marker=Join-Path $statePath 'active-demo.json'
 $m=Read-P3Json $marker
 $root=Assert-P3DirectRoot ([string]$m.Root)
 if($OptionalFixtureRoot){
  $requested=Assert-P3DirectRoot $OptionalFixtureRoot
  if(-not [String]::Equals($root,$requested,[StringComparison]::OrdinalIgnoreCase)){throw 'NOT CLEAN: delete argument and own-run marker differ'}
 }
 $o=Read-P3Json (Join-Path $root 'p3-owner.json')
 Assert-P3Identity $m $o $root
 # The Host writes this private, independent rendezvous *before* the launcher
 # records RunId/RunProof. It binds both user-editable provenance records to
 # the actual process creation identity, without logging any IPC secret.
 $auth=Read-P3Json (Join-Path $root 'controller-auth.json')
 $expectedPipe='rdc-p3-ctl-'+[string]$m.RunId
 if([string]$auth.pipe -cne $expectedPipe -or
    [long]$auth.hostPid -ne [long]$m.HostPID -or
    [long]$auth.hostTicks -ne [long]$m.HostStartTicks -or
    [string]$auth.hostGeneration -cne [string]$m.HostGeneration -or
    [string]::IsNullOrWhiteSpace([string]$auth.nonce)){
   throw 'NOT CLEAN: marker and owner provenance disagree with protected Host rendezvous'
 }
 [void](Assert-P3Fixture $root $m $o)
 return [pscustomobject]@{Root=$root;Marker=$marker;MarkerData=$m;OwnerData=$o}
}
