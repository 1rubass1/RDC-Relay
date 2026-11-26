# G102: quota display defaults ON, explicit opt-out, original Host auto OAuth.
# Disposable local state, synthetic accounts; never touch real Remote or credentials.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'
$files=@('rc1-owner-gui.ps1','rc1-tray-host.ps1','rc1-quota-client.ps1','remote-window.ps1')
$code=@{};$ast=@{};$pass=0;$fail=0
function Check([bool]$yes,[string]$why){
 if($yes){$script:pass++;Write-Output ('PASS '+$why)}
 else{$script:fail++;Write-Output ('FAIL '+$why)}
}
foreach($file in $files){
 $path=Join-Path $src $file
 $code[$file]=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
 $tokens=$null;$errors=$null
 $ast[$file]=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) ('parses '+$file)
}
foreach($name in @('Test-Rc1QuotaDisplayEnabled','Set-Rc1QuotaDisplayEnabled')){
 $n=$ast['rc1-owner-gui.ps1'].Find({param($x)
  $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq $name
 },$true)
 if(-not $n){throw ('MISSING_PRODUCTION_FUNCTION '+$name)}
 . ([scriptblock]::Create($n.Extent.Text))
}
$state=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaDefaultOn-'+[Guid]::NewGuid().ToString('N'))
$path=Join-Path $state 'quota-display.opt-in'
try {
 Check (Test-Rc1QuotaDisplayEnabled $path) 'fresh installation defaults checked ON with no preference file'
 Set-Rc1QuotaDisplayEnabled $path $true
 Check ((Test-Rc1QuotaDisplayEnabled $path) -and -not [IO.File]::Exists($path)) 'explicit ON needs no disk file'
 Set-Rc1QuotaDisplayEnabled $path $false
 Check (-not (Test-Rc1QuotaDisplayEnabled $path) -and
  [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq 'disabled-v1') 'unchecked writes explicit OFF marker'
 Set-Rc1QuotaDisplayEnabled $path $false
 Check (-not (Test-Rc1QuotaDisplayEnabled $path) -and
  @([IO.Directory]::GetFiles($state,'*.tmp')).Count -eq 0 -and
  @([IO.Directory]::GetFiles($state,'*.bak')).Count -eq 0) 'repeated OFF atomically replaces marker and cleans staging'
 Set-Rc1QuotaDisplayEnabled $path $true
 Check ((Test-Rc1QuotaDisplayEnabled $path) -and
  -not [IO.File]::Exists($path)) 'checked ON removes explicit opt-out marker'
 [IO.File]::WriteAllText($path,'enabled-v1',(New-Object Text.UTF8Encoding($false)))
 Check (Test-Rc1QuotaDisplayEnabled $path) 'G101 enabled-v1 marker migrates as ON'
 [IO.File]::WriteAllText($path,'corrupted',[Text.Encoding]::UTF8)
 Check (-not (Test-Rc1QuotaDisplayEnabled $path)) 'malformed preference safely disables quota'
 Set-Rc1QuotaDisplayEnabled $path $true
 Check ((Test-Rc1QuotaDisplayEnabled $path) -and -not [IO.File]::Exists($path)) 'ON repairs malformed old marker'
 foreach($file in @('rc1-tray-host.ps1','rc1-quota-client.ps1')){
  $n=$ast[$file].Find({param($x)
   $x -is [Management.Automation.Language.FunctionDefinitionAst] -and
   $x.Name -ceq 'Test-Rc1QuotaDisplayEnabled'
  },$true)
  if(-not $n){throw ('MISSING_PROCESS_READER '+$file)}
  . ([scriptblock]::Create($n.Extent.Text))
  Check (Test-Rc1QuotaDisplayEnabled $path) ($file+' also defaults ON')
  Set-Rc1QuotaDisplayEnabled $path $false
  Check (-not (Test-Rc1QuotaDisplayEnabled $path)) ($file+' respects explicit opt-out')
  Set-Rc1QuotaDisplayEnabled $path $true
 }
}finally{
 if([IO.File]::Exists($path)){[IO.File]::Delete($path)}
 if([IO.Directory]::Exists($state)){[IO.Directory]::Delete($state,$true)}
}
$gui=$code['rc1-owner-gui.ps1'];$hostCode=$code['rc1-tray-host.ps1']
$client=$code['rc1-quota-client.ps1'];$window=$code['remote-window.ps1']
Check ($window.Contains('$quotaAuthItem.CheckOnClick=[bool]$OwnerGui') -and
 $window.Contains('Set-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath $enabled')) 'Account menu persists standard checkbox'
Check ($gui.Contains('$quotaAuthItem.Checked=[bool](Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath)') -and
 $gui.Contains('$quotaDisplayEnabled=Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath')) 'GUI restores default ON and disables cached display when unchecked'
Check ($hostCode.Contains('$script:quotaPolicy.Decide') -and
 $hostCode.Contains('$script:quotaPollProcess=Start-Process') -and
 $hostCode.Contains('$quotaTimer.Interval=15000')) 'one persistent Host scheduler owns authorization and polling'
Check ($client.Contains('if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){return $false}') -and
 $client.Contains('Stop-Quota '+"'DISABLED'") -and
 $client.Contains("name='who_am_i'")) 'quota child respects OFF, otherwise original who_am_i remains'
# Extract the production Host timer itself and intercept its process launcher.
$tickNodes=@($ast['rc1-tray-host.ps1'].FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text -match 'Test-Rc1QuotaDisplayEnabled'
},$true))
Check ($tickNodes.Count -eq 1) 'one real Host quota timer handler'
if($tickNodes.Count -eq 1){
 $tick=& ([scriptblock]::Create($tickNodes[0].Extent.Text))
 # Compile the exact production scheduler/cache classes, without Host or Remote.
 $runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
 $start=$runtime.IndexOf(' public static class RdcOwnerQuotaIdentity {',[StringComparison]::Ordinal)
 $end=$runtime.IndexOf('// Hidden top-level',$start,[StringComparison]::Ordinal)
 if($start -lt 0 -or $end -le $start){throw 'MISSING_QUOTA_POLICY_CLASSES'}
 Add-Type -TypeDefinition ('using System;using System.IO;using System.Text;using System.Collections.Generic;'+$runtime.Substring($start,$end-$start)) -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
 $hostState=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaHostAuto-'+[Guid]::NewGuid().ToString('N'))
 $quotaDisplayPath=Join-Path $hostState 'quota-display.opt-in'
 $quotaCache=Join-Path $hostState 'remote-usage-cache.json'
 $quotaVault=Join-Path $hostState 'quota-oauth-user.dpapi'
 $owner=[pscustomobject]@{ActiveManagedAccount='test@example.org';QuotaManagedAccount='test@example.org';QuotaGuiOpenGeneration=1}
 $script:quotaPollProcess=$null
 $script:quotaPolicy=New-Object RdcOwnerQuotaRefreshPolicy
 $script:quotaClock=[pscustomobject]@{Elapsed=[pscustomobject]@{TotalSeconds=0}}
 $script:quotaAttemptAccount='';$script:quotaAttemptObserved=[DateTime]::MinValue
 $quotaScript='Z:\fake\quota-client.ps1'
 $script:mockCalls=0;$script:mockMode=''
 function Start-Process {
  [CmdletBinding()]
  param([string]$FilePath,[string[]]$ArgumentList,[string]$WindowStyle,[switch]$PassThru)
  $script:mockCalls++
  $script:mockMode=if($ArgumentList -contains '-Authorize'){'-Authorize'}else{'-Poll'}
  $fake=[pscustomobject]@{HasExited=$false}
  Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
  return $fake
 }
 function Write-SyntheticQuota([DateTime]$observed){
  $json=@{source='official-remote-who-am-i';accountEmail='test@example.org';remainingPercent=73;observedAtUtc=$observed.ToString('yyyy-MM-ddTHH:mm:ssZ')}|ConvertTo-Json -Compress
  [IO.File]::WriteAllText($quotaCache,$json,(New-Object Text.UTF8Encoding($false)))
 }
 try {
  [IO.Directory]::CreateDirectory($hostState)|Out-Null
  & $tick
  Check ($script:mockCalls -eq 1 -and $script:mockMode -ceq '-Authorize') 'default ON retains initial Ready consent'
  $script:quotaClock.Elapsed.TotalSeconds=15
  & $tick
  Check ($script:mockCalls -eq 1) 'separate timer invocation does not duplicate active worker'
  [IO.File]::WriteAllText($quotaVault,'synthetic-presence-only')
  Write-SyntheticQuota ([DateTime]::UtcNow)
  $script:quotaPollProcess.HasExited=$true
  & $tick
  Check ($script:mockCalls -eq 1 -and -not $script:quotaPollProcess) 'finished worker cleared and successful cache observed'
  Write-SyntheticQuota ([DateTime]::UtcNow.AddMinutes(-10))
  $owner.ActiveManagedAccount=''
  $owner.QuotaGuiOpenGeneration=2
  $script:quotaClock.Elapsed.TotalSeconds=299
  & $tick
  Check ($script:mockCalls -eq 1) 'GUI reopen cannot bypass cooldown'
  $script:quotaClock.Elapsed.TotalSeconds=300
  & $tick
  Check ($script:mockCalls -eq 2 -and $script:mockMode -ceq '-Poll') 'quiet owned identity refreshes on reopen without browser'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $false
  $script:quotaClock.Elapsed.TotalSeconds=315
  $script:quotaPollProcess.HasExited=$true
  & $tick
  Check ($script:mockCalls -eq 2) 'opt out prevents new work'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $true
  $script:quotaClock.Elapsed.TotalSeconds=316
  & $tick
  Check ($script:mockCalls -eq 2) 'opt in cannot bypass failure backoff'
  $script:quotaClock.Elapsed.TotalSeconds=1215
  & $tick
  Check ($script:mockCalls -eq 3 -and $script:mockMode -ceq '-Poll') 'ordinary poll resumes after backoff with existing grant'
 }finally {
  Remove-Item function:Start-Process -ErrorAction SilentlyContinue
  foreach($file in @($quotaCache,$quotaVault,$quotaDisplayPath)){if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
  if([IO.Directory]::Exists($hostState)){[IO.Directory]::Delete($hostState,$false)}
 }
}
# Exercise the actual GUI click handler. No browser double-spawn: the Host
# owns both the initial auto-consent and the ordinary periodic poll.
$clickNodes=@($ast['remote-window.ps1'].FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text -match 'Set-Rc1QuotaDisplayEnabled \$script:ownerQuotaEnabledPath \$enabled'
},$true))
Check ($clickNodes.Count -eq 1) 'one real Account-menu checkbox handler'
if($clickNodes.Count -eq 1){
 $click=& ([scriptblock]::Create($clickNodes[0].Extent.Text))
 $uiRoot=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaGuiAuto-'+[Guid]::NewGuid().ToString('N'))
 $script:ownerQuotaEnabledPath=Join-Path $uiRoot 'quota-display.opt-in'
 $script:ownerManagedMode=$true;$OwnerGui=$true
 $script:ownerQuotaNextCheckUtc=[DateTime]::MinValue;$script:ownerLastQuotaText=''
 $quotaAuthItem=New-Object Windows.Forms.ToolStripMenuItem('Quota display')
 $quotaAuthItem.CheckOnClick=$true
 $quotaLabel=New-Object Windows.Forms.Label
 $localizer=$ast['remote-window.ps1'].Find({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-RdcOwnerDialogText'
 },$true)
 if(-not $localizer){throw 'MISSING_QUOTA_LOCALIZER'}
 . ([scriptblock]::Create($localizer.Extent.Text))
 $script:testQuotaCatalog=$null
 function Get-RdcOwnerUiText([string]$key,[string]$fallback){
  $property=$script:testQuotaCatalog.strings.PSObject.Properties[$key]
  if($property){return [string]$property.Value}
  return $fallback
 }
 try{
  $quotaAuthItem.Checked=Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath
  Check ($quotaAuthItem.Checked) 'new GUI first shows checkbox checked'
  $quotaAuthItem.Add_Click($click)
  $script:testQuotaCatalog=[IO.File]::ReadAllText((Join-Path $src 'lang\en-US.json'))|ConvertFrom-Json
  $quotaAuthItem.PerformClick()
  Check (-not $quotaAuthItem.Checked -and
   -not (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath) -and
   $quotaLabel.Text -ceq 'Remaining calls: --%') 'English click OFF persists opt-out without Russian flash'
  $quotaAuthItem.PerformClick()
  Check ($quotaAuthItem.Checked -and
   (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath) -and $quotaLabel.Text -ceq 'Remaining calls: --%') 'English click ON preserves locale and removes opt-out'
  $script:testQuotaCatalog=[IO.File]::ReadAllText((Join-Path $src 'lang\ru-RU.json'))|ConvertFrom-Json
  $quotaAuthItem.PerformClick()
  Check (-not $quotaAuthItem.Checked -and $quotaLabel.Text -ceq [string]$script:testQuotaCatalog.strings.'gui.quota.unknown') 'Russian click OFF preserves locale'
  $quotaAuthItem.PerformClick()
  Check ($quotaAuthItem.Checked -and $quotaLabel.Text -ceq [string]$script:testQuotaCatalog.strings.'gui.quota.unknown') 'Russian click ON preserves locale'
 }finally{
  $quotaAuthItem.Dispose();$quotaLabel.Dispose()
  if([IO.Directory]::Exists($uiRoot)){[IO.Directory]::Delete($uiRoot,$true)}
 }
}
# Real child disabled entrypoint with an isolated fake user profile, no network.
$isolated=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaOffClient-'+[Guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
try{
 $env:LOCALAPPDATA=$isolated
 $pref=Join-Path $isolated 'RDCRelayOwnerPilot\quota-display.opt-in'
 Set-Rc1QuotaDisplayEnabled $pref $false
 $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $output=@(& $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $src 'rc1-quota-client.ps1') -Poll)
 Check ($LASTEXITCODE -eq 0 -and $output -contains 'RC1_QUOTA_DISABLED') 'real CLI blocks requests before tokens when unchecked'
}finally{
 $env:LOCALAPPDATA=$oldLocal
 if([IO.Directory]::Exists($isolated)){[IO.Directory]::Delete($isolated,$true)}
}
Write-Output ('RC1_QUOTA_DISPLAY_TOGGLE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0