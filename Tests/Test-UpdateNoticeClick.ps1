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
foreach($name in @('Test-RdcAutoUpdateEnabled','Set-RdcAutoUpdateEnabled')){
    $preference=$ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $name
    },$true)
    if(-not $preference){throw ('Missing real preference code: '+$name)}
    . ([scriptblock]::Create($preference.Extent.Text))
}

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
    $script:autoUpdatePreferencePath=Join-Path $root 'auto-update.opt-out'
    Assert (Test-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath) 'Auto-update default must be ON'

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

    # Turning OFF auto-update persists across subsequent launches, even when
    # version checks and the clickable update notification remain enabled.
    Set-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath $false
    Assert (-not (Test-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath)) 'Auto-update OFF must be persisted'
    $SkipUpdate = $false
    $script:updateInstallRequested = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 2 -and $script:completeCount -eq 2) 'Auto-update OFF must not start updater during program launch'
    $script:updateInstallRequested = $true
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 3 -and
        $script:launches[2].Arguments -contains '-Force') 'Explicit user click still starts forced updater while auto-update is OFF'
    Set-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath $true
    Assert (Test-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath) 'Auto-update ON removes opt-out marker'
    $script:updateInstallRequested = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 4 -and
        $script:launches[3].Arguments -notcontains '-Force') 'Startup update resumes after user checks Auto-update ON'

    # A missing updater should not launch a process or interrupt an active Remote.
    Remove-Item -LiteralPath (Join-Path $root 'update.ps1') -Force
    $SkipUpdate = $true
    $script:updateInstallRequested = $true
    $script:initializing = $false
    Start-RuntimeInitialization
    Assert ($script:launches.Count -eq 4) 'Missing updater launched unexpectedly'
    Assert ($script:completeCount -eq 3) 'Missing updater did not finish initialization'

    Write-Output 'PASS: default ON; OFF blocks startup across restarts; manual click overrides OFF and -SkipUpdate; ON restores startup; missing updater safe'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
