# Real compiled Setup/Launcher validation, no product execution.
param([Parameter(Mandatory=$true)][string]$Package,[string]$ExpectedVersion='1.6.0',[switch]$PublicPreflight)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$Package=[IO.Path]::GetFullPath($Package)
$manifest=Get-Content -LiteralPath (Join-Path $Package 'owner-source-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$expectedKind=if($PublicPreflight){'FULL_HOST_GUI_V16_PUBLIC'}else{'FULL_HOST_GUI_V16_QUALIFICATION'}
$expectedStatus=if($PublicPreflight){'PUBLIC_RELEASE'}else{'RELEASE_QUALIFICATION'}
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;Write-Output ('PASS '+$label)}
Check ($manifest.candidate -ceq $ExpectedVersion -and $manifest.kind -ceq $expectedKind -and $manifest.installable -eq $true -and $manifest.publishable -eq [bool]$PublicPreflight) 'numeric package identity and matching publication class'
Check ($manifest.files.Count -eq 28 -and @($manifest.files.name|Select-Object -Unique).Count -eq 28) 'exact unique payload member count'
Check (-not (Test-Path -LiteralPath (Join-Path $Package 'Source/update.ps1'))) 'retired updater absent from new payload'
foreach($row in $manifest.files){
 $file=Join-Path $Package $row.name
 Check ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ceq $row.sha256) ('manifest SHA '+$row.name)
}
$source=Join-Path $Package 'Source'
$marker=Get-Content -LiteralPath (Join-Path $source 'rc1-candidate.json') -Raw -Encoding UTF8|ConvertFrom-Json
Check ($marker.candidate -ceq $ExpectedVersion -and $marker.status -ceq $expectedStatus -and $marker.publishable -eq [bool]$PublicPreflight -and !$marker.autoUpdateEnabled -and !$marker.stableManifestEnabled) 'qualification marker cannot activate public legacy updater'
Check (([IO.File]::ReadAllText((Join-Path $source 'version.txt'))).Trim() -ceq $ExpectedVersion) 'numeric disk version'
Check ((Get-FileHash -LiteralPath (Join-Path $source 'THIRD_PARTY_NOTICES.txt')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root 'Source\THIRD_PARTY_NOTICES.txt')).Hash) 'upstream license included byte-exact'
foreach($file in @('remote-window.ps1','rc1-owner-gui.ps1','update-notice.ps1','rc1-tray-host.ps1')){
 $err=$null;$tokens=$null
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source $file),[ref]$tokens,[ref]$err)
 Check ($err.Count -eq 0) ('actual staged script parses '+$file)
}
$gui=[IO.File]::ReadAllText((Join-Path $source 'remote-window.ps1'))
$owner=[IO.File]::ReadAllText((Join-Path $source 'rc1-owner-gui.ps1'))
$runtime=[IO.File]::ReadAllText((Join-Path $source 'RdcOwnerRuntime.cs'))
Check ($gui.Contains("'$ExpectedVersion'") -and $owner.Contains("'guiBuild']='$ExpectedVersion'") -and $runtime.Contains(('RdcOwnerWire.String(request,"guiBuild")!="'+$ExpectedVersion+'"'))) 'GUI and authenticated Host version agree'
foreach($locale in @('ru-RU','en-US')){
 $lang=Get-Content -LiteralPath (Join-Path $source ('lang/'+$locale+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
 Check (-not (($lang|ConvertTo-Json -Depth 10).Contains('1.6.0 RC1'))) ('localized version '+$locale)
}
$binding=[Reflection.BindingFlags]'Static,NonPublic,Public'
$setupName=if($PublicPreflight){'RDC.Relay.Setup.v'+$ExpectedVersion+'.exe'}else{'RC1 Pilot Setup.exe'}
$setup=Join-Path $Package $setupName
$launcherName=if($PublicPreflight){'RDC Relay.exe'}else{'RC1 Pilot Launcher.exe'}
$launcher=Join-Path $Package $launcherName
foreach($exe in @($setup,$launcher)){
 $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
 Check ($info.FileVersion -ceq ($ExpectedVersion+'.0') -and $info.CompanyName -ceq 'RUBASS') ('PE version '+[IO.Path]::GetFileName($exe))
}
$setupAsm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($setup))
$launchAsm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($launcher))
$setupType=$setupAsm.GetType('RdcRc1CandidateSetup',$true)
$launchType=$launchAsm.GetType('RdcRc1CandidateLauncher',$true)
$validate=$setupType.GetMethod('ValidateSource',$binding)
$portable=$launchType.GetMethod('ValidatePortablePackage',$binding)
[void]$validate.Invoke($null,@($Package))
[void]$portable.Invoke($null,@($Package))
Check $true 'actual compiled Setup and Launcher accept same exact manifest'
Check ($setupType.GetMethod('ValidatedCandidateDisplayVersion',$binding).Invoke($null,@($Package)) -ceq $ExpectedVersion) 'actual compiled Setup confirmation numeric version'
$resourceNames=@($setupAsm.GetManifestResourceNames())
Check ($resourceNames.Count -eq 29) 'exact embedded manifest plus 28 payload resources'
foreach($row in @($manifest.files)+@([pscustomobject]@{name='owner-source-manifest.json';sha256=(Get-FileHash -LiteralPath (Join-Path $Package 'owner-source-manifest.json')).Hash})){
 $stream=$setupAsm.GetManifestResourceStream('RdcPayload.'+$row.name.Replace('/','.'))
 if(!$stream){throw ('MISSING_RESOURCE '+$row.name)}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$sha.Dispose();$stream.Dispose()}
 Check ($actual -ceq $row.sha256) ('embedded SHA '+$row.name)
}
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'update-notice.ps1'),[ref]$tokens,[ref]$err)
$fn=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq 'Get-RdcAvailableVersionFromManifest'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$OwnerGui=$true;$appVersion='1.6.0'
function FullFeed($v){[ordered]@{schema=1;architecture='full-host-gui';ready=$true;version=$v;tag=('v'+$v);asset=('RDC.Relay.Setup.v'+$v+'.exe');sha256=('a'*64);bytes=1500000}}
function Available($v){Get-RdcAvailableVersionFromManifest ((FullFeed $v)|ConvertTo-Json)}
Check ($null -eq (Available '1.5.18') -and $null -eq (Available '1.6.0') -and (Available '1.6.1') -ceq '1.6.1') 'numeric passive notice never advertises same or older version'
Check ($script:rdcFullHostOffer.Uri.AbsoluteUri -ceq 'https://github.com/1rubass1/RDC-Relay/releases/download/v1.6.1/RDC.Relay.Setup.v1.6.1.exe') 'exact new architecture installer asset'
Check ($null -eq (Get-RdcAvailableVersionFromManifest '{"version":"1.7.0","files":[{"name":"remote-window.ps1"},{"name":"update.ps1"}]}')) 'legacy flat manifest never accepted by full Host'
foreach($field in @('architecture','tag','asset','sha256')){
 $m=FullFeed '1.6.1';$m[$field]='invalid'
 Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json)) -and !$script:rdcFullHostOffer) ('refuse malformed '+$field)
}
$m=FullFeed '1.6.1';$m.ready=$false
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json))) 'not-ready release refused'
$m.ready='true'
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json))) 'string readiness rejected'
$m=FullFeed '1.6.1';$m.bytes=101MB
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json))) 'oversized installer rejected'
$appVersion='1.5.18'
Check ($null -eq (Available '1.6.1')) 'old clients cannot use full Host feed'
$appVersion='1.6.0'
$notice=[IO.File]::ReadAllText((Join-Path $source 'update-notice.ps1'))
Check ($notice.Contains('/Source/full-host-update-manifest.json') -and !$notice.Contains('/Source/update-manifest.json')) 'separate feed path'

