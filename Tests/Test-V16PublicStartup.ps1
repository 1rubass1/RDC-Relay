param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$PriorPackage)
$ErrorActionPreference='Stop'
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-PublicStartup-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$sub='Software\RDCRelayPublicStartupTest-'+[Guid]::NewGuid().ToString('N')
$key=$null
try{
 $asm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $Package 'RDC Relay.exe')))
 $type=$asm.GetType('RdcOwnerStartup',$true)
 $flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
 function Call($name,[object[]]$p){$a=[object[]]::new($p.Count);for($i=0;$i -lt $p.Count;$i++){$a[$i]=$p[$i].PSObject.BaseObject};$type.GetMethod($name,$flags).Invoke($null,$a)}
 $releases=Join-Path $root 'RDCRelayOwnerPilot\1.6.0-RC1\releases'
 [void][IO.Directory]::CreateDirectory($releases)
 function CopyPackage($p){
  $m=Join-Path $p 'owner-source-manifest.json'
  $manifest=[IO.File]::ReadAllText($m)|ConvertFrom-Json
  $dest=Join-Path $releases ('rc1-'+(Get-FileHash -LiteralPath $m).Hash.Substring(0,24).ToLowerInvariant())
  [void][IO.Directory]::CreateDirectory($dest)
  foreach($row in @($manifest.files)+@([pscustomobject]@{name='owner-source-manifest.json'})){
   $f=Join-Path $dest $row.name
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($f))
   [IO.File]::Copy((Join-Path $p $row.name),$f,$false)
  }
  return $dest
 }
 $release=[string](CopyPackage $Package)
 $prior=[string](CopyPackage $PriorPackage)
 Check (Call 'VerifiedRelease' @($release,$root)) 'public package verified in installed namespace'
 Check (Call 'VerifiedRelease' @($prior,$root)) 'prior qualification recognized'
 Check ((Call 'ReleaseLauncher' @($release)) -ceq 'RDC Relay.exe') 'public entry point'
 Check ((Call 'ReleaseLauncher' @($prior)) -ceq 'RC1 Pilot Launcher.exe') 'prior entry point'
 $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
 $old=Join-Path $root 'RDCRelayOwnerPilot\RDC Relay.exe'
 $oldMarker=Join-Path $root 'RDCRelayOwnerPilot\.startup-dispatch-v1'
 [IO.File]::Copy((Join-Path $prior 'RC1 Pilot Launcher.exe'),$old,$false)
 [IO.File]::WriteAllText($oldMarker,(Get-FileHash -LiteralPath $old).Hash.ToLowerInvariant(),[Text.Encoding]::ASCII)
 $oldCommand='"'+$old+'" --startup-dispatch'
 $key.SetValue('RDC Relay',$oldCommand)
 Check ((Call 'RegistrationState' @($key,$root)) -eq 1) 'legacy owned registration recognized'
 $newExe=Join-Path $root 'RDCRelayOwnerPilot\RDC Relay Startup.exe'
 $newMarker=Join-Path $root 'RDCRelayOwnerPilot\.startup-dispatch-v2'
 [IO.File]::Copy((Join-Path $release 'RDC Relay.exe'),$newExe,$false)
 [void](Call 'EnsureDispatcher' @($release,$root))
 Check (Call 'DispatcherOwned' @($root)) 'F3 exact interrupted dispatcher publication recovered'
 Check ([IO.File]::ReadAllText($newMarker) -ceq (Get-FileHash -LiteralPath $newExe).Hash.ToLowerInvariant()) 'F3 recovered marker binds exact dispatcher'
 [IO.File]::Delete($newMarker)
 [IO.File]::AppendAllText($newExe,'foreign')
 $foreign=(Get-FileHash -LiteralPath $newExe).Hash
 $refused=$false
 try{[void](Call 'EnsureDispatcher' @($release,$root))}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};$refused=$e.Message -ceq 'RC1_STARTUP_DISPATCHER_COLLISION'}
 Check ($refused -and (Get-FileHash -LiteralPath $newExe).Hash -ceq $foreign -and !(Test-Path -LiteralPath $newMarker)) 'F3 foreign orphan dispatcher refused and retained'
 [IO.File]::Delete($newExe)
 [void](Call 'EnsureDispatcher' @($release,$root))
 Check (Call 'DispatcherOwned' @($root)) 'new stable dispatcher created'
 [void](Call 'SetRegistration' @($key,$root,$true))
 $newCommand=Call 'Command' @($root)
 Check ($key.GetValue('RDC Relay') -ceq $newCommand -and $newCommand -ne $oldCommand) 'registration switches to new dispatcher'
 Check ((Get-FileHash -LiteralPath $old).Hash.ToLowerInvariant() -ceq [IO.File]::ReadAllText($oldMarker)) 'old dispatcher unchanged'
 [void](Call 'SetRegistration' @($key,$root,$false))
 Check ((Call 'RegistrationState' @($key,$root)) -eq 0) 'disabled state remains disabled'
 $key.SetValue('RDC Relay','foreign.exe')
 Check ((Call 'RegistrationState' @($key,$root)) -eq -1) 'foreign registration refused'
 [IO.File]::AppendAllText((Join-Path $release 'RDC Relay.exe'),'fixture tamper')
 Check (!(Call 'VerifiedRelease' @($release,$root))) 'tampered public launcher refused'
 'RDC_PUBLIC_STARTUP_PASS='+$pass+' FAIL=0'
}finally{
 if($key){$key.Dispose();[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sub,$false)}
 if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
