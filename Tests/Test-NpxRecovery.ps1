# Regression tests for startup npm ENOENT recovery. Never touch real npm cache.
$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { $env:RDC_TESTS_DIR }
if (-not $here) { throw 'Missing test directory' }
$root = Split-Path -Parent $here
$source = Join-Path $root 'Source\remote-window.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ('PowerShell syntax errors: '+$parseErrors.Count) }
$fn = $ast.Find({
    param($n)
    $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Repair-DesktopCommanderMissingNpxPackageJson'
},$true)
if (-not $fn) { throw 'Recovery function is missing' }
. ([scriptblock]::Create($fn.Extent.Text))

$oldLocalAppData = $env:LOCALAPPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('rdc-npx-recovery-' + [guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA = Join-Path $testRoot 'AppData\Local'
$npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
$logPath = Join-Path $testRoot 'remote.log'
$nl = [Environment]::NewLine
$SelfTest = $false
$Preview = $false
$script:captured = @()
function Add-Log([string]$text) { $script:captured += $text }
function Assert([bool]$value,[string]$message) { if (-not $value) { throw $message } }
function New-Entry([string]$name,[bool]$withPackageJson = $false) {
    $dir = Join-Path $npxRoot $name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'sentinel.txt') -Value 'fixture'
    if ($withPackageJson) {
        Set-Content -LiteralPath (Join-Path $dir 'package.json') -Value '{}'
    }
    return $dir
}
function Set-NpmError([string]$candidate,[string]$code = 'ENOENT',[string]$prefix = 'npm error') {
    $message = @(
        ($prefix+' code '+$code),
        ($prefix+' syscall open'),
        ($prefix+' path '+$candidate),
        ($prefix+' errno -4058'),
        ($prefix+' enoent Could not read package.json')
    ) -join $nl
    [IO.File]::WriteAllText($logPath,$message,[Text.Encoding]::UTF8)
}
function Reset-Recovery { $script:npxMissingPackageRepairAttempted = $false }

try {
    New-Item -ItemType Directory -Force -Path $npxRoot | Out-Null
    $good = New-Entry '1111111111111111' $true
    $broken = New-Entry 'c329005a7fd3ed13'
    Set-NpmError (Join-Path $broken 'package.json')
    Reset-Recovery
    Assert (Repair-DesktopCommanderMissingNpxPackageJson) 'ENOENT was not recovered'
    Assert (-not (Test-Path -LiteralPath $broken)) 'Broken cache entry remains'
    Assert (Test-Path -LiteralPath (Join-Path $good 'package.json')) 'Unrelated cache was removed'
    Assert (-not (Repair-DesktopCommanderMissingNpxPackageJson)) 'Recovery repeated in one episode'

    $outside = Join-Path $testRoot 'not-npx\2222222222222222'
    New-Item -ItemType Directory -Force -Path $outside | Out-Null
    Set-NpmError (Join-Path $outside 'package.json')
    Reset-Recovery
    Assert (-not (Repair-DesktopCommanderMissingNpxPackageJson)) 'Outside path allowed'
    Assert (Test-Path -LiteralPath $outside) 'Outside path deleted'

    $notEnoent = New-Entry '3333333333333333'
    Set-NpmError (Join-Path $notEnoent 'package.json') 'EACCES'
    Reset-Recovery
    Assert (-not (Repair-DesktopCommanderMissingNpxPackageJson)) 'Non-ENOENT allowed'
    Assert (Test-Path -LiteralPath $notEnoent) 'Non-ENOENT entry deleted'

    Set-NpmError (Join-Path $good 'package.json')
    Reset-Recovery
    Assert (-not (Repair-DesktopCommanderMissingNpxPackageJson)) 'Existing package.json deleted'

    $nested = New-Entry '4444444444444444'
    $subdir = Join-Path $nested 'extra'
    New-Item -ItemType Directory -Force -Path $subdir | Out-Null
    Set-NpmError (Join-Path $subdir 'package.json')
    Reset-Recovery
    Assert (-not (Repair-DesktopCommanderMissingNpxPackageJson)) 'Nested path allowed'
    Assert (Test-Path -LiteralPath $nested) 'Nested directory deleted'

    $oldFormat = New-Entry '5555555555555555'
    Set-NpmError (Join-Path $oldFormat 'package.json') 'ENOENT' 'npm ERR!'
    Reset-Recovery
    Assert (Repair-DesktopCommanderMissingNpxPackageJson) 'Legacy npm ERR! syntax not recognized'

    $disabled = New-Entry '6666666666666666'
    Set-NpmError (Join-Path $disabled 'package.json')
    Reset-Recovery
    $SelfTest = $true
    Assert (-not (Repair-DesktopCommanderMissingNpxPackageJson)) 'SelfTest modified cache'
    $SelfTest = $false
    Assert (Test-Path -LiteralPath $disabled) 'SelfTest deleted entry'

    Write-Output 'PASS: npx ENOENT detection, bounded deletion, retry guard and safety cases (7 scenarios)'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
