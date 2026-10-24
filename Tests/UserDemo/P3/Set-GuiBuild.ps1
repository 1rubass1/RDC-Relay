# Edit only a stopped GUI source inside one uniquely named P2 fixture under TEMP.
param([Parameter(Mandatory=$true)][string]$FixtureRoot,
      [ValidateSet('A','B')][string]$Build='B')
$ErrorActionPreference='Stop'

function Normalize-P3Directory([string]$Path){
  $full=[IO.Path]::GetFullPath($Path)
  $volume=[IO.Path]::GetPathRoot($full)
  if($full.Length -gt $volume.Length){
    $full=$full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  }
  return $full
}
function Test-P3NoReparsePath([string]$Path,[switch]$AllowMissingLeaf){
  try{
    $current=[IO.Path]::GetFullPath($Path)
    $volume=[IO.Path]::GetPathRoot($current)
    $leaf=$true
    while(-not [string]::IsNullOrEmpty($current)){
      try{
        $attributes=[IO.File]::GetAttributes($current)
        if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
      }catch{
        if(-not ($leaf -and $AllowMissingLeaf)){return $false}
        $parent=[IO.Path]::GetDirectoryName($current)
        if(-not $parent -or -not [IO.Directory]::Exists($parent)){return $false}
        $name=[IO.Path]::GetFileName($current)
        foreach($entry in [IO.Directory]::GetFileSystemEntries($parent)){
          if([String]::Equals([IO.Path]::GetFileName($entry),$name,[StringComparison]::OrdinalIgnoreCase)){return $false}
        }
      }
      if([String]::Equals($current,$volume,[StringComparison]::OrdinalIgnoreCase)){break}
      $next=[IO.Path]::GetDirectoryName($current)
      if(-not $next -or $next -eq $current){return $false}
      $current=$next;$leaf=$false
    }
    return $true
  }catch{return $false}
}
function Assert-P3Fixture([string]$RootPath){
  $root=Normalize-P3Directory $RootPath
  $temp=Normalize-P3Directory ([IO.Path]::GetTempPath())
  if(-not [String]::Equals([IO.Path]::GetDirectoryName($root),$temp,[StringComparison]::OrdinalIgnoreCase) -or
     [IO.Path]::GetFileName($root) -cnotmatch '^RDC-P3-[0-9a-f]{32}$'){
    throw 'REFUSED: fixture must be a direct RDC-P3-<GUID> child of TEMP'
  }
  if(-not [IO.Directory]::Exists($root)){throw 'REFUSED: fixture root missing'}
  if(-not (Test-P3NoReparsePath $root)){throw 'REFUSED: reparse point in fixture root or its path components'}
  $gui=[IO.Path]::GetFullPath([IO.Path]::Combine($root,'DemoGui.ps1'))
  if(-not [String]::Equals([IO.Path]::GetDirectoryName($gui),$root,[StringComparison]::OrdinalIgnoreCase) -or
     -not [String]::Equals([IO.Path]::GetFileName($gui),'DemoGui.ps1',[StringComparison]::OrdinalIgnoreCase) -or
     -not [IO.File]::Exists($gui)){
    throw 'REFUSED: expected direct fixture Gui.ps1 missing'
  }
  if(-not (Test-P3NoReparsePath $gui)){throw 'REFUSED: reparse point in Gui.ps1 or its path components'}
  $allowed=@('P1Core.cs','P1Wire.cs','Host.ps1','Gui.ps1','DemoGui.ps1','rdc-banner.png','controller-auth.json','gui-ticket.json','gui-pulse.txt','pause-gui-ipc.flag')
  $entries=@([IO.Directory]::GetFileSystemEntries($root))
  foreach($entry in $entries){
    $name=[IO.Path]::GetFileName($entry)
    $attributes=[IO.File]::GetAttributes($entry)
    if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw ('REFUSED: reparse point in fixture entry '+$name)}
    if(($attributes -band [IO.FileAttributes]::Directory) -ne 0){throw ('REFUSED: unexpected nested directory '+$name)}
    if($allowed -cnotcontains $name){throw ('REFUSED: unexpected fixture file '+$name)}
  }
  return $root
}

$path=Assert-P3Fixture $FixtureRoot
$gui=[IO.Path]::GetFullPath((Join-Path $path 'DemoGui.ps1'))
$hostScript=[IO.Path]::GetFullPath((Join-Path $path 'Host.ps1'))
# Recheck the boundary immediately before process inspection/source access.
$path=Assert-P3Fixture $path
$items=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)
$guiEntry=[IO.Path]::GetFullPath((Join-Path $path 'Gui.ps1'))
$liveGui=@($items|Where-Object {([string]$_.CommandLine).Contains(' -File "'+$guiEntry+'"')})
$liveHost=@($items|Where-Object {([string]$_.CommandLine).Contains(' -File "'+$hostScript+'"')})
if($liveGui.Count){throw ('REFUSED: GUI must close with X before editing; GUI PID '+($liveGui.ProcessId -join ','))}
if($liveHost.Count -ne 1){throw 'REFUSED: exactly one test Host must be running'}

# Validation is repeated directly before both source reads and source write.
$path=Assert-P3Fixture $path
$content=[IO.File]::ReadAllText($gui,[Text.Encoding]::UTF8)
if($content -notmatch '(?m)^\$GuiBuild=''[AB]''\r?$'){throw 'REFUSED: test GUI build marker missing'}
$next=[regex]::Replace($content,'(?m)^\$GuiBuild=''[AB]''(?=\r?$)',('$GuiBuild='+"'"+$Build+"'"))
$path=Assert-P3Fixture $path
[IO.File]::WriteAllText($gui,$next,(New-Object Text.UTF8Encoding($true)))
$path=Assert-P3Fixture $path
$verify=[IO.File]::ReadAllText($gui,[Text.Encoding]::UTF8)
if($verify -notmatch ('(?m)^\$GuiBuild='+"'"+$Build+"'"+'\r?$')){throw 'P2 GUI build write verification failed'}
Write-Output ('P2_GUI_SOURCE_BUILD='+$Build)
Write-Output ('P2_HOST_STILL_PID='+$liveHost[0].ProcessId)
Write-Output 'Double-click only the P2 SANDBOX tray icon to reopen the new GUI process.'
