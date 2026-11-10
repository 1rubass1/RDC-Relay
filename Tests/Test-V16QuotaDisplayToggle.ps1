# G101: persisted opt-in and no automatic OAuth browser, using disposable local state only.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'
$files=@('rc1-owner-gui.ps1','rc1-tray-host.ps1','rc1-quota-client.ps1','remote-window.ps1')
$code=@{}
$ast=@{}
$pass=0;$fail=0
function Check([bool]$condition,[string]$message){
 if($condition){$script:pass++;Write-Output ('PASS '+$message)}
 else{$script:fail++;Write-Output ('FAIL '+$message)}
}
foreach($name in $files){
 $path=Join-Path $src $name
 $code[$name]=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
 $tokens=$null;$errors=$null
 $ast[$name]=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) ('parse '+$name)
}
# Extract the actual GUI writer and reader. Never use the production path.
foreach($name in @('Test-Rc1QuotaDisplayEnabled','Set-Rc1QuotaDisplayEnabled')){
 $n=$ast['rc1-owner-gui.ps1'].Find({param($x)
  $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq $name
 },$true)
 if(-not $n){throw ('MISSING_PRODUCTION_FUNCTION '+$name)}
 . ([scriptblock]::Create($n.Extent.Text))
}
$state=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaPreference-'+[Guid]::NewGuid().ToString('N'))
$path=Join-Path $state 'quota-display.opt-in'
try{
 Check (-not (Test-Rc1QuotaDisplayEnabled $path)) 'absent opt-in defaults to disabled'
 Set-Rc1QuotaDisplayEnabled $path $true
 Check ((Test-Rc1QuotaDisplayEnabled $path) -and
  [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq 'enabled-v1') 'checked writes exact persistent user opt-in marker'
 Set-Rc1QuotaDisplayEnabled $path $true
 Check ((Test-Rc1QuotaDisplayEnabled $path) -and
  @([IO.Directory]::GetFiles($state,'*.tmp')).Count -eq 0 -and
  @([IO.Directory]::GetFiles($state,'*.bak')).Count -eq 0) 'second check atomically replaces existing marker without leftovers'
 [IO.File]::WriteAllText($path,'something-else',[Text.Encoding]::UTF8)
 Check (-not (Test-Rc1QuotaDisplayEnabled $path)) 'invalid marker is fail closed'
 Set-Rc1QuotaDisplayEnabled $path $true
 Check (Test-Rc1QuotaDisplayEnabled $path) 'invalid marker can be safely replaced with valid opt-in'
 Set-Rc1QuotaDisplayEnabled $path $false
 Check (-not (Test-Rc1QuotaDisplayEnabled $path) -and -not [IO.File]::Exists($path)) 'unchecking deletes marker and disables background polling'
 Set-Rc1QuotaDisplayEnabled $path $false
 Check (-not (Test-Rc1QuotaDisplayEnabled $path)) 'repeated uncheck is idempotent'
 $menu=New-Object Windows.Forms.ToolStripMenuItem('Quota display')
 $menu.CheckOnClick=$true
 try{
  $menu.PerformClick()
  Check ($menu.Checked -and $menu.Text -ceq 'Quota display') 'standard ToolStripMenuItem checks on click'
  $menu.PerformClick()
  Check (-not $menu.Checked) 'standard ToolStripMenuItem unchecks on second click'
 }finally{$menu.Dispose()}
 # Compare each independent read-only process implementation on the SAME
 # synthetic file; no production credentials, user settings or browser access.
 Set-Rc1QuotaDisplayEnabled $path $true
 foreach($file in @('rc1-tray-host.ps1','rc1-quota-client.ps1')){
  $n=$ast[$file].Find({param($x)
   $x -is [Management.Automation.Language.FunctionDefinitionAst] -and
   $x.Name -ceq 'Test-Rc1QuotaDisplayEnabled'
  },$true)
  if(-not $n){throw ('MISSING_PROCESS_READER '+$file)}
  . ([scriptblock]::Create($n.Extent.Text))
  Check (Test-Rc1QuotaDisplayEnabled $path) ($file+' reads persisted enabled state')
  Set-Rc1QuotaDisplayEnabled $path $false
  Check (-not (Test-Rc1QuotaDisplayEnabled $path)) ($file+' treats opt-out as disabled')
  Set-Rc1QuotaDisplayEnabled $path $true
 }
}finally{
 if([IO.File]::Exists($path)){[IO.File]::Delete($path)}
 if([IO.Directory]::Exists($state)){[IO.Directory]::Delete($state,$true)}
}
$window=$code['remote-window.ps1']
$gui=$code['rc1-owner-gui.ps1']
$hostCode=$code['rc1-tray-host.ps1']
$client=$code['rc1-quota-client.ps1']
Check ($window.Contains("$"+'quotaAuthItem.Text=') -and
 $window.Contains('$quotaAuthItem.CheckOnClick=[bool]$OwnerGui') -and
 $window.Contains('Set-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath $enabled')) 'Account menu is a checkable persistent display setting'
Check ($window.Contains('if([IO.File]::Exists($vault)){return}') -and
 $window.Contains("'-Authorize'") -and
 $window.Contains('if(-not $enabled){return}')) 'explicit checked action opens OAuth only when vault is missing'
Check ($gui.Contains('$quotaAuthItem.Checked=[bool](Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath)') -and
 $gui.Contains('$quotaDisplayEnabled=Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath') -and
 $gui.Contains('quotaDisplayEnabled') -and
 $gui.Contains('ownerLastQuotaText')) 'GUI restores checkmark and suppresses off-state cached percent'
Check ($hostCode.Contains('if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath))') -and
 $hostCode.Contains("$"+'quotaPollProcess=Start-Process') -and
 $hostCode.Contains("'-Poll'") -and
 -not $hostCode.Contains("'-Authorize'")) 'Tray Host timer refuses disabled mode, never opens browser'
Check ($client.Contains('if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){Stop-Quota ') -and
 $client.Contains('if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){return $false}') -and
 $client.Contains('if(-not (Test-Rc1QuotaDisplayEnabled $quotaDisplayPath)){throw ')) 'OAuth helper blocks off-state start, browser and cache publication'
Check ($window.Contains("$"+'quotaLabel.Text=') -and
 $client.Contains("name='who_am_i'")) 'off-state shows honest unknown, read-only MCP scope unchanged'
# Execute the exact production Tray Host tick with a fake owner and an
# intercepted process-launch function. Real Remote and OAuth never start.
$tickNodes=@($ast['rc1-tray-host.ps1'].FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text -match 'Test-Rc1QuotaDisplayEnabled'
},$true))
Check ($tickNodes.Count -eq 1) 'exactly one real Host quota timer handler found'
if($tickNodes.Count -eq 1){
 $tickWrapper=[scriptblock]::Create($tickNodes[0].Extent.Text)
 $tick=& $tickWrapper
 $hostTestState=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaHostTest-'+[Guid]::NewGuid().ToString('N'))
 $quotaDisplayPath=Join-Path $hostTestState 'quota-display.opt-in'
 $owner=[pscustomobject]@{ActiveManagedAccount='test@example.org'}
 $quotaPollProcess=$null
 $quotaLastAccount=''
 $quotaNextPollUtc=[DateTime]::MinValue
 $quotaScript='Z:\does-not-exist\synthetic-quota.ps1'
 $script:quotaTestLaunches=0
 $script:quotaTestArguments=@()
 function Start-Process {
  [CmdletBinding()]
  param([string]$FilePath,[string[]]$ArgumentList,[string]$WindowStyle,[switch]$PassThru)
  $script:quotaTestLaunches++
  $script:quotaTestArguments=$ArgumentList
  $fake=[pscustomobject]@{HasExited=$true}
  Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value {}
  return $fake
 }
 try{
  . $tick
  Check ($script:quotaTestLaunches -eq 0) 'no marker: Host timer cannot launch any quota client'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $true
  . $tick
  Check ($script:quotaTestLaunches -eq 1 -and
   $script:quotaTestArguments -contains '-Poll' -and
   $script:quotaTestArguments -cnotcontains '-Authorize') 'checked: one read-only poll launched, never an OAuth browser'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $false
  . $tick
  Check ($script:quotaTestLaunches -eq 1 -and
   $quotaNextPollUtc -eq [DateTime]::MinValue) 'unchecked: Host resets schedule and launches no new polls'
  Set-Rc1QuotaDisplayEnabled $quotaDisplayPath $true
  . $tick
  Check ($script:quotaTestLaunches -eq 2) 'rechecked: Host resumes on the next timer tick'
 }finally{
  Remove-Item function:Start-Process -ErrorAction SilentlyContinue
  if([IO.Directory]::Exists($hostTestState)){[IO.Directory]::Delete($hostTestState,$true)}
 }
}
# Exercise the actual Account-menu click handler with disposable WinForms
# controls and a mocked process launcher; browser and OAuth never run.
$clickNodes=@($ast['remote-window.ps1'].FindAll({param($n)
 $n -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
 $n.Extent.Text -match 'Set-Rc1QuotaDisplayEnabled \$script:ownerQuotaEnabledPath \$enabled'
},$true))
Check ($clickNodes.Count -eq 1) 'exactly one production Account-menu quota click handler found'
if($clickNodes.Count -eq 1){
 $clickWrapper=[scriptblock]::Create($clickNodes[0].Extent.Text)
 $click=& $clickWrapper
 $uiState=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaMenuTest-'+[Guid]::NewGuid().ToString('N'))
 $root=Join-Path $uiState 'source'
 $script:ownerQuotaEnabledPath=Join-Path $uiState 'quota-display.opt-in'
 $script:ownerManagedMode=$true
 $OwnerGui=$true
 $script:ownerQuotaNextCheckUtc=[DateTime]::MinValue
 $script:ownerLastQuotaText=''
 $oldLocal=$env:LOCALAPPDATA
 $env:LOCALAPPDATA=$uiState
 $quotaAuthItem=New-Object Windows.Forms.ToolStripMenuItem('Quota display')
 $quotaAuthItem.CheckOnClick=$true
 $quotaLabel=New-Object Windows.Forms.Label
 $script:quotaTestLaunches=0
 $script:quotaTestArguments=@()
 function Start-Process {
  [CmdletBinding()]
  param([string]$FilePath,[string[]]$ArgumentList,[string]$WindowStyle)
  $script:quotaTestLaunches++
  $script:quotaTestArguments=$ArgumentList
 }
 try {
  [void][IO.Directory]::CreateDirectory($root)
  [IO.File]::WriteAllText((Join-Path $root 'rc1-quota-client.ps1'),'synthetic no-op test file')
  $quotaAuthItem.Add_Click($click)
  $quotaAuthItem.PerformClick()
  Check ($quotaAuthItem.Checked -and
   (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath) -and
   $script:quotaTestLaunches -eq 1 -and
   $script:quotaTestArguments -contains '-Authorize') 'actual check click persists and requests OAuth only when vault missing'
  $quotaAuthItem.PerformClick()
  Check (-not $quotaAuthItem.Checked -and
   -not (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath) -and
   $script:quotaTestLaunches -eq 1 -and
   $quotaLabel.Text.EndsWith('--%')) 'actual uncheck click disables updates and shows unknown without browser'
  [void][IO.Directory]::CreateDirectory((Join-Path $uiState 'RDCRelayOwnerPilot'))
  [IO.File]::WriteAllText((Join-Path $uiState 'RDCRelayOwnerPilot\quota-oauth-user.dpapi'),'synthetic vault presence')
  $quotaAuthItem.PerformClick()
  Check ($quotaAuthItem.Checked -and
   (Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath) -and
   $script:quotaTestLaunches -eq 1) 'actual check click with existing vault reuses token; no duplicate OAuth browser'
 }finally {
  Remove-Item function:Start-Process -ErrorAction SilentlyContinue
  $quotaAuthItem.Dispose();$quotaLabel.Dispose()
  $env:LOCALAPPDATA=$oldLocal
  if([IO.Directory]::Exists($uiState)){[IO.Directory]::Delete($uiState,$true)}
 }
}
# Invoke only the opt-out branch of the real standalone quota client in a
# process with a disposable LOCALAPPDATA; no genuine tokens or network calls.
$isolatedLocal=Join-Path ([IO.Path]::GetTempPath()) ('RdcQuotaClientOff-'+[Guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
try {
 $env:LOCALAPPDATA=$isolatedLocal
 $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $result=@(& $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $src 'rc1-quota-client.ps1') -Poll)
 Check ($LASTEXITCODE -eq 0 -and $result -contains 'RC1_QUOTA_DISABLED') 'real quota client returns DISABLED before credential/network access when unchecked'
}finally{
 $env:LOCALAPPDATA=$oldLocal
 if([IO.Directory]::Exists($isolatedLocal)){[IO.Directory]::Delete($isolatedLocal,$true)}
}
Write-Output ('RC1_QUOTA_DISPLAY_TOGGLE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0