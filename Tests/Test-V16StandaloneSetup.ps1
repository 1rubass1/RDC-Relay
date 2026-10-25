# Safe verification of a downloaded single Setup.exe. Does NOT invoke Main or install.
param([Parameter(Mandatory=$true)][string]$SetupPath)
$ErrorActionPreference='Stop'
$pass=0;$fail=0
function Check([bool]$yes,[string]$name){
 if($yes){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-RC1-EXE-'+[Guid]::NewGuid().ToString('N'))
$extracted=$null
try{
 [void][IO.Directory]::CreateDirectory($root)
 $download=Join-Path $root 'RDC Relay 1.6.0 RC1 Setup.exe'
 [IO.File]::Copy([IO.Path]::GetFullPath($SetupPath),$download,$false)
 Check (-not [IO.File]::Exists((Join-Path $root 'owner-source-manifest.json'))) 'EXE isolated from sidecars'
 $asm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($download))
 $type=$asm.GetType('RdcRc1CandidateSetup',$true)
 $flags=[Reflection.BindingFlags]'Static,NonPublic'
 $list=[string[]]$type.GetField('Required',$flags).GetValue($null)
 $items=@($list)+@('owner-source-manifest.json')
 $found=@($asm.GetManifestResourceNames())
 Check ($found.Count -eq $items.Count) 'EXE exact embedded item count'
 $allPresent=$true
 foreach($name in $items){
  $resource='RdcPayload.'+$name.Replace('/','.')
  if($found -cnotcontains $resource){$allPresent=$false;break}
 }
 Check $allPresent 'EXE all expected named payloads'
 $extract=$type.GetMethod('ExtractEmbeddedCandidate',$flags)
 $validate=$type.GetMethod('ValidateSource',$flags)
 $cleanup=$type.GetMethod('CleanExactExtraction',$flags)
 if(-not $extract -or -not $validate -or -not $cleanup){throw 'EXE_PRIVATE_VERIFIER_NOT_FOUND'}
 $extracted=[string]$extract.Invoke($null,@())
 Check ([IO.File]::Exists((Join-Path $extracted 'owner-source-manifest.json'))) 'EXE payload extracted without sidecars'
 [void]$validate.Invoke($null,[object[]]@($extracted))
 Check $true 'EXE extracted signed-by-manifest candidate validates'
 foreach($entry in $items){
  $expected=Join-Path $extracted ($entry.Replace('/','\'))
  if(-not [IO.File]::Exists($expected)) {throw ('EXE_ITEM_MISSING '+$entry)}
 }
 Check $true 'EXE exact required files extracted'
 [void]$cleanup.Invoke($null,[object[]]@($extracted))
 Check (-not [IO.Directory]::Exists($extracted)) 'EXE private extraction safely removed'
 $extracted=$null
}catch{$fail++;Write-Output ('FAIL EXE exception '+$_.Exception.Message)}
finally{
 if($null -ne $extracted){Write-Output ('PARTIAL EXE retained suspicious extraction '+$extracted)}
 try{
  $name=[IO.Path]::GetFileName($root)
  if($name -cnotmatch '^RDC-RC1-EXE-[a-f0-9]{32}$' -or
   [IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92))
   {throw 'EXE_ROOT_SCOPE_REFUSED'}
  $members=@(Get-ChildItem -LiteralPath $root -Force)
  if($members.Count -ne 1 -or $members[0].Name -cne 'RDC Relay 1.6.0 RC1 Setup.exe' -or
   ($members[0].Attributes -band [IO.FileAttributes]::ReparsePoint))
   {throw 'EXE_ROOT_UNKNOWN_CONTENT'}
  [IO.File]::Delete($members[0].FullName)
  [IO.Directory]::Delete($root,$false)
  Check (-not [IO.Directory]::Exists($root)) 'EXE disposable copy cleaned'
 }catch{$fail++;Write-Output ('FAIL EXE disposable copy not cleaned '+$root+' '+$_.Exception.Message)}
}
Write-Output ('RC1_STANDALONE_EXE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
