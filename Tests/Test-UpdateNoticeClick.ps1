# Isolated regression: user-requested update must override -SkipUpdate.
# Replaces Start-Process with an in-memory stub; no installed app or Remote touched.
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = Join-Path $ProjectRoot 'Source\remote-window.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ('GUI parse failed: ' + $errors.Count) }
$fn = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Start-RuntimeInitialization'
}, $true)
if (-not $fn) { throw 'Start-RuntimeInitialization is missing' }
. ([scriptblock]::Create($fn.Extent.Text))

function Assert([bool]$ok,[string]$message) { if (-not $ok) { throw $message } }
function Set-RemoteActionsEnabled([bool]$enabled) { $script:actionsEnabled = $enabled }
function Set-State { param($name,$details,$color) }
function Add-Log { param($message) }
function Complete-RuntimeInitialization { $script:completeCount++ }
function Start-Process {
    param(
        [string]$FilePath,
        [object[]]$ArgumentList,
        [string]$WindowStyle,
        [switch]$PassThru
    )
    $script:launches += [pscustomobject]@{
        FilePath = $FilePath
        Arguments = @($ArgumentList)
    }
    return [pscustomobject]@{ HasExited = $false }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('rdc-update-click-' + [guid]::NewGuid().ToString('N'))
$appVersion = '1.5.17'
$script:enableUpdateNotice = $true
$script:launches = @()
$script:completeCount = 0
$script:actionsEnabled = $true
$nl = [Environment]::NewLine

try {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'update.ps1') -Value '# stub: do not execute'

    # The relaunch after an earlier successful update intentionally skips startup checks.
    $SkipUpdate = $true
    $script:updateInstallRequested = $false
    $script:initializing = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 0) 'Passive -SkipUpdate relaunch unexpectedly started updater'
    Assert ($script:completeCount -eq 1) 'Passive -SkipUpdate did not finish initialization'

    # Exact failing sequence: the previous updater relaunched with -SkipUpdate;
    # user clicks the newly visible v1.5.18 notification.
    $script:updateInstallRequested = $true
    $script:initializing = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 1) 'Clicked update was suppressed by -SkipUpdate'
    Assert ($null -ne $script:updateProc) 'Clicked update process was not captured'
    Assert ($script:launches[0].Arguments -contains '-Force') 'Clicked update did not bypass six-hour throttle'
    Assert ($script:launches[0].Arguments -contains '-CurrentVersion') 'Updater omitted installed version'
    Assert (-not $script:actionsEnabled) 'Update controls not disabled during launch'

    # Normal startup without -SkipUpdate retains the existing updater behavior.
    $SkipUpdate = $false
    $script:updateInstallRequested = $false
    $script:initializing = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 2) 'Standard startup check was suppressed'
    Assert ($script:launches[1].Arguments -notcontains '-Force') 'Standard startup incorrectly forced an update'

    # A missing updater should not launch a process or interrupt an active Remote.
    Remove-Item -LiteralPath (Join-Path $root 'update.ps1') -Force
    $SkipUpdate = $true
    $script:updateInstallRequested = $true
    $script:initializing = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 2) 'Missing updater launched unexpectedly'
    Assert ($script:completeCount -eq 2) 'Missing updater did not finish initialization'

    Write-Output 'PASS: explicit update click overrides -SkipUpdate; -Force, normal startup and missing-updater cases'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
