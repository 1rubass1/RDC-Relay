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
Check ($hostCode.Contains("$"+'mode='+ "'-Authorize'") -and
 $hostCode.Contains('$quotaAutoTried.ContainsKey') -and
 $hostCode.Contains('$quotaNextPollUtc=[DateTime]::UtcNow.AddMinutes(30)') -and
 $hostCode.Contains('$quotaTimer.Interval=15000')) 'original owned-account auto OAuth and 30m polling schedule restored'
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
 $hostState=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaHostAuto-'+[Guid]::NewGuid().ToString('N'))
 $oldLocal=$env:LOCALAPPDATA
 $env:LOCALAPPDATA=$hostState
 $quotaDisplayPath=Join-Path $hostState 'RDCRelayOwnerPilot\quota-display.opt-in'
 $owner=[pscustomobject]@{ActiveManagedAccount='test@example.org'}
 $quotaPollProcess=$null;$quotaAutoTried=@{};$quotaLastAccount=''
 $quotaNextPollUtc=[DateTime]::MinValue
 $quotaScript='Z:\fake\quota-client.ps1'
 $script:mockCalls=0;$script:mockMode=''
 function Start-Process {
  [CmdletBinding()]
  param([string]$FilePath,[string[]]$ArgumentList,[string]$WindowStyle,[switch]$PassThru)
  $script:mockCalls++
  $script:mockMode=if($ArgumentList -contains '-Authorize'){'-Authorize'}else{'-Poll'}
  $fake=[pscustomobject]@{HasExited=$true}
  Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
  return $fake
 }
 try {
  . $tick
  Check ($script:mockCalls -eq 1 -and $script:mockMode -ceq '-Authorize') 'default ON: original Host initiates OAuth when no token'
  . $tick
  Check ($script:mockCalls -eq 1) '30m schedule prevents repeated authorization'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $false
  . $tick
  Check ($script:mockCalls -eq 1 -and $quotaNextPollUtc -eq [DateTime]::MinValue -and
   $quotaAutoTried.Count -eq 0) 'explicit OFF stops scheduling and re-arms future consent'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $true
  . $tick
  Check ($script:mockCalls -eq 2 -and $script:mockMode -ceq '-Authorize') 'recheck resumes original auto authorization if still missing'
  $pilot=Join-Path $hostState 'RDCRelayOwnerPilot'
  [IO.Directory]::CreateDirectory($pilot)|Out-Null
  [IO.File]::WriteAllText((Join-Path $pilot 'quota-oauth-user.dpapi'),'synthetic-credential-present')
  [IO.File]::WriteAllText((Join-Path $pilot 'remote-usage-cache.json'),
    '{"source":"official-remote-who-am-i","accountEmail":"other@example.org"}')
  $owner.ActiveManagedAccount='other@example.org'
  . $tick
  Check ($script:mockCalls -eq 3 -and $script:mockMode -ceq '-Poll') 'existing vault and matching account cache use ordinary poll'
 }finally {
  Remove-Item function:Start-Process -ErrorAction SilentlyContinue
  $env:LOCALAPPDATA=$oldLocal
  if([IO.Directory]::Exists($hostState)){[IO.Directory]::Delete($hostState,$true)}
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
 try{
  $quotaAuthItem.Checked=Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath
  Check ($quotaAuthItem.Checked) 'new GUI first shows checkbox checked'
  $quotaAuthItem.Add_Click($click)
  $quotaAuthItem.PerformClick()
  Check (-not $quotaAuthItem.Checked -and
   -not (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath) -and
   $quotaLabel.Text.EndsWith('--%')) 'click OFF persists opt-out, hides old percent'
  $quotaAuthItem.PerformClick()
  Check ($quotaAuthItem.Checked -and
   (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath)) 'click ON removes opt-out; no duplicate GUI OAuth launcher'
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