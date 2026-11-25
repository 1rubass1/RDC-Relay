param([Parameter(Mandatory=$true)][string]$PublicStage,[Parameter(Mandatory=$true)][string]$BridgeStage)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$package=Join-Path $PublicStage 'package'
$setup=Join-Path $package 'RDC.Relay.Setup.v1.6.0.exe'
$portable=Join-Path $PublicStage 'RDC.Relay.v1.6.0.Portable.zip'
$m=[IO.File]::ReadAllText((Join-Path $package 'owner-source-manifest.json'))|ConvertFrom-Json
if($m.kind -cne 'FULL_HOST_GUI_V16_PUBLIC' -or $m.candidate -cne '1.6.0' -or !$m.publishable -or $m.files.Count -ne 29){throw 'PUBLIC_PACKAGE_IDENTITY'}
$bridge=Join-Path $BridgeStage 'Source'
$b=[IO.File]::ReadAllText((Join-Path $bridge 'update-manifest.json'))|ConvertFrom-Json
if($b.version -cne '1.5.18' -or $b.migration.ready -or $b.files.Count -ne 11){throw 'BRIDGE_IDENTITY'}
$stage=Join-Path $repo ('dist\RDC-PublicSource-QA-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
$base='5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb'
if((git -C $repo rev-parse 'v1.5.18^{commit}').Trim() -cne $base){throw 'BASE_CHANGED'}
$baseZip=Join-Path $stage 'baseline.zip'
& git -C $repo archive --format=zip "--output=$baseZip" $base
if($LASTEXITCODE -ne 0){throw 'BASE_EXPORT'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tree=Join-Path $stage 'tree'
[IO.Compression.ZipFile]::ExtractToDirectory($baseZip,$tree)
# Legacy path must remain 1.5.18 flat files. The offer stays inactive until
# the verified exact asset is publicly accessible.
foreach($row in $b.files){
 $src=Join-Path $bridge $row.name
 if((Get-FileHash -LiteralPath $src).Hash -cne $row.sha256){throw 'BRIDGE_HASH'}
 [IO.File]::Copy($src,(Join-Path $tree ('Source/'+$row.name)),$true)
}
$b.migration.setupSha256=(Get-FileHash -LiteralPath $setup).Hash
[IO.File]::WriteAllText((Join-Path $tree 'Source\update-manifest.json'),($b|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
$feed=[ordered]@{schema=1;architecture='full-host-gui';ready=$false;version='1.6.0';tag='v1.6.0';asset='RDC.Relay.Setup.v1.6.0.exe';sha256=(Get-FileHash -LiteralPath $setup).Hash;bytes=(Get-Item -LiteralPath $setup).Length}
[IO.File]::WriteAllText((Join-Path $tree 'Source\full-host-update-manifest.json'),($feed|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
# Exact transformed source used to build the candidate, not development
# documents or unrelated tests. Do not check generated binaries into Git.
$full=Join-Path $tree 'FullHost'
foreach($row in $m.files){
 $src=Join-Path $package $row.name
 if((Get-FileHash -LiteralPath $src).Hash -cne $row.sha256){throw 'FULL_HASH'}
 if(!$row.name.StartsWith('Source/',[StringComparison]::Ordinal)){continue}
 $dst=Join-Path $full $row.name
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
 [IO.File]::Copy($src,$dst,$false)
}
$installer=Join-Path $full 'Installer'
[void][IO.Directory]::CreateDirectory($installer)
foreach($name in @('AssemblyInfo.cs','Rc1CandidateSetup.cs','Rc1CandidateLauncher.cs','Rc1ManualUpgrade.cs','RdcReleaseLegacyMigrationLease.cs','RdcV16MetadataTransaction.cs','RdcV16IntegratedMaintenance.cs')){
 [IO.File]::Copy((Join-Path $PublicStage ('build-source/'+$name)),(Join-Path $installer $name),$false)
}
# Store the intended package identity separately from the inactive feed.
[IO.File]::Copy((Join-Path $package 'owner-source-manifest.json'),(Join-Path $full 'verified-package-manifest.json'),$false)
# Public README accurately describes the new package and the deliberate
# compatibility channel; do not expose development worktree details.
$readme=@'
# RDC Relay

RDC Relay is an independent Windows companion GUI and background Host for
Desktop Commander Remote mode. It is not affiliated with the upstream project.

## Install

Download the installer from [GitHub Releases](https://github.com/1rubass1/RDC-Relay/releases).
RDC Relay 1.6.0 uses an independent background Host and graphical interface.
Setup installs per user and offers Node.js 24 LTS if a supported Node.js,
npm and npx installation is missing. The Windows dependency installer may
request administrator permission. Windows can warn about unsigned software
or prevent its execution under Smart App Control.

For portable use, extract the complete Portable ZIP into a local folder
and open RDC Relay.exe. Do not move the executable away from its supporting
files. Installed copies have Desktop/Start Menu shortcuts and an entry in
Windows Installed apps. Stop Remote and exit RDC Relay before uninstalling.

RDC Relay pins @wonderwhy-er/desktop-commander to 0.2.52. Pairing uses the
official upstream device approval flow; approve only devices you recognize.

## Architecture and updates

1.5.x uses the flat legacy update feed in Source/. Its final architecture
transition is 1.6.0. Full Host releases use a separate installer feed,
Source/full-host-update-manifest.json. FullHost/ contains the selected
runtime and installer sources for the new architecture. The retained
internal storage namespace preserves compatibility with prior local data.

The migration offer and full Host feed must remain inactive until the
corresponding exact public release assets are verified. Do not treat a
source snapshot with an inactive feed as an available automatic update.
'@
[IO.File]::WriteAllText((Join-Path $tree 'README.md'),$readme,(New-Object Text.UTF8Encoding($false)))
[IO.File]::Copy((Join-Path $PSScriptRoot 'build-v16-public-source.ps1'),(Join-Path $tree 'Scripts\build-release.ps1'),$true)
# Verify complete package resources and ZIP contents separately.
$z=[IO.Compression.ZipFile]::OpenRead($portable)
try{
 $expected=@($m.files.name)+@('owner-source-manifest.json')
 if($z.Entries.Count -ne $expected.Count -or @($z.Entries|Where-Object{$expected -cnotcontains $_.FullName}).Count){throw 'ZIP_SCOPE'}
 foreach($e in $z.Entries){
  $f=$e.Open();$sha=[Security.Cryptography.SHA256]::Create()
  try{$h=[BitConverter]::ToString($sha.ComputeHash($f)).Replace('-','')}finally{$sha.Dispose();$f.Dispose()}
  if($h -cne (Get-FileHash -LiteralPath (Join-Path $package $e.FullName)).Hash){throw 'ZIP_HASH'}
 }
}finally{$z.Dispose()}
$all=@(Get-ChildItem -LiteralPath $tree -Recurse -File -Force)
$patterns=@('(?<![A-Za-z0-9])tunnel_[A-Za-z0-9_-]{12,}','(?i)\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{18,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})','\beyJ[A-Za-z0-9_-]{25,}\.[A-Za-z0-9_-]{25,}')
foreach($f in $all){
 $name=$f.FullName.Substring($tree.Length+1).Replace('\','/')
 if($name -match '^(AGENTS\.md|PROJECT_(INDEX|CONTEXT)\.md|DECISIONS\.md|COORDINATION/|docs/dev/)' -or $name -match '(?i)\.(pen|log|dpapi|exe|dll|zip)$'){throw ('PUBLIC_PATH '+$name)}
 if($f.Extension -in @('.cs','.ps1','.json','.md','.txt','.cmd','.hlsl')){
  $t=[IO.File]::ReadAllText($f.FullName)
  foreach($pattern in $patterns){if([regex]::IsMatch($t,$pattern)){throw ('PUBLIC_SECRET_PATTERN '+$name)}}
 }
}
# Real Git object tree with unfiltered exact bytes; local-only staging repo.
$git=Join-Path $stage 'git'
[void][IO.Directory]::CreateDirectory($git)
& git -C $git init --quiet
if($LASTEXITCODE -ne 0){throw 'GIT_INIT'}
& git -C $git config core.autocrlf false
foreach($file in $all){
 $name=$file.FullName.Substring($tree.Length+1).Replace('\','/')
 $blob=(& git -C $git hash-object -w --no-filters -- $file.FullName).Trim()
 if($LASTEXITCODE -ne 0 -or $blob -cnotmatch '^[0-9a-f]{40}$'){throw 'GIT_HASH'}
 & git -C $git update-index --add --cacheinfo "100644,$blob,$name"
 if($LASTEXITCODE -ne 0){throw 'GIT_INDEX'}
}
$treeHash=(& git -C $git write-tree).Trim()
$export=Join-Path $stage 'git-export.zip'
& git -C $git archive --format=zip "--output=$export" $treeHash
if($LASTEXITCODE -ne 0){throw 'GIT_ARCHIVE'}
$verify=Join-Path $stage 'verify'
[IO.Compression.ZipFile]::ExtractToDirectory($export,$verify)
foreach($row in $b.files){
 if((Get-FileHash -LiteralPath (Join-Path $verify ('Source/'+$row.name))).Hash -cne $row.sha256){throw 'GIT_RAW_BRIDGE_HASH'}
}
foreach($row in @($m.files|Where-Object{$_.name.StartsWith('Source/')})){
 if((Get-FileHash -LiteralPath (Join-Path $verify ('FullHost/'+$row.name))).Hash -cne $row.sha256){throw 'GIT_RAW_FULL_HASH'}
}
'PUBLIC_SOURCE_TREE='+$treeHash
'PUBLIC_SOURCE_FILES='+$all.Count
'PUBLIC_SOURCE_STAGE='+$stage
'LEGACY_FEED_READY=FALSE'
'FULL_HOST_FEED_READY=FALSE'
'PUBLIC_SOURCE_PREFLIGHT_PASS'
'NO_PUBLICATION=TRUE'
