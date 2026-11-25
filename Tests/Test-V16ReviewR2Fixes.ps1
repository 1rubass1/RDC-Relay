param([Parameter(Mandatory=$true)][string]$Package)
$ErrorActionPreference='Stop'
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$setup=Join-Path $Package 'RDC.Relay.Setup.v1.6.0.exe'
$asm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($setup))
$flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
$meta=$asm.GetType('RdcV16MetadataTransaction',$true)
$maint=$asm.GetType('RdcV16IntegratedMaintenance',$true)
$start=$asm.GetType('RdcOwnerStartup',$true)
function Call($type,$name,[object[]]$p){$a=[object[]]::new($p.Count);for($i=0;$i -lt $p.Count;$i++){$a[$i]=$p[$i].PSObject.BaseObject};$type.GetMethod($name,$flags).Invoke($null,$a)}
function Refuse($type,$name,[object[]]$p,[string]$reason){try{[void](Call $type $name $p);return $false}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};if($e.Message -cne $reason){Write-Host ('EXPECTED='+$reason+' ACTUAL='+$e.Message)};return $e.Message -ceq $reason}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-ReviewFix-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
 $desktop=[Environment]::GetFolderPath('DesktopDirectory')
 # F1 real desktop path read only; no shortcut is created or modified.
 [void](Call $meta 'Safe' @((Join-Path $desktop 'RDC Relay.lnk')))
 Check $true 'F1 exact system Desktop shortcut path accepted'
 $target=Join-Path $root 'target';[void][IO.Directory]::CreateDirectory($target)
 $junction=Join-Path $root 'junction'
 # A real junction in the isolated test folder, never system Desktop.
 New-Item -ItemType Junction -Path $junction -Target $target|Out-Null
 try{Check (Refuse $meta 'Safe' @((Join-Path $junction 'RDC Relay.lnk')) 'V16_METADATA_REPARSE') 'F1 unrelated junction refused'}finally{[IO.Directory]::Delete($junction,$false)}
 $input=Join-Path $root 'Input.exe';[IO.File]::Copy($setup,$input,$false)
 $hash=(Get-FileHash -LiteralPath $input).Hash
 $path=Join-Path $root 'Maintenance.exe'
 $args=[object[]]@($input,$path,$hash)
 # Exact executable left between publication and marker move.
 [IO.File]::Copy($input,$path,$false)
 [void](Call $maint 'PublishMaintenancePair' $args)
 Check ((Get-FileHash -LiteralPath $path).Hash -ceq $hash -and [IO.File]::ReadAllText($path+'.sha256') -ceq $hash) 'F2 exact orphan EXE recovered'
 [void](Call $maint 'PublishMaintenancePair' $args)
 Check ((Get-FileHash -LiteralPath $path).Hash -ceq $hash) 'F2 completed pair idempotent'
 [IO.File]::Delete($path+'.sha256')
 [IO.File]::AppendAllText($path,'foreign')
 $foreign=(Get-FileHash -LiteralPath $path).Hash
 Check (Refuse $maint 'PublishMaintenancePair' $args 'V16_MAINTENANCE_COLLISION') 'F2 foreign executable refused'
 Check ((Get-FileHash -LiteralPath $path).Hash -ceq $foreign -and !(Test-Path ($path+'.sha256'))) 'F2 foreign executable retained'
 [IO.File]::Delete($path)
 [IO.File]::WriteAllText($path+'.sha256',$hash,[Text.Encoding]::ASCII)
 Check (Refuse $maint 'PublishMaintenancePair' $args 'V16_MAINTENANCE_COLLISION') 'F2 marker-only refused'
 [IO.File]::Delete($path+'.sha256')
 [void](Call $maint 'PublishMaintenancePair' $args)
 Check ((Get-FileHash -LiteralPath $path).Hash -ceq $hash -and [IO.File]::ReadAllText($path+'.sha256') -ceq $hash) 'F2 fresh pair verified'
 # F3 first-install intent survives a simulated interruption, is bound to
 # manifest bytes and cannot be synthesized by an ordinary repair.
 Check (!(Call $start 'BeginFreshIntent' @($Package,$root,$false))) 'F3 ordinary repair does not create intent'
 Check (Call $start 'BeginFreshIntent' @($Package,$root,$true)) 'F3 first install records intent'
 Check (Call $start 'FreshIntentExists' @($root)) 'F3 durable intent visible'
 Check (Call $start 'BeginFreshIntent' @($Package,$root,$false)) 'F3 interrupted install resumes on same package'
 $other=Join-Path $root 'other';[void][IO.Directory]::CreateDirectory($other)
 [IO.File]::WriteAllText((Join-Path $other 'owner-source-manifest.json'),'other')
 Check (Refuse $start 'BeginFreshIntent' @($other,$root,$false) 'V16_FRESH_INTENT_COLLISION') 'F3 unrelated package refused'
 $intent=Join-Path $root 'RDCRelayFirstInstall.pending'
 [IO.File]::Delete($intent)
 Check (!(Call $start 'BeginFreshIntent' @($Package,$root,$false))) 'F3 completed intent does not recur'
 # F4 run the exact initialization block of the staged polling function.
 $notice=[IO.File]::ReadAllText((Join-Path $Package 'Source\update-notice.ps1'))
 $a=$notice.IndexOf('$handler = New-Object Net.Http.HttpClientHandler')
 $b=$notice.IndexOf('$script:rdcNoticeHttp.DefaultRequestHeaders.Accept.ParseAdd',$a)
 if($a -lt 0 -or $b -le $a){throw 'F4_SOURCE_DRIFT'}
 Add-Type -AssemblyName System.Net.Http
 . ([scriptblock]::Create($notice.Substring($a,$b-$a)))
 $client=$script:rdcNoticeHttp
 Check ($client.MaxResponseContentBufferSize -eq 256KB -and !$handler.AllowAutoRedirect -and !$handler.UseCookies -and !$handler.UseDefaultCredentials) 'F4 explicit bounded metadata client'
 Add-Type -TypeDefinition @'
