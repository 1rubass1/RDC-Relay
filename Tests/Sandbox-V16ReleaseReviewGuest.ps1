# Offline Windows Sandbox smoke. Never starts Host/GUI/Remote, Setup or updater.
# Host Input mapping MUST be read-only; Output is the sole writable host mapping.
$ErrorActionPreference='Stop'
$inputDir='C:\RDC-Review-Input'
$outputDir='C:\RDC-Review-Output'
$destination='C:\RDC-Review-Extract'
$zip=Join-Path $inputDir 'RDC-Relay-1.6.0-FullHostGui-REVIEW.zip'
$checker=Join-Path $inputDir 'RDC-Relay-1.6.0-Offline-Review-Check.exe'
$report=Join-Path $outputDir 'review-sandbox-report.txt'
$done=Join-Path $outputDir 'done.txt'
$lines=New-Object 'System.Collections.Generic.List[string]'
$pass=0
function Check([bool]$okay,[string]$reason){
 if(-not $okay){throw ('RDC_REVIEW_GUEST_FAILED '+$reason)}
 $script:pass++
 [void]$lines.Add('PASS '+$reason)
}
function RunVerifier([string]$folder){
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$checker
 $psi.Arguments=if($folder){'--verify "'+$folder+'"'}else{''}
 $psi.UseShellExecute=$false
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $psi.CreateNoWindow=$true
 $proc=[Diagnostics.Process]::Start($psi)
 if(!$proc.WaitForExit(15000)){
  try{$proc.Kill()}catch{}
  throw 'RDC_REVIEW_GUEST_CHECKER_TIMEOUT'
 }
 return @{Exit=$proc.ExitCode;Out=$proc.StandardOutput.ReadToEnd();Err=$proc.StandardError.ReadToEnd()}
}
try{
 Check ([IO.Directory]::Exists($inputDir) -and [IO.Directory]::Exists($outputDir)) 'mapped input/output available'
 Check ([IO.File]::Exists($zip) -and [IO.File]::Exists($checker)) 'both review artifacts available'
 foreach($pair in @(
  @{File=$zip;Sha=(Join-Path $inputDir 'review-zip.sha256')},
  @{File=$checker;Sha=(Join-Path $inputDir 'review-checker.sha256')}
  )){
  $expected=[IO.File]::ReadAllText($pair.Sha,[Text.Encoding]::UTF8).Trim()
  $actual=(Get-FileHash -LiteralPath $pair.File -Algorithm SHA256).Hash
  Check ($expected -ceq $actual) ('hash verified '+[IO.Path]::GetFileName($pair.File))
 }
 Check (-not [IO.Directory]::Exists($destination)) 'new guest-only extraction directory'
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory($zip,$destination)
 $manifest=Get-Content (Join-Path $destination 'review-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check ($manifest.files.Count -eq 27 -and !$manifest.installable -and
   !$manifest.publishable -and !$manifest.launchEnabled -and
   $manifest.kind -ceq 'FULL_HOST_GUI_SOURCE_REVIEW_ONLY') '27-member noninstallable manifest'
 $verified=RunVerifier $destination
 Check ($verified.Exit -eq 0 -and
   $verified.Out.Contains('RDC_RELEASE_REVIEW_PACKAGE_PASS=27 FAIL=0')) 'offline checker validates all extracted bytes'
 $withoutArgs=RunVerifier ''
 Check ($withoutArgs.Exit -eq 42 -and
   $withoutArgs.Err.Contains('RDC_RELEASE_REVIEW_NO_INSTALL_OR_REMOTE')) 'checker refuses launch without arguments'
 foreach($script in @('remote-window.ps1','rc1-tray-host.ps1','rc1-quota-client.ps1','update.ps1')){
  $file=Join-Path $destination ('payload\Source\'+$script)
  $firstLines=@(Get-Content -LiteralPath $file -TotalCount 25 -Encoding UTF8)
  Check ($firstLines -ccontains "throw 'RDC_RELEASE_REVIEW_NOT_LAUNCHABLE'") ('blocked entrypoint '+$script)
 }
 $dll=Join-Path $destination 'payload\RdcOwnerRuntime.dll'
 $original=[IO.File]::ReadAllBytes($dll)
 [IO.File]::AppendAllText($dll,'sandbox-corruption')
 $refused=RunVerifier $destination
 Check ($refused.Exit -eq 42 -and
   $refused.Err.Contains('RDC_RELEASE_REVIEW_PACKAGE_REFUSED')) 'tampered DLL is refused'
 [IO.File]::WriteAllBytes($dll,$original)
 $restored=RunVerifier $destination
 Check ($restored.Exit -eq 0 -and
   $restored.Out.Contains('RDC_RELEASE_REVIEW_PACKAGE_PASS=27')) 'restored DLL bytes pass verification'
 [void]$lines.Add('RDC_SANDBOX_REVIEW_PASS='+$pass+' FAIL=0')
 [void]$lines.Add('INSTALLER_EXECUTED=FALSE')
 [void]$lines.Add('REMOTE_HOST_EXECUTED=FALSE')
 [void]$lines.Add('NETWORK_DISABLED_BY_WSB=TRUE')
 [void]$lines.Add('EXTRACTED_GUEST_FOLDER='+$destination)
 [IO.File]::WriteAllText($done,'PASS',(New-Object Text.UTF8Encoding($false)))
}catch{
 [void]$lines.Add('RDC_SANDBOX_REVIEW_ERROR='+[string]$_.Exception.Message)
 [IO.File]::WriteAllText($done,'FAIL',(New-Object Text.UTF8Encoding($false)))
}finally{
 [IO.File]::WriteAllLines($report,$lines.ToArray(),(New-Object Text.UTF8Encoding($true)))
}
