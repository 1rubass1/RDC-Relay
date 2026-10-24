# Strictly remove ONLY a stopped disposable P2 test fixture; no process killing.
param([Parameter(Mandatory=$true)][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$path=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd([char]92)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)+[char]92
if(-not $path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
   [IO.Path]::GetFileName($path) -cnotmatch '^RDC-P3-[0-9a-f]{32}$'){
  throw 'REFUSED: only unique RDC-P3-<GUID> directories in TEMP'
}
if(-not(Test-Path -LiteralPath $path)){Write-Output 'P3_FIXTURE_ALREADY_ABSENT';exit 0}
if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){
  throw 'REFUSED: reparse point fixture path'
}
$hostFile=Join-Path $path 'Host.ps1';$guiFile=Join-Path $path 'Gui.ps1'
$items=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop)
$active=@($items|Where-Object{
  $_.ProcessId -ne $PID -and
  (([string]$_.CommandLine).Contains(' -File "'+$hostFile+'"') -or
  ([string]$_.CommandLine).Contains(' -File "'+$guiFile+'"'))
})
if($active.Count){throw ('REFUSED: test fixture Host/GUI still running: '+($active.ProcessId -join ','))}
$unknown=@(Get-ChildItem -LiteralPath $path -Force | Where-Object {
  $_.Name -notin @('P1Core.cs','P1Wire.cs','Host.ps1','Gui.ps1','DemoGui.ps1','rdc-banner.png','controller-auth.json','gui-ticket.json','gui-pulse.txt','pause-gui-ipc.flag')
})
if($unknown.Count){throw ('REFUSED: unexpected files in fixture: '+($unknown.Name -join ','))}
$links=@(Get-ChildItem -LiteralPath $path -Force | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $_.PSIsContainer})
if($links.Count){throw ('REFUSED: linked or nested fixture path: '+($links.Name -join ','))}
Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
Write-Output ('P3_STOPPED_FIXTURE_CLEANED='+$path)
