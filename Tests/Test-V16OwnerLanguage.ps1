# Isolated production locale reader/writer and GUI+tray resource binding.
# Uses only a disposable temp directory; no Host, Remote, installed client, or live preference writes.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sourceRoot=Join-Path $root 'Source'
Add-Type -Path (Join-Path $sourceRoot 'RdcUiLanguage.cs') -ReferencedAssemblies @(
 'System.dll','System.Core.dll','System.Web.Extensions.dll')
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){
 if($ok){$script:pass++;Write-Output ('PASS '+$label)}
 else{$script:fail++;Write-Output ('FAIL '+$label)}
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('RdcUiLang-'+[Guid]::NewGuid().ToString('N'))
$state=Join-Path $testRoot 'state'
$path=Join-Path $state 'ui-language.json'
try{
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'ru-RU' -and -not [IO.File]::Exists($path)) 'missing preference preserves existing Russian without writing'
 Check ([RdcUiLanguage]::Supported('en-US') -and [RdcUiLanguage]::Supported('ru-RU') -and
  -not [RdcUiLanguage]::Supported('fr-FR')) 'locale allowlist accepts only Russian/English'
 [RdcUiLanguage]::SetPreference($path,'en-US')
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'en-US') 'English selection persisted atomically and read back'
 Check ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq '{"version":1,"locale":"en-US"}') 'preference is bounded versioned JSON'
 [RdcUiLanguage]::SetPreference($path,'ru-RU')
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'ru-RU') 'switching back to Russian persists correctly'
 Check (@(Get-ChildItem -LiteralPath $state -Filter '*.tmp').Count -eq 0 -and
  @(Get-ChildItem -LiteralPath $state -Filter '*.bak').Count -eq 0) 'atomic replace leaves no temp files'
 $denied=$false
 try{[RdcUiLanguage]::SetPreference($path,'de-DE')}catch{$denied=$true}
 Check ($denied -and [RdcUiLanguage]::ReadPreference($path) -ceq 'ru-RU') 'unsupported language refused without changing saved choice'
 [IO.File]::WriteAllText($path,'{"version":1,"locale":"fr-FR"}',(New-Object Text.UTF8Encoding($false)))
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'ru-RU') 'unsupported saved locale safely falls back to Russian'
 [IO.File]::WriteAllText($path,'broken',(New-Object Text.UTF8Encoding($false)))
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'ru-RU') 'malformed preference safely falls back to Russian'
 [IO.File]::WriteAllBytes($path,[byte[]]@(255,254,253))
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'ru-RU') 'invalid UTF-8 safely falls back to Russian'
 [RdcUiLanguage]::SetPreference($path,'en-US')
 Check ([RdcUiLanguage]::ReadPreference($path) -ceq 'en-US') 'valid choice recovers from malformed preference'
 $ru=[RdcUiLanguage]::LoadResources($sourceRoot,'ru-RU')
 $en=[RdcUiLanguage]::LoadResources($sourceRoot,'en-US')
 Check ($ru.Count -ge 93 -and $ru.Count -eq $en.Count) 'both integration resource catalogs load with matching base and extension keys'
 Check ([RdcUiLanguage]::Text($en,'tray.menu.start','Запустить') -ceq 'Start' -and
  [RdcUiLanguage]::Text($ru,'tray.menu.start','X') -ceq 'Запустить') 'fixed UI keys produce correct English and Russian labels'
 Check ([RdcUiLanguage]::Text($en,'missing.translation.key','Русский резерв') -ceq 'Русский резерв') 'missing key falls back to Russian without an exception'
 Check (([RdcUiLanguage]::LoadResources($sourceRoot,'fr-FR')).Count -eq 0) 'unsupported resource locale has no catalog'
 $fakeSource=Join-Path $testRoot 'source'
 $fakeLang=Join-Path $fakeSource 'lang'
 [IO.Directory]::CreateDirectory($fakeLang) | Out-Null
 Copy-Item -LiteralPath (Join-Path $sourceRoot 'lang\en-US.json') -Destination (Join-Path $fakeLang 'en-US.json')
 $malformed=Join-Path $fakeLang 'en-US.json'
 [IO.File]::WriteAllText($malformed,'{"schema":"other"}',(New-Object Text.UTF8Encoding($false)))
 Check (([RdcUiLanguage]::LoadResources($fakeSource,'en-US')).Count -eq 0) 'wrong schema is rejected without display crash'
 $hostSource=[IO.File]::ReadAllText((Join-Path $sourceRoot 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
 $gui=[IO.File]::ReadAllText((Join-Path $sourceRoot 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
 $legacy=[IO.File]::ReadAllText((Join-Path $sourceRoot 'remote-window.ps1'),[Text.Encoding]::UTF8)
 Check ($hostSource.Contains('command=="LANGUAGE_RU"||command=="LANGUAGE_EN"') -and
  $hostSource.IndexOf('command=="LANGUAGE_RU"||command=="LANGUAGE_EN"') -lt $hostSource.IndexOf('if(command!="START"&&command!="STOP"')) 'tray language route is isolated before Remote action dispatcher'
 Check ($hostSource.Contains('RdcUiLanguage.SetPreference(RdcUiLanguage.PreferencePath,') -and
  $gui.Contains('Apply-RdcOwnerLocale') -and $gui.Contains('Set-RdcOwnerLocalizedFinishLabel') -and
  -not $legacy.Contains('$accountMenu.Items.Add($languageMenuItem)') -and
  -not $gui.Contains('$languageRuItem.Add_Click')) 'Tray exclusively owns locale choice; GUI retains locale repaint and state-derived action label'
 $packageAllowlist=@(
  (Join-Path $root 'Scripts\build-rc1-full.ps1'),
  (Join-Path $root 'Installer\Rc1CandidateSetup.cs'),
  (Join-Path $root 'Installer\Rc1CandidateLauncher.cs'),
  (Join-Path $root 'Scripts\rc1-private-upgrade-transaction.ps1')
 )
 foreach($listPath in $packageAllowlist){
  $data=[IO.File]::ReadAllText($listPath,[Text.Encoding]::UTF8)
  Check ($data.Contains('RdcUiLanguage.cs') -and
   $data.Contains('lang/ru-RU.json') -and $data.Contains('lang/en-US.json')) (
   'candidate staging/launcher includes code and both language files: '+[IO.Path]::GetFileName($listPath))
 }
 foreach($file in @('rc1-tray-host.ps1','rc1-owner-gui.ps1','remote-window.ps1')){
  $errors=$null;$tokens=$null
  [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $sourceRoot $file),[ref]$tokens,[ref]$errors)
  Check ($errors.Count -eq 0) ('parses '+$file)
 }
}finally{
 if([IO.Directory]::Exists($testRoot)){[IO.Directory]::Delete($testRoot,$true)}
}
Write-Output ('RC1_OWNER_LANGUAGE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
