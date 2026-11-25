# Full Host/GUI update executor. Imported only in the staged numeric build.
# Setup owns the actual activation and cooperative Host handoff.
$script:rdcFullHostDownload=$null
function Test-RdcFullHostInstalled{
 try{
  if(!$OwnerGui -or $SelfTest -or !$script:ownerManagedMode){return $false}
  if(-not ('RdcOwnerStartup' -as [type])){
   Add-Type -Path (Join-Path $root 'RdcOwnerStartup.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Security.dll')
  }
  return [RdcOwnerStartup]::IsActiveSource($root)
 }catch{return $false}
}
function Test-RdcFullHostUpdateIdle{
 try{
  if(!(Test-RdcFullHostInstalled) -or !$script:ownerCanStart -or $script:ownerCanStop -or
     $script:ownerRemoteBornTicks -ne 0 -or $script:ownerQueuedAction){return $false}
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='cmd.exe'" -ErrorAction Stop)){
   if(!$p.CommandLine -or ($p.CommandLine -match '(?i)desktop-commander' -and $p.CommandLine -match '(?i)\bremote\b')){return $false}
  }
  return $true
 }catch{return $false}
}
function Test-RdcFullHostAssetUri([Uri]$uri){
 return ($uri -and $uri.IsAbsoluteUri -and $uri.Scheme -ceq 'https' -and $uri.IsDefaultPort -and !$uri.UserInfo -and
  @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com') -ccontains $uri.DnsSafeHost)
}
function Test-RdcFullHostBytes([byte[]]$bytes,$offer){
 if(!$bytes -or !$offer -or $bytes.Length -ne $offer.Bytes -or $bytes.Length -lt 2 -or $bytes.Length -gt 100MB -or
    $bytes[0] -ne 77 -or $bytes[1] -ne 90 -or $offer.Digest -cnotmatch '^[A-F0-9]{64}$'){return $false}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') -ceq $offer.Digest)}finally{$sha.Dispose()}
}
function Assert-RdcFullHostUpdatePath([string]$path){
 for($p=[IO.Path]::GetFullPath($path);$p;$p=[IO.Path]::GetDirectoryName($p)){
  if(([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) -and ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint)){throw 'RDC_UPDATE_REPARSE'}
 }
}
function Save-RdcFullHostCandidate([byte[]]$bytes,$offer){
 if(!(Test-RdcFullHostBytes $bytes $offer)){throw 'RDC_UPDATE_HASH'}
 if($offer.Version -cnotmatch '^\d+\.\d+\.\d+$'){throw 'RDC_UPDATE_VERSION'}
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-FullUpdate-'+[Guid]::NewGuid().ToString('N'))
 Assert-RdcFullHostUpdatePath $dir
 if(Test-Path -LiteralPath $dir){throw 'RDC_UPDATE_COLLISION'}
 [void][IO.Directory]::CreateDirectory($dir)
 $path=Join-Path $dir ('RDC.Relay.Setup.v'+$offer.Version+'.exe')
 Assert-RdcFullHostUpdatePath $path
 $f=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 Set-Content -LiteralPath $path -Stream Zone.Identifier -Value @('[ZoneTransfer]','ZoneId=3') -Encoding ASCII -ErrorAction Stop
 return $path
}
function Invoke-RdcFullHostCandidate([string]$path,$offer){
 Assert-RdcFullHostUpdatePath $path
 if(!(Test-RdcFullHostUpdateIdle)){throw 'RDC_UPDATE_REMOTE_ACTIVE'}
 if((Get-Item -LiteralPath $path).Length -ne $offer.Bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $offer.Digest){throw 'RDC_UPDATE_DISK_HASH'}
 if((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw -ErrorAction Stop) -notmatch '(?m)^ZoneId=3\r?$'){throw 'RDC_UPDATE_ZONE'}
 # Interactive Setup validates the installed predecessor and takes its
 # own Host/maintenance leases. No force-kill or old flat updater.
 Start-Process -FilePath $path -ErrorAction Stop -PassThru
}
function Clear-RdcFullHostDownload{
 $d=$script:rdcFullHostDownload
 $script:rdcFullHostDownload=$null
 if($d){
  if($d.Timer){$d.Timer.Stop();$d.Timer.Dispose()}
  if($d.Client){$d.Client.Dispose()}
  if($d.Process){$d.Process.Dispose()}
 }
 $script:rdcNoticeInstalling=$false
 if($script:rdcNoticeControl -and !$script:rdcNoticeControl.IsDisposed){$script:rdcNoticeControl.Installing=$false}
}
function Show-RdcFullUpdateMessage([string]$key,[string]$fallback){
 [void][Windows.Forms.MessageBox]::Show((Get-RdcOwnerNoticeText $key $fallback),'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
}
function Update-RdcFullHostDownload{
 $d=$script:rdcFullHostDownload
 if(!$d){return}
 try{
  if($d.Process){
   if(!$d.Process.HasExited){return}
   $exit=$d.Process.ExitCode
   Clear-RdcFullHostDownload
   if($exit -ne 0){Show-RdcFullUpdateMessage 'update.owner.failed' 'Update did not complete.'}
   return
  }
  if([DateTime]::UtcNow -ge $d.Deadline){throw 'RDC_UPDATE_TIMEOUT'}
  if(!$d.Task.IsCompleted){return}
  $r=$d.Task.GetAwaiter().GetResult()
  try{
   if([int]$r.StatusCode -in @(301,302,303,307,308)){
    if(!$r.Headers.Location -or $d.Hops -ge 5){throw 'RDC_UPDATE_REDIRECT'}
    $next=[Uri]::new($d.Uri,$r.Headers.Location)
    if(!(Test-RdcFullHostAssetUri $next)){throw 'RDC_UPDATE_REDIRECT'}
    $d.Uri=$next;$d.Hops++;$d.Task=$d.Client.GetAsync($next);return
   }
   [void]$r.EnsureSuccessStatusCode()
   $bytes=$r.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
   $path=Save-RdcFullHostCandidate $bytes $d.Offer
  }finally{$r.Dispose()}
  $d.Process=Invoke-RdcFullHostCandidate $path $d.Offer
 }catch{
  Clear-RdcFullHostDownload
  Show-RdcFullUpdateMessage 'update.owner.failed' 'Update did not complete.'
 }
}
function Start-RdcFullHostUpdate{
 if($script:rdcFullHostDownload -or !$script:rdcFullHostOffer -or !$script:rdcNoticeControl.ButtonReady){return}
 $offer=$script:rdcFullHostOffer
 if($offer.Version -cne $script:rdcNoticeControl.OfferedVersion){return}
 if(!(Test-RdcFullHostUpdateIdle)){
  Show-RdcFullUpdateMessage 'update.owner.stopFirst' 'Stop Remote before updating.'
  return
 }
 $question=(Get-RdcOwnerNoticeText 'update.owner.confirm' 'Install RDC Relay {version}?').Replace('{version}',$offer.Version)
 if([Windows.Forms.MessageBox]::Show($question,'RDC Relay',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2) -ne [Windows.Forms.DialogResult]::Yes){return}
 if(!(Test-RdcFullHostUpdateIdle)){return}
 try{
  Add-Type -AssemblyName System.Net.Http
  if(!(Test-RdcFullHostAssetUri $offer.Uri)){throw 'RDC_UPDATE_URI'}
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $handler=New-Object Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect=$false;$handler.UseCookies=$false;$handler.UseDefaultCredentials=$false
  $client=New-Object Net.Http.HttpClient($handler)
  $client.Timeout=[TimeSpan]::FromSeconds(45)
  $client.MaxResponseContentBufferSize=100MB
  $client.DefaultRequestHeaders.UserAgent.ParseAdd('RDCRelayFullUpdate/1.0')
  $timer=New-Object Windows.Forms.Timer;$timer.Interval=150
  $script:rdcFullHostDownload=[pscustomobject]@{Client=$client;Timer=$timer;Task=$null;Uri=$offer.Uri;Offer=$offer;Hops=0;Deadline=[DateTime]::UtcNow.AddSeconds(90);Process=$null}
  $script:rdcNoticeInstalling=$true;$script:rdcNoticeControl.Installing=$true
  $script:rdcFullHostDownload.Task=$client.GetAsync($offer.Uri)
  $timer.Add_Tick({Update-RdcFullHostDownload});$timer.Start()
 }catch{
  Clear-RdcFullHostDownload
  Show-RdcFullUpdateMessage 'update.owner.failed' 'Update did not complete.'
 }
}
