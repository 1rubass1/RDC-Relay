# Full Host/GUI release pipeline, qualification stage.
# Public publication remains intentionally disabled until the activation,
# ARP/uninstall and update-channel migration contracts pass OS-level trials.
param([switch]$Qualify)
$ErrorActionPreference='Stop'
if(-not $Qualify){throw 'RDC_V16_PUBLICATION_NOT_READY_USE_QUALIFY'}
$repo=Split-Path -Parent $PSScriptRoot
if((git -C $repo branch --show-current).Trim() -cne 'fix/rc1-tray-exit-prompt'){throw 'RDC_V16_QUALIFICATION_TOPIC_BRANCH_REQUIRED'}
if(@(git -C $repo status --porcelain).Count){throw 'RDC_V16_QUALIFICATION_REQUIRES_CLEAN_TREE'}
& (Join-Path $PSScriptRoot 'build-rc1-full.ps1') -Build -ReleaseQualification
if($LASTEXITCODE -ne 0){throw 'RDC_V16_QUALIFICATION_FAILED'}