$trial=Join-Path ([IO.Path]::GetTempPath()) ('RDC-V16-Qualification-Test-'+[Guid]::NewGuid().ToString('N'))
try{
 [void][IO.Directory]::CreateDirectory($trial)
 foreach($row in @($manifest.files)+@([pscustomobject]@{name='owner-source-manifest.json'})){
  $dest=Join-Path $trial $row.name
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
  [IO.File]::Copy((Join-Path $Package $row.name),$dest,$false)
 }
 $mp=Join-Path $trial 'owner-source-manifest.json'
 $old=[IO.File]::ReadAllText($mp)
 function Refuse($method,$label){
  $denied=$false;try{[void]$method.Invoke($null,@($trial))}catch{$denied=$true}
  Check $denied $label
 }
 [IO.File]::WriteAllText($mp,$old.Replace($expectedKind,'PRIVATE_FULL_RC1'))
 Refuse $validate 'Setup refuses RC1-kind substitution'
 Refuse $portable 'Launcher refuses RC1-kind substitution'
 [IO.File]::WriteAllText($mp,$old)
 [IO.File]::AppendAllText((Join-Path $trial 'Source/version.txt'),'tamper')
 Refuse $validate 'Setup rejects altered version file'
 Refuse $portable 'Launcher rejects altered version file'
}finally{if([IO.Directory]::Exists($trial)){[IO.Directory]::Delete($trial,$true)}}
Write-Output ('RDC_V16_QUALIFICATION_PASS='+$pass+' FAIL=0')