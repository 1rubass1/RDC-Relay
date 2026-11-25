# Runs only inside offline Windows Sandbox with explicit read-only mapped Input.
# Produces summary and screenshots in mapped Output. Never starts Host, Remote or installer.
$ErrorActionPreference='Stop'
$inputDir='C:\RDC-I18n-Input'
$outputDir='C:\RDC-I18n-Output'
$sourceDir='C:\RDC-I18n-Source'
$summary=Join-Path $outputDir 'smoke-report.txt'
$done=Join-Path $outputDir 'done.txt'
$lines=New-Object 'System.Collections.Generic.List[string]'
try{
 if(-not (Test-Path (Join-Path $inputDir 'source.zip'))){throw 'SANDBOX_SOURCE_ZIP_MISSING'}
 if(-not (Test-Path $outputDir)){throw 'SANDBOX_OUTPUT_NOT_MAPPED'}
 [void][IO.Directory]::CreateDirectory($sourceDir)
 # Use .NET ZIP directly: a disposable Windows Sandbox may omit the Archive module.
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $inputDir 'source.zip'),$sourceDir)
 $tests=@(
  'Test-V16OwnerHeaderStatusRu.ps1',
  'Test-V16OwnerDialogLanguage.ps1',
  'Test-V16OwnerAccountSwitchDialog.ps1',
  'Test-V16OwnerStopHelpDialogs.ps1',
  'Test-V16OwnerLanguage.ps1',
  'Test-V16OwnerJournalLanguage.ps1',
  'Test-V16OwnerRealUpdateNotice.ps1',
  'Test-V16OwnerTrayMenu.ps1',
  'Test-V16OwnerSandboxVisual.ps1'
 )
 foreach($name in $tests){
  $test=Join-Path (Join-Path $sourceDir 'Tests') $name
  if(-not (Test-Path $test)){throw ('MISSING_SANDBOX_TEST '+$name)}
  $args=@('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',$test)
  if($name -eq 'Test-V16OwnerSandboxVisual.ps1'){
    $args+=@('-OutputDir',(Join-Path $outputDir 'screens'))
  }
  $log=@(& powershell.exe @args 2>&1)
  $exit=$LASTEXITCODE
  $last=@($log|Where-Object{$_ -match 'PASS=|SCREENSHOTS='})|Select-Object -Last 1
  $record=$name+' EXIT='+$exit+' '+[string]$last
  [void]$lines.Add($record)
  if($exit -ne 0){
   [void]$lines.Add(([string]::Join([Environment]::NewLine,@($log|Select-Object -Last 14))))
   throw ('SANDBOX_TEST_FAILED '+$name)
  }
 }
 [void]$lines.Add('SANDBOX_TESTS_PASS='+$tests.Count)
 [IO.File]::WriteAllLines($done,@('PASS'),(New-Object Text.UTF8Encoding($false)))
}catch{
 [void]$lines.Add('SANDBOX_ERROR='+[string]$_.Exception.Message)
 [IO.File]::WriteAllLines($done,@('FAIL'),(New-Object Text.UTF8Encoding($false)))
}finally{
 [IO.File]::WriteAllLines($summary,$lines.ToArray(),(New-Object Text.UTF8Encoding($true)))
}