using System;using System.IO;using System.Net;using System.Net.Sockets;using System.Text;using System.Threading;
public sealed class RdcReviewHttpFixture:IDisposable{
 TcpListener listener; Thread worker;
 public string Url;
 public RdcReviewHttpFixture(string mode){
  listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
  Url="http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port+"/";
  worker=new Thread(()=>Serve(mode));worker.IsBackground=true;worker.Start();
 }
 void Write(Stream s,string v){byte[] b=Encoding.ASCII.GetBytes(v);s.Write(b,0,b.Length);}
 void Serve(string mode){try{using(var c=listener.AcceptTcpClient())using(var s=c.GetStream()){
  c.ReceiveTimeout=3000;c.SendTimeout=3000;
  int n=0,last=0;while(n++<8192){int ch=s.ReadByte();if(ch<0)return;last=(last<<8)|ch;if(last==0x0d0a0d0a)break;}
  if(mode=="small")Write(s,"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}");
  else if(mode=="redirect")Write(s,"HTTP/1.1 302 Found\r\nLocation: "+Url+"other\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
  else if(mode=="length"){Write(s,"HTTP/1.1 200 OK\r\nContent-Length: 300000\r\nConnection: close\r\n\r\n");byte[] b=new byte[300000];s.Write(b,0,b.Length);}
  else {Write(s,"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n");byte[] b=new byte[16384];for(int i=0;i<20;i++){Write(s,"4000\r\n");s.Write(b,0,b.Length);Write(s,"\r\n");}Write(s,"0\r\n\r\n");}
 }}catch{}}
 public void Dispose(){listener.Stop();worker.Join(4000);}
}
'@
 foreach($mode in @('small','length','chunked','redirect')){
  $server=New-Object RdcReviewHttpFixture($mode)
  try{
   $ok=$false;$value=$null
   try{$value=$client.GetStringAsync($server.Url).GetAwaiter().GetResult();$ok=$true}catch{}
   if($mode -eq 'small'){Check ($ok -and $value -ceq '{}') 'F4 small response accepted'}
   else{Check (!$ok) ('F4 '+$mode+' refused')}
  }finally{$server.Dispose()}
 }
 $client.Dispose()
}finally{if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}}
'RDC_REVIEW_FIX_PASS='+$pass+' FAIL=0'
