# Offline regression: periodic polling replaces a stale update version.
# No internet, UI window, running Remote process or installed files are touched.
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $ProjectRoot 'Source\update-notice.ps1'),
    [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ('Update notice parse failed: ' + $errors.Count) }
$names = @(
    'Show-RdcUpdateNotice',
    'Hide-RdcUpdateNotice',
    'Get-RdcAvailableVersionFromManifest',
    'Update-RdcUpdateNoticePolling'
)
foreach ($name in $names) {
    $fn = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $name
    }, $true)
    if (-not $fn) { throw ('Missing update-notice function ' + $name) }
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert([bool]$ok,[string]$reason) { if (-not $ok) { throw $reason } }
function New-Timer {
    $timer = [pscustomobject]@{ StartCount = 0; StopCount = 0 }
    $timer | Add-Member ScriptMethod Start { $this.StartCount++ }
    $timer | Add-Member ScriptMethod Stop { $this.StopCount++ }
    return $timer
}
$appVersion = '1.5.16'
$script:enableUpdateNotice = $true
$SelfTest = $false
$Preview = $false
$nl = [Environment]::NewLine
$script:rdcNoticeActive = $false
$script:rdcNoticeInstalling = $false
$script:rdcNoticeAnimationTimer = New-Timer
$script:rdcNoticeControl = [pscustomobject]@{
    OfferedVersion = ''
    BeginCount = 0
    EndCount = 0
    TabStop = $false
}
$script:rdcNoticeControl | Add-Member ScriptMethod Begin {
    param($installed,$available,$text)
    $this.OfferedVersion = $available
    $this.BeginCount++
}
$script:rdcNoticeControl | Add-Member ScriptMethod End {
    $this.OfferedVersion = ''
    $this.EndCount++
}
$hint = [pscustomobject]@{ Text = 'Original footer text' }
$style = [pscustomobject]@{ Width = 440 }
$bottom = [pscustomobject]@{ ColumnStyles = @($null,$style) }
$bottom | Add-Member ScriptMethod PerformLayout {}
$script:httpManifestVersion = '1.5.17'
$script:httpCalls = @()
$script:rdcNoticeHttp = [pscustomobject]@{}
$script:rdcNoticeHttp | Add-Member ScriptMethod GetStringAsync {
    param([string]$url)
    $script:httpCalls += $url
    $content = if ($url -like 'https://api.github.com/*') {
        '{"sha":"' + ('a' * 40) + '"}'
    } else {
        '{"version":"' + $script:httpManifestVersion + '"}'
    }
    return [Threading.Tasks.Task]::FromResult([string]$content)
}
$script:rdcNoticeCheckTask = $null
$script:rdcNoticeCheckPhase = ''
$script:rdcNoticeNextCheck = (Get-Date).AddSeconds(-1)

function Complete-PollCycle {
    # First tick gets the stable ref; second reads manifest; third updates UI.
    Update-RdcUpdateNoticePolling
    Update-RdcUpdateNoticePolling
    Update-RdcUpdateNoticePolling
    Assert ($script:rdcNoticeCheckPhase -eq '') 'Poll did not finish manifest processing'
    Assert ($null -eq $script:rdcNoticeCheckTask) 'Poll task still active'
}
# Initial stable release appears with an interactive update button.
Complete-PollCycle
Assert $script:rdcNoticeActive 'Initial offer was not displayed'
Assert ($script:rdcNoticeControl.OfferedVersion -eq '1.5.17') 'Initial offer wrong'
Assert ($script:rdcNoticeControl.BeginCount -eq 1) 'Initial animation missing'

# Later stable release replaces the visible button during the same session.
$script:httpManifestVersion = '1.5.18'
$script:rdcNoticeNextCheck = (Get-Date).AddSeconds(-1)
Complete-PollCycle
Assert ($script:rdcNoticeControl.OfferedVersion -eq '1.5.18') 'Stale 1.5.17 remained visible'
Assert ($script:rdcNoticeControl.BeginCount -eq 2) 'New version did not restart animation'
Assert ($script:rdcNoticeActive) 'Offer disabled on new version'
Assert ($script:rdcNoticeAnimationTimer.StartCount -eq 2) 'New offer did not start animation'
Assert ($script:httpCalls.Count -eq 4) 'Both polling rounds must fetch current stable commit and manifest'
Assert ($script:httpCalls[1] -like '*aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Source/update-manifest.json') 'Manifest was not pinned to stable SHA'

# Same version must not endlessly reanimate and distract the user.
$script:rdcNoticeNextCheck = (Get-Date).AddSeconds(-1)
Complete-PollCycle
Assert ($script:rdcNoticeControl.BeginCount -eq 2) 'Identical version replayed the animation'

# With no newer version (e.g. the current version is now stable), hide the notice.
$script:httpManifestVersion = '1.5.16'
$script:rdcNoticeNextCheck = (Get-Date).AddSeconds(-1)
Complete-PollCycle
Assert (-not $script:rdcNoticeActive) 'Notice was not hidden for current version'
Assert ($script:rdcNoticeControl.EndCount -eq 1) 'Notice renderer did not reset'
Assert ($bottom.ColumnStyles[1].Width -eq 440) 'Footer width was not restored'
Assert ($hint.Text -eq 'Original footer text') 'Footer informational text changed'

Write-Output 'PASS: later stable version updates visible button, same version remains stable, current version hides notice'
