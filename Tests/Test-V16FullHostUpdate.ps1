param([Parameter(Mandatory=$true)][string]$Package)
$ErrorActionPreference='Stop'
$p=Join-Path $Package 'Source\update-notice.ps1'
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
if($e.Count){throw ($e|Out-String)}
$fn=@($ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and ($a.Name -like '*RdcFullHost*' -or $a.Name -eq 'Show-RdcFullUpdateMessage')},$false))
if($fn.Count -ne 11){throw ('HELPER_FUNCTION_COUNT='+$fn.Count)}
foreach($f in $fn){. ([scriptblock]::Create($f.Extent.Text))}
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$OwnerGui=$true;$SelfTest=$false;$script:ownerManagedMode=$false
Check (!(Test-RdcFullHostInstalled)) 'fake or observer refused'
foreach($u in @('https://github.com/a','https://objects.githubusercontent.com/a','https://release-assets.githubusercontent.com/a')){Check (Test-RdcFullHostAssetUri ([Uri]$u)) ('allowed '+$u)}
foreach($u in @('http://github.com/a','https://github.com.evil.test/a','https://evil.test/a','https://github.com:444/a','https://u@github.com/a')){Check (!(Test-RdcFullHostAssetUri ([Uri]$u))) ('refused '+$u)}
[byte[]]$bytes=77,90,1,2,3,4
$sha=[Security.Cryptography.SHA256]::Create()
try{$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
$offer=[pscustomobject]@{Version='1.6.1';Digest=$hash;Bytes=$bytes.Length}
Check (Test-RdcFullHostBytes $bytes $offer) 'exact future installer fixture'
$bad=[pscustomobject]@{Version='1.6.1';Digest=('A'*64);Bytes=$bytes.Length}
Check (!(Test-RdcFullHostBytes $bytes $bad)) 'wrong digest refused'
$bad.Digest=$hash;$bad.Bytes=5
Check (!(Test-RdcFullHostBytes $bytes $bad)) 'wrong length refused'
$path=Save-RdcFullHostCandidate $bytes $offer
try{
 Check ((Get-FileHash -LiteralPath $path).Hash -ceq $hash) 'exact disk bytes'
 Check ((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw) -match '(?m)^ZoneId=3\r?$') 'internet provenance'
 $script:idle=$false;$script:launches=0
 function Test-RdcFullHostUpdateIdle{return $script:idle}
 function Start-Process{param($FilePath,$ErrorAction,[switch]$PassThru);if($FilePath -cne $path){throw 'UNEXPECTED_PATH'};$script:launches++;[pscustomobject]@{Id=123}}
 function Refuse($reason){
  try{[void](Invoke-RdcFullHostCandidate $path $offer);return $false}catch{return $_.Exception.Message -ceq $reason}
 }
 Check (Refuse 'RDC_UPDATE_REMOTE_ACTIVE') 'active Remote refuses launch'
 $script:idle=$true
 [IO.File]::AppendAllText($path,'tamper')
 Check (Refuse 'RDC_UPDATE_DISK_HASH') 'changed bytes refuse launch'
 [IO.File]::WriteAllBytes($path,$bytes)
 Set-Content -LiteralPath $path -Stream Zone.Identifier -Value @('[ZoneTransfer]','ZoneId=3') -Encoding ASCII
 [void](Invoke-RdcFullHostCandidate $path $offer)
 Check ($script:launches -eq 1) 'verified normal Setup launch (mock)'
 Remove-Item -LiteralPath $path -Stream Zone.Identifier
 $denied=$false;try{[void](Invoke-RdcFullHostCandidate $path $offer)}catch{$denied=$true}
 Check ($denied -and $script:launches -eq 1) 'missing zone refuses launch'
}finally{[IO.File]::Delete($path);[IO.Directory]::Delete([IO.Path]::GetDirectoryName($path),$false)}
$s=[IO.File]::ReadAllText($p)
Check ($s.Contains('Start-RdcFullHostUpdate') -and !$s.Contains('    Start-RuntimeInitialization')) 'no legacy update path'
Check ($s.Contains('Clear-RdcFullHostDownload') -and $s.Contains('$script:rdcNoticeControl.VisualPreviewOnly= -not (Test-RdcFullHostInstalled)')) 'installed-only action and teardown'
'RDC_FULL_HOST_UPDATE_PASS='+$pass+' FAIL=0'
