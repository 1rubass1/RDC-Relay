# Offline Windows Sandbox: the real Owner GUI and tray in strictly FAKE_ONLY mode.
# No Remote, credential, network request, installer, or host-installed client.
$ErrorActionPreference='Stop'
$inputRoot='C:\RDC-I18n-Input'
$outputRoot='C:\RDC-I18n-Output'
$previewRoot='C:\RDC-I18n-Preview'
$status=Join-Path $outputRoot 'interactive-status.txt'
$notes=New-Object 'System.Collections.Generic.List[string]'
try{
 if(-not (Test-Path (Join-Path $inputRoot 'source.zip')) -or
    -not (Test-Path $outputRoot)){throw 'SANDBOX_MAPPING_NOT_PRESENT'}
 if(Test-Path $previewRoot){throw 'SANDBOX_PREVIEW_ALREADY_PRESENT'}
 [void][IO.Directory]::CreateDirectory($previewRoot)
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=Join-Path $inputRoot 'source.zip'
 $hasher=[Security.Cryptography.SHA256]::Create()
 try{$actual=([BitConverter]::ToString($hasher.ComputeHash([IO.File]::ReadAllBytes($zip)))).Replace('-','').ToLowerInvariant()}
 finally{$hasher.Dispose()}
 $expected=[IO.File]::ReadAllText((Join-Path $inputRoot 'source.sha256'),[Text.Encoding]::UTF8).Trim()
 if($actual -cne $expected){throw 'SANDBOX_ZIP_SHA256_MISMATCH'}
 [IO.Compression.ZipFile]::ExtractToDirectory($zip,$previewRoot)
 $entry=Join-Path $previewRoot 'Source\rc1-tray-host.ps1'
 $source=Join-Path $previewRoot 'Source'
 if(-not [IO.File]::Exists($entry) -or
    -not [IO.File]::Exists((Join-Path $source 'RdcUiLanguage.cs')) -or
    -not [IO.File]::Exists((Join-Path $source 'lang\en-US.json'))){throw 'PREVIEW_SOURCE_MISSING'}
 $sourceText=[IO.File]::ReadAllText($entry,[Text.Encoding]::UTF8)
 if(-not $sourceText.Contains('param([switch]$FakeOnly') -or
    -not $sourceText.Contains('RC1_SELECT_EXACTLY_ONE_MODE')){throw 'FAKE_ONLY_ENTRY_CONTRACT_CHANGED'}
 # The entire OS is disposable. FakeOnly without TrialRoot permits unlimited manual
 # inspection; TrialRoot is reserved by the runtime for bounded 15-120 s OS tests.
 $exe=Join-Path $PSHOME 'powershell.exe'
 $arguments=@('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',('"'+$entry+'"'),'-FakeOnly')
 $outFile=Join-Path $outputRoot 'fake-host-stdout.txt'
 $errFile=Join-Path $outputRoot 'fake-host-stderr.txt'
 $child=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $source -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
 [void]$notes.Add('MODE=FAKE_ONLY_RC1')
 [void]$notes.Add('NO_REAL_REMOTE=true')
 [void]$notes.Add('TRIAL_ROOT_NOT_USED=true')
 [void]$notes.Add('NETWORK_DISABLED_BY_WSB=true')
 [void]$notes.Add('HOST_PID='+[string]$child.Id)
 [void]$notes.Add('SOURCE_GIT_SHA='+[IO.File]::ReadAllText((Join-Path $inputRoot 'revision.txt'),[Text.Encoding]::UTF8).Trim())
 $healthy=$true
 for($i=0;$i -lt 14;$i++){
  Start-Sleep -Milliseconds 500
  $child.Refresh()
  if($child.HasExited){$healthy=$false;break}
 }
 if(-not $healthy){throw ('FAKE_HOST_EXITED_CODE_'+[string]$child.ExitCode)}
 [void]$notes.Add('FAKE_HOST_PROCESS_ALIVE=true')
 [void]$notes.Add('INSTRUCTIONS=Use tray icon > Language / Язык; only synthetic Remote state is available.')
 [IO.File]::WriteAllLines($status,$notes.ToArray(),(New-Object Text.UTF8Encoding($false)))
}catch{
 [void]$notes.Add('ERROR='+[string]$_.Exception.Message)
 [IO.File]::WriteAllLines($status,$notes.ToArray(),(New-Object Text.UTF8Encoding($false)))
 throw
}
