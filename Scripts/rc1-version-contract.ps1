# Build-time guard: the source marker is the candidate version authority.
# Prevent shipping a Setup whose visible GUI/launcher identity disagrees.
# Read-only; the caller owns the build and stages the metadata.
function Assert-Rc1CandidateVersionContract {
 param(
  [Parameter(Mandatory=$true)][string]$SourceDirectory,
  [Parameter(Mandatory=$true)][string]$InstallerDirectory
 )
 $markerPath=Join-Path $SourceDirectory 'rc1-candidate.json'
 $marker=[IO.File]::ReadAllText($markerPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
 $version=[string]$marker.candidate
 if($version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+ RC[1-9][0-9]*$'){
  throw 'RC1_BUILD_CANDIDATE_VERSION_FORMAT'
 }
 $quote=[char]39
 $contracts=@(
  @{
   path=Join-Path $SourceDirectory 'remote-window.ps1'
   exact='$appVersion = if($OwnerGui){'+$quote+$version+$quote+'}else{'
   error='RC1_BUILD_GUI_VERSION_MISMATCH'
  },
  @{
   path=Join-Path $SourceDirectory 'rc1-owner-gui.ps1'
   exact='$hello['+$quote+'guiBuild'+$quote+']='+$quote+$version+$quote
   error='RC1_BUILD_OWNER_HELLO_VERSION_MISMATCH'
  },
  @{
   path=Join-Path $InstallerDirectory 'Rc1CandidateLauncher.cs'
   exact='(string)values["candidate"]!="'+$version+'"'
   error='RC1_BUILD_LAUNCHER_VERSION_MISMATCH'
  },
  @{
   path=Join-Path $InstallerDirectory 'Rc1CandidateSetup.cs'
   exact='(string)manifest["candidate"]!="'+$version+'"'
   error='RC1_BUILD_SETUP_VERSION_MISMATCH'
  }
 )
 foreach($contract in $contracts){
  $text=[IO.File]::ReadAllText([string]$contract.path,[Text.Encoding]::UTF8)
  if(-not $text.Contains([string]$contract.exact)){throw [string]$contract.error}
 }
 return $version
}
