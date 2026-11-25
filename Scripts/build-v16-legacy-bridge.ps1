param([switch]$Qualify)
$ErrorActionPreference='Stop'
if(!$Qualify){throw 'RDC_BRIDGE_PUBLICATION_BLOCKED'}
$repo=Split-Path -Parent $PSScriptRoot
$base='5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb'
if((git -C $repo rev-parse 'v1.5.18^{commit}').Trim() -cne $base){throw 'RDC_BRIDGE_BASE_CHANGED'}
$stage=Join-Path $repo ('dist\RDC-Legacy-Bridge-QA-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
# Use the exact released installer, not Git checkout line endings.
$setup=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'RDC.Relay.Setup.v1.5.18.exe'
if((Get-FileHash -LiteralPath $setup).Hash -cne 'D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190'){throw 'BASE_SETUP_HASH'}
$src=Join-Path $stage 'Source'
[void][IO.Directory]::CreateDirectory($src)
$asm=[Reflection.Assembly]::ReflectionOnlyLoadFrom($setup)
function Read-Resource($name,$dest){
 $input=$asm.GetManifestResourceStream('RdcPayload.'+$name)
 if(!$input){throw 'RESOURCE_MISSING'}
 try{$output=[IO.File]::Open($dest,[IO.FileMode]::CreateNew);try{$input.CopyTo($output)}finally{$output.Dispose()}}finally{$input.Dispose()}
}
$mp=Join-Path $src 'update-manifest.json'
Read-Resource 'update-manifest.json' $mp
$m=[IO.File]::ReadAllText($mp)|ConvertFrom-Json
$expected=@('remote-window.ps1','update-notice.ps1','divider-caustic.ps','divider-caustic-detail.ps','divider-particles.ps','divider-particles-core.ps','RDCRelay.ico','version.txt','update.ps1','RDC Relay.cmd')
if($m.version -cne '1.5.18' -or $m.files.Count -ne $expected.Count -or @($m.files.name|Select-Object -Unique).Count -ne $expected.Count){throw 'BASE_MANIFEST'}
foreach($row in $m.files){
 if($expected -cnotcontains $row.name){throw 'BASE_MEMBER'}
 $name=if($row.name -ceq 'RDC Relay.cmd'){'launch.cmd'}else{$row.name}
 $p=Join-Path $src $row.name
 Read-Resource $name $p
 if((Get-FileHash -LiteralPath $p).Hash -cne $row.sha256){throw ('BASE_HASH '+$row.name)}
}
$p=Join-Path $src 'update-notice.ps1'
$raw=[IO.File]::ReadAllBytes($p);$bom=$raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191
$s=[IO.File]::ReadAllText($p)
function Replace-Exact($text,$old,$new){
 $nl=if($text.Contains([string][char]13+[char]10)){[string][char]13+[char]10}else{[string][char]10}
 $old=$old.Replace([string][char]13+[char]10,[string][char]10).Replace([string][char]10,$nl)
 $new=$new.Replace([string][char]13+[char]10,[string][char]10).Replace([string][char]10,$nl)
 if([regex]::Matches($text,[regex]::Escape($old)).Count -ne 1){throw 'SOURCE_DRIFT'}
 $text.Replace($old,$new)
}
$s=Replace-Exact $s @'
    $script:rdcNoticeInstalling = $true
    $script:rdcNoticeControl.Installing = $true
    $script:updateInstallRequested = $true
    Start-RuntimeInitialization
'@ @'
    if($script:rdcNoticeControl.OfferedVersion -ceq '1.6.0'){Start-RdcLegacyMigration}
'@
$s=Replace-Exact $s @'
    $remote = [Version]([string]$manifest.version)
    $local = [Version]$appVersion
    if ($remote -gt $local) { return [string]$manifest.version }
    return $null
'@ @'
    $script:rdcMigrationOffer=Get-RdcMigrationOffer $manifest $appVersion
    if($script:rdcMigrationOffer){return '1.6.0'}
    return $null
'@
# Stage the new helper as a normal manifest-listed flat legacy member.
$helper=Join-Path $src 'legacy-migration.ps1'
[IO.File]::Copy((Join-Path $PSScriptRoot 'v16-legacy-migration.ps1'),$helper,$false)
$m.files=@($m.files)+@([pscustomobject]@{name='legacy-migration.ps1';sha256=(Get-FileHash -LiteralPath $helper).Hash})
$s=Replace-Exact $s 'function Dispose-RdcUpdateNotice {' ('function Dispose-RdcUpdateNotice {'+[Environment]::NewLine+'    Clear-RdcMigrationDownload')
$s=Replace-Exact $s 'function Get-RdcAvailableVersionFromManifest([string]$Raw) {' ('. (Join-Path $PSScriptRoot ''legacy-migration.ps1'')'+[Environment]::NewLine+'function Get-RdcAvailableVersionFromManifest([string]$Raw) {')
# App.Run returns and the legacy mutex is released before Setup starts.
$gui=Join-Path $src 'remote-window.ps1'
$guiText=[IO.File]::ReadAllText($gui)
if(!$guiText.TrimEnd().EndsWith('$windowMutex.Dispose()'+[Environment]::NewLine+'    }'+[Environment]::NewLine+'}')){
 $tail=$guiText.TrimEnd() -split '\r?\n'
 if(($tail|Select-Object -Last 3) -join '|' -cne '$windowMutex.Dispose()|    }|}'){
  # Leading indentation is preserved in the actual source.
  if(($tail|Select-Object -Last 3|ForEach-Object{$_.Trim()}) -join '|' -cne '$windowMutex.Dispose()|}|}') {throw 'LEGACY_GUI_TAIL_DRIFT'}
 }
}
[IO.File]::AppendAllText($gui,[Environment]::NewLine+'if(Get-Command Complete-RdcMigrationHandoff -ErrorAction SilentlyContinue){Complete-RdcMigrationHandoff}'+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
. $helper
[IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding($bom)))
foreach($row in $m.files){$row.sha256=(Get-FileHash -LiteralPath (Join-Path $src $row.name)).Hash}
$m|Add-Member -NotePropertyName migration -NotePropertyValue ([ordered]@{schema=1;ready=$false;targetVersion='1.6.0';releaseTag='v1.6.0';mode='installer-handoff';asset='RDC.Relay.Setup.v1.6.0.exe';setupSha256=''})
[IO.File]::WriteAllText($mp,($m|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
if($e.Count){throw 'BRIDGE_PARSE'}
$fn=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq 'Get-RdcAvailableVersionFromManifest'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$pass=0
function Check([bool]$ok,[string]$name){if(!$ok){throw ('FAIL '+$name)};$script:pass++;'PASS '+$name}
$appVersion='1.5.18'
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json -Depth 6))) 'never offers unpublished installer'
$m.migration.ready=$true;$m.migration.setupSha256='a'*64
foreach($v in @('1.5.4','1.5.18','1.6.0','1.6.1')){
 $appVersion=$v;$actual=Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json -Depth 6)
 if([Version]$v -lt [Version]'1.6.0'){Check ($actual -ceq '1.6.0') ('fixed gateway '+$v)}
 else{Check ($null -eq $actual) ('new architecture not offered legacy gateway '+$v)}
}
$appVersion='1.5.18';$m.migration.targetVersion='1.7.0'
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json -Depth 6))) 'reject skipped gateway'
$m.migration.targetVersion='1.6.0';$m.migration.ready='true'
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json -Depth 6))) 'reject string ready flag'
$m.migration.ready=$true;$m.migration.setupSha256='invalid'
Check ($null -eq (Get-RdcAvailableVersionFromManifest ($m|ConvertTo-Json -Depth 6))) 'reject malformed digest'
Check (!$s.Contains('    Start-RuntimeInitialization')) 'no legacy update invocation'
'RDC_LEGACY_BRIDGE_PASS='+$pass
'RDC_LEGACY_BRIDGE_STAGE='+$stage
'RDC_LEGACY_BRIDGE_NOT_PUBLISHABLE=TRUE'
