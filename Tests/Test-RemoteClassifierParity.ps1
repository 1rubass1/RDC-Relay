# Compare pristine PROG-003A and current PROG-004 with identical AST fixtures.
# Requires a locally preserved baseline file; never starts or attaches to Remote.
param(
    [Parameter(Mandatory=$true)][string]$BaselineSourcePath
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runner=Join-Path $PSScriptRoot 'Test-RemoteCharacterization.ps1'
$current=Join-Path $root 'Source/remote-window.ps1'
$expectedBaselineSha='7D0BC5531A51514F12248EEB70C2D3FC5072772C48414BB45A42730A0BD6D19C'
if(-not(Test-Path -LiteralPath $BaselineSourcePath -PathType Leaf)){throw 'Baseline source is absent'}
$beforeHash=(Get-FileHash -LiteralPath $BaselineSourcePath -Algorithm SHA256).Hash
if($beforeHash -ne $expectedBaselineSha){throw 'Baseline source hash mismatch; refuse an unverifiable comparison'}
if((Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash -eq $beforeHash){throw 'Current source does not contain a refactor to compare'}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-PROG004-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
$oldTrace=Join-Path $dir 'before.json';$newTrace=Join-Path $dir 'after.json'
try {
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -SourcePath $BaselineSourcePath -TracePath $oldTrace | Select-Object -Last 2
    if($LASTEXITCODE -ne 0){throw ('Baseline fixture failed with '+$LASTEXITCODE)}
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -SourcePath $current -TracePath $newTrace | Select-Object -Last 2
    if($LASTEXITCODE -ne 0){throw ('Refactored fixture failed with '+$LASTEXITCODE)}
    $a=(Get-FileHash -LiteralPath $oldTrace -Algorithm SHA256).Hash
    $b=(Get-FileHash -LiteralPath $newTrace -Algorithm SHA256).Hash
    if($a -ne $b){throw ('TRACE MISMATCH: before '+$a+' after '+$b)}
    Write-Output ('PASS: PROG-004 complete-line fixture states/effect ordering match, SHA256='+$a)
} finally {
    if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Force -Recurse}
}
