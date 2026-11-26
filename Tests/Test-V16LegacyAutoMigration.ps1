# Offline tests of the exact staged bridge helper. No network or product launch.
param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$src=Join-Path $Stage 'Source'
. (Join-Path $src 'legacy-migration.ps1')
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$m=[IO.File]::ReadAllText((Join-Path $src 'update-manifest.json'))|ConvertFrom-Json
Check (!$m.migration.ready -and !$m.migration.setupSha256 -and $m.files.Count -eq 11) 'offline manifest inactive and includes helper'
foreach($row in $m.files){Check ((Get-FileHash -LiteralPath (Join-Path $src $row.name)).Hash -ceq $row.sha256) ('flat payload hash '+$row.name)}
$m.migration.ready=$true;$m.migration.setupSha256='a'*64
$offer=Get-RdcMigrationOffer $m '1.5.18'
Check ($offer.Uri.AbsoluteUri -ceq 'https://github.com/Rubo-Facility/RDC-Relay/releases/download/v1.6.0/RDC.Relay.Setup.v1.6.0.exe') 'one fixed release asset'
$m.migration.asset='other.exe'
Check ($null -eq (Get-RdcMigrationOffer $m '1.5.18')) 'different asset rejected'
$m.migration.asset='RDC.Relay.Setup.v1.6.0.exe'
foreach($u in @('https://github.com/test','https://release-assets.githubusercontent.com/test','https://objects.githubusercontent.com/test')){
 Check (Test-RdcMigrationUri ([Uri]$u)) ('trusted redirect '+$u)
}
foreach($u in @('http://github.com/test','https://github.com.evil.test/test','https://evil.test/test','https://github.com:444/test','https://u@github.com/test')){
 Check (!(Test-RdcMigrationUri ([Uri]$u))) ('denied redirect '+$u)
}
# Tiny synthetic MZ byte sequence; it is NOT a real executable.
[byte[]]$bytes=77,90,1,2,3,4
$digest=Get-RdcMigrationDigest $bytes
Check (Test-RdcMigrationBytes $bytes $digest) 'exact fixture digest accepted'
Check (!(Test-RdcMigrationBytes $bytes ('A'*64))) 'wrong digest denied'
Check (!(Test-RdcMigrationBytes ([byte[]](1,2)) (Get-RdcMigrationDigest ([byte[]](1,2))))) 'non PE prefix denied'
$script:initializing=$false;$script:remoteOperation=$false;$script:autoReconnectAt=$null;$script:closeRequested=$false;$script:proc=$null
$script:remoteAbsent=$true
function Test-RdcMigrationNoRemote{return $script:remoteAbsent}
Check (Test-RdcMigrationIdle) 'idle and absence confirmed'
$script:proc=[pscustomobject]@{HasExited=$false}
Check (!(Test-RdcMigrationIdle)) 'owned active process blocks'
$script:proc=$null;$script:remoteAbsent=$false
Check (!(Test-RdcMigrationIdle)) 'other or unknown Remote blocks'
$script:remoteAbsent=$true;$script:autoReconnectAt=Get-Date
Check (!(Test-RdcMigrationIdle)) 'pending reconnect blocks'
$script:autoReconnectAt=$null
$script:launches=0;$script:messages=0;$script:closed=0
function Start-Process{param($FilePath,$ErrorAction);if($FilePath -cne $script:expectedPath){throw 'UNEXPECTED_FIXTURE'};$script:launches++}
function Show-RdcMigrationMessage([string]$message){$script:messages++}
$c=Save-RdcMigrationCandidate $bytes $digest
$script:expectedPath=$c.Path
try{
 Check ((Get-FileHash -LiteralPath $c.Path).Hash -ceq $digest) 'verified bytes staged exactly'
 Check ((Get-Content -LiteralPath $c.Path -Stream Zone.Identifier -Raw) -match '(?m)^ZoneId=3\r?$') 'download retains Internet-zone marker'
 $script:rdcMigrationHandoff=$c;$script:remoteAbsent=$false
 Complete-RdcMigrationHandoff
 Check ($script:launches -eq 0 -and $script:messages -eq 1 -and !$script:rdcMigrationHandoff) 'handoff rechecks remote absence'
 $script:remoteAbsent=$true
 [IO.File]::AppendAllText($c.Path,'tamper')
 $script:rdcMigrationHandoff=$c
 Complete-RdcMigrationHandoff
 Check ($script:launches -eq 0 -and $script:messages -eq 2) 'handoff rehash rejects changed file'
 [IO.File]::WriteAllBytes($c.Path,$bytes)
 Set-Content -LiteralPath $c.Path -Stream Zone.Identifier -Value @('[ZoneTransfer]','ZoneId=3') -Encoding ASCII
 $script:rdcMigrationHandoff=$c
 Complete-RdcMigrationHandoff
 Check ($script:launches -eq 1 -and !$script:rdcMigrationHandoff) 'validated handoff launches exactly once (mock)'
 Complete-RdcMigrationHandoff
 Check ($script:launches -eq 1) 'no repeated launch'
 Remove-Item -LiteralPath $c.Path -Stream Zone.Identifier
 $script:rdcMigrationHandoff=$c
 Complete-RdcMigrationHandoff
 Check ($script:launches -eq 1 -and $script:messages -eq 3) 'missing zone marker refuses launch'
}finally{
 [IO.File]::Delete($c.Path)
 [IO.Directory]::Delete([IO.Path]::GetDirectoryName($c.Path),$false)
}
$gui=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'))
$notice=[IO.File]::ReadAllText((Join-Path $src 'update-notice.ps1'))
$helper=[IO.File]::ReadAllText((Join-Path $src 'legacy-migration.ps1'))
Check ($gui.LastIndexOf('Complete-RdcMigrationHandoff') -gt $gui.LastIndexOf('$windowMutex.ReleaseMutex()')) 'setup handoff after original window mutex release'
Check ($notice.Contains('Start-RdcLegacyMigration') -and $notice.Contains('Clear-RdcMigrationDownload') -and !$notice.Contains('    Start-RuntimeInitialization')) 'button and dispose routes integrated'
Check ($helper.Contains('$form.Close()') -and !$helper.Contains('$script:allowClose=') -and !$helper.Contains('Stop-Process')) 'normal close only; no forced stop'
foreach($name in @('remote-window.ps1','update-notice.ps1','legacy-migration.ps1')){
 $t=$null;$e=$null
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $src $name),[ref]$t,[ref]$e)
 Check ($e.Count -eq 0) ('staged script parses '+$name)
}
'RDC_LEGACY_AUTO_MIGRATION_PASS='+$pass+' FAIL=0'
