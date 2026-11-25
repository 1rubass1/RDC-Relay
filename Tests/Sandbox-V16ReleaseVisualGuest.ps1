# Offline Windows Sandbox guest: source-only release-dialog previews, no installation.
# Two strictly mapped folders: input read-only, output report/images.
$ErrorActionPreference='Stop'
$inputDir='C:\RDC-Release-Input'
$outputDir='C:\RDC-Release-Output'
$sourceDir='C:\RDC-Release-Source'
$report=Join-Path $outputDir 'sandbox-release-report.txt'
$done=Join-Path $outputDir 'done.txt'
$lines=New-Object 'System.Collections.Generic.List[string]'
try{
 if(-not (Test-Path $inputDir) -or -not (Test-Path $outputDir)){
  throw 'SANDBOX_MAPPING_MISSING'
 }
 $zip=Join-Path $inputDir 'source.zip'
 $hashFile=Join-Path $inputDir 'source.sha256'
 $revFile=Join-Path $inputDir 'revision.txt'
 foreach($file in @($zip,$hashFile,$revFile)){
  if(-not [IO.File]::Exists($file)){throw ('SANDBOX_REQUIRED_INPUT_MISSING '+$file)}
 }
 $expected=[IO.File]::ReadAllText($hashFile,[Text.Encoding]::UTF8).Trim().ToLowerInvariant()
 $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
 if($expected -cne $actual){throw 'SANDBOX_SOURCE_HASH_MISMATCH'}
 [void][IO.Directory]::CreateDirectory($sourceDir)
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory($zip,$sourceDir)
 $expectedDirs=@('Installer','Source','Tests')
 foreach($dir in $expectedDirs){
  if(-not [IO.Directory]::Exists((Join-Path $sourceDir $dir))){
   throw ('SANDBOX_SOURCE_DIR_MISSING '+$dir)
  }
 }
 $revision=[IO.File]::ReadAllText($revFile,[Text.Encoding]::UTF8).Trim()
 [void]$lines.Add('SOURCE_GIT_SHA='+$revision)
 [void]$lines.Add('SOURCE_ZIP_SHA256='+$actual)
 [void]$lines.Add('NO_SETUP_LAUNCH=true')
 [void]$lines.Add('NO_REMOTE_HOST=true')
 [void]$lines.Add('NETWORK_DISABLED_BY_WSB=true')
 $tests=@(
  'Test-V16ReleaseInstallerLanguage.ps1',
  'Test-V16ReleaseMaintenance.ps1',
  'Test-V16ReleasePathDialog.ps1',
  'Test-V16ReleaseInstallPolicy.ps1',
  'Test-V16TrayV04Visual.ps1',
  'Test-V16OwnerQuotaFooter.ps1',
  'Test-V16ReleaseInstallerSandboxVisual.ps1'
 )
 foreach($name in $tests){
  $test=Join-Path $sourceDir ('Tests\'+$name)
  if(-not [IO.File]::Exists($test)){throw ('SANDBOX_TEST_MISSING '+$name)}
  $args=@('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',$test)
  if($name -ceq 'Test-V16ReleaseInstallerSandboxVisual.ps1'){
   $args+=@('-OutputDir',(Join-Path $outputDir 'screens'))
  }
  $output=@(& powershell.exe @args 2>&1)
  $exit=$LASTEXITCODE
  $summary=@($output|Where-Object{[string]$_ -match 'PASS=\d+.*FAIL=\d+|SCREENSHOTS=\d+'})|
   Select-Object -Last 1
  [void]$lines.Add($name+' EXIT='+$exit+' '+[string]$summary)
  if($exit -ne 0){
   foreach($item in @($output|Select-Object -Last 18)){
    [void]$lines.Add('ERR '+[string]$item)
   }
   throw ('SANDBOX_SUITE_FAILED '+$name)
  }
 }
 $shots=@(Get-ChildItem (Join-Path $outputDir 'screens') -Filter '*.png' -File)
 if($shots.Count -ne 12){throw ('SANDBOX_SCREENSHOT_COUNT '+$shots.Count)}
 [void]$lines.Add('SANDBOX_SUITES_PASS='+$tests.Count)
 [void]$lines.Add('SANDBOX_PNG_COUNT=12')
 [IO.File]::WriteAllText($done,'PASS',(New-Object Text.UTF8Encoding($false)))
}catch{
 [void]$lines.Add('SANDBOX_ERROR='+[string]$_.Exception.Message)
 [IO.File]::WriteAllText($done,'FAIL',(New-Object Text.UTF8Encoding($false)))
}finally{
 [IO.File]::WriteAllLines($report,$lines.ToArray(),(New-Object Text.UTF8Encoding($true)))
}
