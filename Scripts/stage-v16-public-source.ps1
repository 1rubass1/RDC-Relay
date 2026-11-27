param([Parameter(Mandatory=$true)][string]$PublicStage)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$package=Join-Path $PublicStage 'package'
$setup=Join-Path $package 'RDC.Relay.Setup.v1.6.0.exe'
$portable=Join-Path $PublicStage 'RDC.Relay.v1.6.0.Portable.zip'
$m=[IO.File]::ReadAllText((Join-Path $package 'owner-source-manifest.json'))|ConvertFrom-Json
if($m.kind -cne 'FULL_HOST_GUI_V16_PUBLIC' -or $m.candidate -cne '1.6.0' -or !$m.publishable -or $m.files.Count -ne 28 -or @($m.files|Where-Object name -ceq 'Source/update.ps1').Count){throw 'PUBLIC_PACKAGE_IDENTITY'}
# Clean public tree: no archive or bridge from any legacy tag. Keep the
# full-host feed at the already shipped path for 1.6.0 client compatibility.
$stage=Join-Path $repo ('dist\RDC-PublicSource-QA-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tree=Join-Path $stage 'tree'
[void][IO.Directory]::CreateDirectory((Join-Path $tree 'Source'))
[void][IO.Directory]::CreateDirectory((Join-Path $tree 'Scripts'))
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
# Public README accurately describes the new package and its sole
# update channel; do not expose development worktree details.
$readme=@'
# RDC Relay

RDC Relay is an independent Windows companion GUI and background Host for
Desktop Commander Remote mode. It is not affiliated with the upstream project.

## Install

Download the installer from [GitHub Releases](https://github.com/Rubo-Facility/RDC-Relay/releases).
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

RDC Relay 1.6.0 is the supported Full Host/GUI baseline. The installer
update feed is Source/full-host-update-manifest.json. FullHost/ contains
the selected runtime and installer sources. The retained internal
storage namespace preserves existing Full Host settings and installation
identity. Automatic migration from the retired 1.5.x architecture is not
supported. Uninstall an old 1.5.x installation using its own supported
uninstall route before installing the current release.

The full Host feed must remain inactive until the corresponding exact
public release asset is verified. Do not treat a source snapshot with
an inactive feed as an available automatic update.
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
$feedFiles=@(Get-ChildItem -LiteralPath (Join-Path $verify 'Source') -Force)
if($feedFiles.Count -ne 1 -or $feedFiles[0].Name -cne 'full-host-update-manifest.json' -or $feedFiles[0].PSIsContainer){throw 'PUBLIC_LEGACY_FEED_PRESENT'}
$verifiedFeed=[IO.File]::ReadAllText($feedFiles[0].FullName)|ConvertFrom-Json
if($verifiedFeed.schema -ne 1 -or $verifiedFeed.architecture -cne 'full-host-gui' -or $verifiedFeed.ready -ne $false -or $verifiedFeed.sha256 -cne (Get-FileHash -LiteralPath $setup).Hash){throw 'PUBLIC_FULL_FEED_VERIFY'}
foreach($row in @($m.files|Where-Object{$_.name.StartsWith('Source/')})){
 if((Get-FileHash -LiteralPath (Join-Path $verify ('FullHost/'+$row.name))).Hash -cne $row.sha256){throw 'GIT_RAW_FULL_HASH'}
}
'PUBLIC_SOURCE_TREE='+$treeHash
'PUBLIC_SOURCE_FILES='+$all.Count
'PUBLIC_SOURCE_STAGE='+$stage
'LEGACY_FEED_ABSENT=TRUE'
'FULL_HOST_FEED_READY=FALSE'
'PUBLIC_SOURCE_PREFLIGHT_PASS'
'NO_PUBLICATION=TRUE'
