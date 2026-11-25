# Fail-closed preflight for the legacy 1.5.x release builder.
# Uses only a disposable synthetic Git checkout in user TEMP. Never builds or
# runs the product installer, touches live registration, shortcuts or Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$builder=Join-Path $repo 'Scripts\build-release.ps1'
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-REL-V16-GATE-'+[Guid]::NewGuid().ToString('N'))
try{
 [void][IO.Directory]::CreateDirectory($root)
 [IO.File]::WriteAllText((Join-Path $root 'test-sentinel.txt'),[IO.Path]::GetFileName($root))
 $s=Join-Path $root 'Source'
 $scripts=Join-Path $root 'Scripts'
 [void][IO.Directory]::CreateDirectory($s)
 [void][IO.Directory]::CreateDirectory($scripts)
 [IO.File]::Copy($builder,(Join-Path $scripts 'build-release.ps1'))
 [IO.File]::WriteAllText((Join-Path $s 'version.txt'),'1.6.0')
 $null=& git -C $root init -q -b main 2>&1
 if($LASTEXITCODE -ne 0){throw 'FAKE_GIT_INIT_FAILED'}
 $null=& git -C $root -c user.name='RDC Test Fixture' -c user.email='fixture@invalid.example' add -- Scripts/build-release.ps1 Source/version.txt test-sentinel.txt
 if($LASTEXITCODE -ne 0){throw 'FAKE_GIT_ADD_FAILED'}
 $null=& git -C $root -c user.name='RDC Test Fixture' -c user.email='fixture@invalid.example' commit -q -m 'synthetic 1.6 packaging gate fixture'
 if($LASTEXITCODE -ne 0){throw 'FAKE_GIT_COMMIT_FAILED'}
 $fake=Join-Path $scripts 'build-release.ps1'
 $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $ErrorActionPreference='Continue'
 $output=@(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $fake 2>&1)
 $status=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 $full=[string]::Join("`n",@($output|ForEach-Object {[string]$_}))
 Check ($status -ne 0 -and $full.Contains('RDC_RELEASE_V16_REQUIRES_FULL_HOST_GUI_INTEGRATION')) 'legacy stable builder refuses 1.6.0 before any payload work'
 Check (-not [IO.Directory]::Exists((Join-Path $root 'dist')) -and
  -not [IO.File]::Exists((Join-Path $s 'update-manifest.json'))) '1.6.0 gate performs no source/package mutation'
 [IO.File]::WriteAllText((Join-Path $s 'rc1-candidate.json'),'{"candidate":"1.6.0 RC1"}')
 $null=& git -C $root -c user.name='RDC Test Fixture' -c user.email='fixture@invalid.example' add -- Source/rc1-candidate.json
 if($LASTEXITCODE -ne 0){throw 'FAKE_MARKER_ADD_FAILED'}
 $null=& git -C $root -c user.name='RDC Test Fixture' -c user.email='fixture@invalid.example' commit -q -m 'synthetic pilot marker fixture'
 if($LASTEXITCODE -ne 0){throw 'FAKE_MARKER_COMMIT_FAILED'}
 $ErrorActionPreference='Continue'
 $output=@(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $fake 2>&1)
 $status=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 $full=[string]::Join("`n",@($output|ForEach-Object {[string]$_}))
 Check ($status -ne 0 -and $full.Contains('RDC_RELEASE_REFUSES_OWNER_PILOT_MARKER')) 'pilot marker remains blocked even on a stable-labeled branch'
 Check (-not [IO.Directory]::Exists((Join-Path $root 'dist'))) 'pilot marker refusal causes no release artifact'
}catch{
 $fail++;Write-Output ('FAIL RELEASE_GATE_EXCEPTION '+$_.Exception.GetType().Name+' '+$_.Exception.Message)
}finally{
 if([IO.Directory]::Exists($root)){
  $expected=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92)
  $parent=[IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($root)).TrimEnd([char]92)
  if($parent -cne $expected -or
    [IO.Path]::GetFileName($root) -cnotmatch '^RDC-REL-V16-GATE-[a-f0-9]{32}$' -or
    [IO.File]::ReadAllText((Join-Path $root 'test-sentinel.txt')) -cne [IO.Path]::GetFileName($root)){
   $fail++;Write-Output 'NOT CLEAN RELEASE_GATE_UNVERIFIED_TEMP'
  }else{
   try{
    foreach($node in @(Get-ChildItem -LiteralPath $root -Force -Recurse)){
     if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'REPARSE_DETECTED'}
    }
    foreach($item in @(Get-ChildItem -LiteralPath $root -Force -File -Recurse)){$item.Attributes=[IO.FileAttributes]::Normal}
    [IO.Directory]::Delete($root,$true)
    Check (-not [IO.Directory]::Exists($root)) 'synthetic repository deleted after safe scope check'
   }catch{$fail++;Write-Output ('NOT CLEAN RELEASE_GATE_TEMP_LEFT '+$_.Exception.GetType().Name+' '+$_.Exception.Message)}
  }
 }
}
Write-Output ('RC1_LEGACY_RELEASE_BUILDER_GATE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
