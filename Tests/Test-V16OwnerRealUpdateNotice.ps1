# G107: Owner GUI update button appears ONLY for a real newer published
# stable manifest. Isolated mocked GitHub responses, no network/Remote/install.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'Source\remote-window.ps1'),[Text.Encoding]::UTF8)
$owner=[IO.File]::ReadAllText((Join-Path $root 'Source\rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
$notice=[IO.File]::ReadAllText((Join-Path $root 'Source\update-notice.ps1'),[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$yes,[string]$label){
 if($yes){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$astErrors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Source\update-notice.ps1'),[ref]$tokens,[ref]$astErrors)
Check ($astErrors.Count -eq 0) 'real notice module parses'
foreach($name in @('Get-RdcAvailableVersionFromManifest','Update-RdcUpdateNoticePolling','Show-RdcUpdateNotice','Hide-RdcUpdateNotice')){
 $n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq $name},$true)
 if(-not $n){throw ('MISSING_PRODUCT_NOTICE_FUNCTION '+$name)}
 . ([scriptblock]::Create($n.Extent.Text))
}
Check ($source.Contains('$script:ownerUpdateDemoMode=[bool]($OwnerGui -and -not $SelfTest)') -and
 -not $source.Contains("Start-RdcUpdateNoticePreview '1.6.0 RC2'") -and
 $owner.Contains('if($script:enableUpdateNotice){Update-RdcUpdateNoticePolling}')) 'Owner starts idle; no fake RC2; Host-bound GUI polls passive stable manifest'
Check ($notice.Contains('if ($SelfTest -or ($Preview -and -not $OwnerGui) -or') -and
 $notice.Contains('https://api.github.com/repos/1rubass1/RDC-Relay/commits/stable') -and
 $notice.Contains('/Source/update-manifest.json')) 'Owner only reads official stable commit and pinned release manifest'
Check ($notice.Contains('if ($SelfTest -or $Preview -or $script:ownerUpdateDemoMode -or') -and
 $notice.Contains('public bool ButtonReady { get { return !visualPreviewOnly') -and
 $notice.Contains('if($OwnerGui){')) 'Owner update action disabled, while check remains read-only'
function New-FakeTimer {
 $t=[pscustomobject]@{StartCount=0;StopCount=0}
 $t|Add-Member ScriptMethod Start {$this.StartCount++}
 $t|Add-Member ScriptMethod Stop {$this.StopCount++}
 return $t
}
$OwnerGui=$true
$SelfTest=$false;$Preview=$true
$script:ownerUpdateDemoMode=$true
$script:enableUpdateNotice=$true
$appVersion='1.6.0 RC1'
$script:rdcNoticeActive=$false
$script:rdcNoticeInstalling=$false
$script:rdcNoticeAnimationTimer=New-FakeTimer
$script:rdcNoticeControl=[pscustomobject]@{
 OfferedVersion='';BeginCount=0;EndCount=0;TabStop=$false;AccessibleName=''
}
$script:rdcNoticeControl|Add-Member ScriptMethod Begin {
 param([string]$installed,[string]$available,[string]$text)
 $this.OfferedVersion=$available
 $this.BeginCount++
}
$script:rdcNoticeControl|Add-Member ScriptMethod End {
 $this.OfferedVersion=''
 $this.EndCount++
}
$hint=[pscustomobject]@{Text=''}
$tip=[pscustomobject]@{TooltipText=''}
$tip|Add-Member ScriptMethod SetToolTip {param($control,$value) $this.TooltipText=[string]$value}
$column=[pscustomobject]@{Width=115}
$bottom=[pscustomobject]@{ColumnStyles=@($null,$column)}
$bottom|Add-Member ScriptMethod PerformLayout {}
$nl=[Environment]::NewLine
function Add-Log {param([string]$message)throw ('G107_UNEXPECTED_POLL_FAILURE '+$message)}
$script:mockVersion='1.5.18'
$script:mockFiles=$true
$script:mockCalls=New-Object System.Collections.Generic.List[string]
$script:rdcNoticeHttp=[pscustomobject]@{}
$script:rdcNoticeHttp|Add-Member ScriptMethod GetStringAsync {
 param([string]$url)
 [void]$script:mockCalls.Add($url)
 $raw=if($url -like 'https://api.github.com/repos/1rubass1/RDC-Relay/commits/stable'){
  '{"sha":"'+('b'*40)+'"}'
 }else{
  if($script:mockFiles){
   '{"version":"'+$script:mockVersion+'","files":[{"name":"remote-window.ps1","sha256":"TEST"},{"name":"update.ps1","sha256":"TEST"}]}'
  }else{
   '{"version":"'+$script:mockVersion+'"}'
  }
 }
 return [Threading.Tasks.Task]::FromResult([string]$raw)
}
$script:rdcNoticeCheckTask=$null
$script:rdcNoticeCheckPhase=''
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
function Complete-Poll {
 Update-RdcUpdateNoticePolling
 Update-RdcUpdateNoticePolling
 Update-RdcUpdateNoticePolling
 Check ($null -eq $script:rdcNoticeCheckTask -and $script:rdcNoticeCheckPhase -ceq '') 'one asynchronous three-step stable check completes'
}
Complete-Poll
Check (-not $script:rdcNoticeActive -and $script:rdcNoticeControl.BeginCount -eq 0 -and
 $column.Width -eq 115) 'actual published stable 1.5.18 is older: Owner button NEVER appears'
Check ($script:mockCalls.Count -eq 2 -and
 $script:mockCalls[1] -like '*bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/Source/update-manifest.json') 'manifest request pinned to SHA returned by real stable commit endpoint'
# A private future candidate RC2 cannot be fabricated: a stable manifest
# lacking required stable-install payload is not a real release.
$script:mockVersion='1.6.0'
$script:mockFiles=$false
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
Complete-Poll
Check (-not $script:rdcNoticeActive -and $script:rdcNoticeControl.BeginCount -eq 0) 'numeric version alone without real stable payload does not trigger a fake offer'
$script:mockFiles=$true
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
Complete-Poll
Check ($script:rdcNoticeActive -and
 $script:rdcNoticeControl.OfferedVersion -ceq '1.6.0' -and
 $script:rdcNoticeControl.BeginCount -eq 1 -and
 $script:rdcNoticeAnimationTimer.StartCount -eq 1) 'verified stable 1.6.0 is newer than 1.6.0 RC1 and animates once'
Check ($script:rdcNoticeControl.AccessibleName.Contains('v1.6.0') -and
 $script:rdcNoticeControl.AccessibleName.Contains('RC1')) 'real stable notice names true version and blocked candidate install'
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
Complete-Poll
Check ($script:rdcNoticeControl.BeginCount -eq 1 -and
 $script:rdcNoticeAnimationTimer.StartCount -eq 1) 'same stable release never replays the animation'
$script:mockVersion='1.6.1'
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
Complete-Poll
Check ($script:rdcNoticeControl.OfferedVersion -ceq '1.6.1' -and
 $script:rdcNoticeControl.BeginCount -eq 2) 'genuinely newer stable release replaces a stale offer'
$script:mockVersion='1.5.19'
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
Complete-Poll
Check (-not $script:rdcNoticeActive -and $script:rdcNoticeControl.EndCount -eq 1 -and
 $column.Width -eq 115) 'later stable manifest older than RC1 hides previous offer and restores idle'
$Preview=$true;$OwnerGui=$false
$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
$before=$script:mockCalls.Count
Update-RdcUpdateNoticePolling
Check ($before -eq $script:mockCalls.Count -and -not $script:rdcNoticeCheckTask) 'legacy -Preview mode still never calls the network'
$OwnerGui=$true;$script:enableUpdateNotice=$false
Update-RdcUpdateNoticePolling
Check ($before -eq $script:mockCalls.Count) 'feature disabled means no new stable check'
$script:enableUpdateNotice=$true
$appVersion='1.6.0 RC1'
Check (-not (Get-RdcAvailableVersionFromManifest '{"version":"1.5.18","files":[{"name":"remote-window.ps1"},{"name":"update.ps1"}]}')) 'published 1.5.18 not an update'
Check ((Get-RdcAvailableVersionFromManifest '{"version":"1.6.0","files":[{"name":"remote-window.ps1"},{"name":"update.ps1"}]}') -ceq '1.6.0') 'published final 1.6.0 outranks RC1'
$appVersion='1.6.0'
$OwnerGui=$false
Check (-not (Get-RdcAvailableVersionFromManifest '{"version":"1.6.0"}') -and
 (Get-RdcAvailableVersionFromManifest '{"version":"1.6.1"}') -ceq '1.6.1') 'legacy stable-release version comparison remains strict greater-than'
Write-Output ('RC1_OWNER_REAL_UPDATE_NOTICE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0