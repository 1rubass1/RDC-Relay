param([Parameter(Mandatory=$true)][string]$Package,[switch]$LiveGitHub)
$ErrorActionPreference='Stop'
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$asm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $Package 'RDC.Relay.Setup.v1.6.0.exe')))
$t=$asm.GetType('RdcOwnerStartup',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
function Call($name,[object[]]$p){$a=[object[]]::new($p.Count);for($i=0;$i -lt $p.Count;$i++){$a[$i]=$p[$i].PSObject.BaseObject};$t.GetMethod($name,$flags).Invoke($null,$a)}
function Refuse($name,[object[]]$p,[string]$reason){try{[void](Call $name $p);return $false}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};if($e.Message -cne $reason){Write-Host ('EXPECTED='+$reason+' ACTUAL='+$e.Message)};return $e.Message -ceq $reason}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-R2006-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
 $archive=Join-Path $root 'fresh-intent.removed'
 $marker=Join-Path $root 'RDCRelayFirstInstall.pending'
 $other=Join-Path $root 'other';[void][IO.Directory]::CreateDirectory($other)
 [IO.File]::WriteAllText((Join-Path $other 'owner-source-manifest.json'),'different manifest fixture')
 [void](Call 'RetireFreshIntent' @($Package,$root,$archive))
 Check (!(Test-Path $archive) -and !(Test-Path $marker)) 'ordinary removal no intent'
 [void](Call 'BeginFreshIntent' @($Package,$root,$true))
 $original=[IO.File]::ReadAllText($marker)
 Check (Refuse 'ValidateFreshIntentRetirement' @($other,$root,$archive) 'V16_FRESH_INTENT_COLLISION') 'foreign pending refuses removal before mutation'
 Check ([IO.File]::ReadAllText($marker) -ceq $original) 'foreign pending preserved'
 [void](Call 'RetireFreshIntent' @($Package,$root,$archive))
 Check (!(Test-Path $marker) -and [IO.File]::ReadAllText($archive) -ceq $original) 'matching pending archived'
 [void](Call 'RestoreRetiredFreshIntent' @($Package,$root,$archive))
 Check (!(Test-Path $archive) -and [IO.File]::ReadAllText($marker) -ceq $original) 'rollback restores exact pending'
 [void](Call 'RetireFreshIntent' @($Package,$root,$archive))
 Check (!(Call 'BeginFreshIntent' @($other,$root,$false))) 'different manifest ordinary installation unblocked'
 Check (Call 'BeginFreshIntent' @($other,$root,$true)) 'different manifest may start fresh'
 $new=[IO.File]::ReadAllText($marker)
 Check (Refuse 'RestoreRetiredFreshIntent' @($Package,$root,$archive) 'V16_FRESH_INTENT_COLLISION') 'rollback refuses overwrite of new intent'
 Check ([IO.File]::ReadAllText($marker) -ceq $new -and [IO.File]::ReadAllText($archive) -ceq $original) 'both distinct markers preserved'
 [IO.File]::Delete($marker)
 Check (Refuse 'RestoreRetiredFreshIntent' @($other,$root,$archive) 'V16_FRESH_INTENT_ARCHIVE_IDENTITY') 'foreign archive refused'
 # Exercise exact staged passive polling functions, with fake completed
 # tasks only at HTTP boundary. No UI or actual installer invocation.
 $path=Join-Path $Package 'Source\update-notice.ps1'
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'NOTICE_PARSE'}
 foreach($name in @('Update-RdcUpdateNoticePolling','Get-RdcAvailableVersionFromManifest')){
  $f=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
  if(!$f){throw 'NOTICE_FUNCTION'}
  . ([scriptblock]::Create($f.Extent.Text))
 }
 $script:sha='a6580ebabb4cfc2928c2aee60ca134c8521f50c5'
 $script:refUrl='https://api.github.com/repos/1rubass1/RDC-Relay/git/ref/heads/stable'
 $script:manifestUrl='https://raw.githubusercontent.com/1rubass1/RDC-Relay/'+$script:sha+'/Source/full-host-update-manifest.json'
 $script:refBody='{"ref":"refs/heads/stable","object":{"type":"commit","sha":"'+$script:sha+'"}}'
 $script:manifestBody='{"schema":1,"architecture":"full-host-gui","ready":true,"version":"1.6.1","tag":"v1.6.1","asset":"RDC.Relay.Setup.v1.6.1.exe","sha256":"'+('A'*64)+'","bytes":1000}'
 $OwnerGui=$true;$Preview=$true;$SelfTest=$false;$appVersion='1.6.0';$script:enableUpdateNotice=$true
 $nl=[Environment]::NewLine
 function Show-RdcUpdateNotice($version){$script:shown=$version}
 function Hide-RdcUpdateNotice{$script:shown=$null}
 function Add-Log($message){$script:logs++}
 $script:rdcNoticeHttp=[pscustomobject]@{}
 $script:rdcNoticeHttp|Add-Member ScriptMethod GetStringAsync {
  param([string]$url)
  [void]$script:calls.Add($url)
  if($url -ceq $script:refUrl){$raw=$script:refBody}
  elseif($url -ceq $script:manifestUrl){$raw=$script:manifestBody}
  else{throw 'Unexpected endpoint (large commit detail fixture would exceed cap)'}
  return [Threading.Tasks.Task]::FromResult([string]$raw)
 }
 function Poll {
  $script:calls=New-Object 'Collections.Generic.List[string]'
  $script:shown=$null;$script:logs=0
  $script:rdcNoticeCheckTask=$null;$script:rdcNoticeCheckPhase='';$script:rdcNoticeNextCheck=(Get-Date).AddSeconds(-1)
  1..3|ForEach-Object{Update-RdcUpdateNoticePolling}
 }
 Poll
 Check ($script:calls.Count -eq 2 -and $script:calls[0] -ceq $script:refUrl -and $script:calls[1] -ceq $script:manifestUrl -and $script:shown -ceq '1.6.1') 'large-commit ref routes to pinned full Host manifest and offer'
 foreach($bad in @(('{"ref":"refs/heads/main","object":{"type":"commit","sha":"'+$script:sha+'"}}'),('{"ref":"refs/heads/stable","object":{"type":"tag","sha":"'+$script:sha+'"}}'),'{"ref":"refs/heads/stable","object":{"type":"commit","sha":"invalid"}}')){
  $script:refBody=$bad;Poll
  Check ($script:calls.Count -eq 1 -and !$script:shown -and $script:logs -eq 1) 'invalid ref blocks manifest'
 }
 if($LiveGitHub){
  Add-Type -AssemblyName System.Net.Http
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $handler=New-Object Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect=$false;$handler.UseCookies=$false;$handler.UseDefaultCredentials=$false
  $client=New-Object Net.Http.HttpClient($handler)
  try{
   $client.MaxResponseContentBufferSize=256KB;$client.Timeout=[TimeSpan]::FromSeconds(8)
   $client.DefaultRequestHeaders.UserAgent.ParseAdd('RDCRelayUpdateNotice/1.0')
   $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
   $rejected=$false
   try{[void]$client.GetStringAsync(('https://api.github.com/repos/1rubass1/RDC-Relay/commits/'+$script:sha)).GetAwaiter().GetResult()}catch{$rejected=$true;'LARGE_DETAIL_REFUSED='+$_.Exception.Message}
   Check $rejected 'live large preflight commit details rejected by unchanged cap'
   $raw=$client.GetStringAsync('https://api.github.com/repos/1rubass1/RDC-Relay/git/ref/heads/release/v1.6.0-preflight').GetAwaiter().GetResult()
   $ref=$raw|ConvertFrom-Json
   Check ($ref.object.type -ceq 'commit' -and $ref.object.sha -ceq $script:sha -and $ref.ref -ceq 'refs/heads/release/v1.6.0-preflight') 'live compact ref resolves same large commit'
   'REF_BYTES='+[Text.Encoding]::UTF8.GetByteCount($raw)
   $real=$client.GetStringAsync($script:manifestUrl).GetAwaiter().GetResult()
   Check (($real|ConvertFrom-Json).architecture -ceq 'full-host-gui') 'live pinned manifest reachable'
   $script:refBody=($raw.Replace('refs/heads/release/v1.6.0-preflight','refs/heads/stable'))
   $script:manifestBody=$real;Poll
   Check ($script:calls.Count -eq 2 -and $script:calls[1] -ceq $script:manifestUrl -and $script:logs -eq 0 -and !$script:shown) 'actual ref/manifest response fixture completes passive check (inactive offer)'
  }finally{$client.Dispose()}
 }
}finally{if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}}
'RDC_R2_006_PASS='+$pass+' FAIL=0'
