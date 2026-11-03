# Isolated original renderer and uptime contract.
$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'))
$view=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'))
$runtime=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerRuntime.cs'))
$child=[IO.File]::ReadAllText((Join-Path $src 'RdcOwnerManagedProcess.cs'))
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'rc1-owner-gui.ps1'),[ref]$tokens,[ref]$errors)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){if($ok){$script:pass++;Write-Output ('PASS '+$label)}else{$script:fail++;Write-Output ('FAIL '+$label)}}
Check ($errors.Count -eq 0) 'Owner GUI parses'
Check ($view.Contains('Color-HeaderSemantics $headerLog $headerLog.TextLength') -and $view.Contains('StyleStartupBanner(')) 'original rich-text coloring retained'
Check ($child.Contains('public long BornUtcTicks {get{return born;}}')) 'verified Remote OS birth provided'
Check ($runtime.Contains('managedBornUtcTicks=child.BornUtcTicks') -and $runtime.Contains('"remoteBornUtcTicks"')) 'Remote birth sent by Host'
Check ($gui.Contains('{0:00}:{1:00}:{2:00}') -and $gui.Contains('$script:ownerRemoteBornTicks')) 'original uptime footer restored'
Check (-not $gui.Contains("'Управление: Host-owned Job'")) 'obsolete footer text removed'
Check ($runtime.Contains('AcceptManagedBannerArt(cleanLine)') -and $runtime.Contains('"remoteStartupArt"') -and $gui.Contains('$snapshot.remoteStartupArt')) 'safe original startup art in authenticated snapshot'
Check ($gui.Contains("('- User: '") -and $gui.Contains("('- Device Name: '") -and $gui.Contains("('- Device ID: '")) 'original semantic value coloring applies'
Write-Output ('RC1_BANNER_UPTIME_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
