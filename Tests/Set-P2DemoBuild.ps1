# Edit only a user-launched disposable P2 GUI source AFTER its process exited.
param([Parameter(Mandatory=$true)][string]$FixtureRoot,
      [ValidateSet('A','B')][string]$Build='B')
$ErrorActionPreference='Stop'
$path=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd([char]92)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)+[char]92
if(-not $path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
   [IO.Path]::GetFileName($path) -cnotmatch '^RDC-P2-[0-9a-f]{32}$'){
  throw 'REFUSED: not a uniquely named RDC-P2 test directory under TEMP'
}
$gui=Join-Path $path 'Gui.ps1';$hostScript=Join-Path $path 'Host.ps1'
if(-not(Test-Path -LiteralPath $gui)){throw 'REFUSED: disposable GUI source missing'}
$items=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)
$liveGui=@($items|Where-Object {([string]$_.CommandLine).Contains(' -File "'+$gui+'"')})
$liveHost=@($items|Where-Object {([string]$_.CommandLine).Contains(' -File "'+$hostScript+'"')})
if($liveGui.Count){throw ('REFUSED: GUI must close with X before editing; GUI PID '+($liveGui.ProcessId -join ','))}
if($liveHost.Count -ne 1){throw 'REFUSED: exactly one test Host must be running'}
$content=[IO.File]::ReadAllText($gui,[Text.Encoding]::UTF8)
if($content -notmatch '(?m)^\$GuiBuild=''[AB]''\r?$'){throw 'REFUSED: test GUI build marker missing'}
$next=[regex]::Replace($content,'(?m)^\$GuiBuild=''[AB]''\r?$',('$GuiBuild='+"'"+$Build+"'"))
[IO.File]::WriteAllText($gui,$next,(New-Object Text.UTF8Encoding($true)))
Write-Output ('P2_GUI_SOURCE_BUILD='+$Build)
Write-Output ('P2_HOST_STILL_PID='+$liveHost[0].ProcessId)
Write-Output 'Double-click only the P2 SANDBOX tray icon to reopen the new GUI process.'
