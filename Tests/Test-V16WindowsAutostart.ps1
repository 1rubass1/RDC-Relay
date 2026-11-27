# Exercise exact native registration against a unique synthetic registry key.
# No actual Run key, installed launcher, Explorer, Host or Remote is changed.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Add-Type -Path @((Join-Path $repo 'Source\RdcOwnerStartup.cs'),(Join-Path $repo 'Installer\Rc1CandidateLauncher.cs'),(Join-Path $repo 'Installer\RdcNodePrerequisite.cs')) -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Windows.Forms.dll','System.Drawing.dll') -PassThru | Out-Null
$id=[Guid]::NewGuid().ToString('N')
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-STARTUP-TEST-'+$id)
$keyName='Software\RDC-Startup-Test-'+$id
$key=$null;$pass=0
function Check([bool]$ok,[string]$label){if(-not $ok){throw ('FAIL '+$label)};$script:pass++;Write-Output ('PASS '+$label)}
function Denied([scriptblock]$operation,[string]$label){$blocked=$false;try{& $operation}catch{$blocked=$true};Check $blocked $label}
function New-Release([string]$bytes){
 $releases=Join-Path $root 'RDCRelayOwnerPilot\1.6.0-RC1\releases'
 $stage=Join-Path $releases ('fixture-'+[Guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($stage)
 $exe=Join-Path $stage 'RC1 Pilot Launcher.exe'
 [IO.File]::WriteAllText($exe,$bytes)
 $manifest=Join-Path $stage 'owner-source-manifest.json'
 $row=[ordered]@{name='RC1 Pilot Launcher.exe';sha256=(Get-FileHash $exe -Algorithm SHA256).Hash}
 $data=[ordered]@{candidate='1.6.0 RC1';kind='PRIVATE_FULL_RC1';ownerMode='FULL_HOST_GUI_RC1';installable=$true;publishable=$false;files=@($row)}
 [IO.File]::WriteAllText($manifest,($data|ConvertTo-Json -Depth 6))
 $name='rc1-'+(Get-FileHash $manifest -Algorithm SHA256).Hash.Substring(0,24).ToLowerInvariant()
 $release=Join-Path $releases $name
 [IO.Directory]::Move($stage,$release)
 return $release
}
try{
 [void][IO.Directory]::CreateDirectory($root)
 $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($keyName)
 Check ([RdcOwnerStartup]::RegistrationState($key,$root) -eq 0) 'empty registry has no registration before Setup initialization'
 $one=New-Release 'fixture version one'
 $two=New-Release 'fixture version two'
 Check ([RdcOwnerStartup]::VerifiedRelease($one,$root)) 'immutable installed release with matching launcher is eligible'
 Check (-not [RdcOwnerStartup]::VerifiedRelease((Split-Path $one -Parent),$root)) 'portable or nonrelease path refused'
 Denied {[RdcOwnerStartup]::SetRegistration($key,$root,$true)} 'enable requires verified stable dispatcher'
 [RdcOwnerStartup]::InitializeFreshRegistration($key,$one,$root)
 Check ([RdcOwnerStartup]::DispatcherOwned($root)) 'stable dispatcher verified against durable ownership hash'
 Check ([RdcOwnerStartup]::RegistrationState($key,$root) -eq 1) 'fresh Setup initializes Windows startup ON'
 [RdcOwnerStartup]::SetRegistration($key,$root,$true)
 $command=$key.GetValue('RDC Relay')
 Check ([RdcOwnerStartup]::RegistrationState($key,$root) -eq 1 -and $command -ceq [RdcOwnerStartup]::Command($root)) 'single native startup entry has fixed stable executable and dispatch argument'
 $stable=[RdcOwnerStartup]::DispatcherPath($root)
 $hash=(Get-FileHash $stable).Hash
 [RdcOwnerStartup]::EnsureDispatcher($two,$root)
 Check ((Get-FileHash $stable).Hash -ceq $hash -and $key.GetValue('RDC Relay') -ceq $command) 'new release preserves dispatcher bytes and registration'
 [RdcOwnerStartup]::SetRegistration($key,$root,$false)
 Check ([RdcOwnerStartup]::RegistrationState($key,$root) -eq 0) 'disable removes only owned registration'
 $key.SetValue('RDC Relay','foreign command')
 Denied {[RdcOwnerStartup]::SetRegistration($key,$root,$true)} 'foreign startup command cannot be overwritten'
 Denied {[RdcOwnerStartup]::SetRegistration($key,$root,$false)} 'foreign startup command cannot be removed'
 Check ($key.GetValue('RDC Relay') -ceq 'foreign command') 'foreign entry preserved'
 $key.DeleteValue('RDC Relay')
 [IO.File]::AppendAllText($stable,'unexpected alteration')
 Check (-not [RdcOwnerStartup]::DispatcherOwned($root)) 'altered dispatcher fails verification'
 Denied {[RdcOwnerStartup]::EnsureDispatcher($two,$root)} 'altered stable dispatcher is not overwritten'
 [IO.File]::AppendAllText((Join-Path $two 'RC1 Pilot Launcher.exe'),'unexpected alteration')
 Check (-not [RdcOwnerStartup]::VerifiedRelease($two,$root)) 'altered installed candidate fails validation'
 $type=[RdcOwnerStartup].Assembly.GetType('RdcRc1CandidateLauncher')
 $flags=[Reflection.BindingFlags]'Static,NonPublic'
 function Mode($name,[string[]]$items){$arr=New-Object object[] 1;$arr[0]=$items;[bool]$type.GetMethod($name,$flags).Invoke($null,$arr)}
 Check ((Mode BackgroundRequested @('--background')) -and -not (Mode FullLaunchRequested @('--background'))) 'background route separate from full GUI route'
 Check ((Mode DispatchRequested @('--startup-dispatch')) -and -not (Mode DispatchRequested @('--startup-dispatch','extra'))) 'dispatcher exact argument contract'
 $hostSource=[IO.File]::ReadAllText((Join-Path $repo 'Source\RdcOwnerRuntime.cs'))
 $scriptSource=[IO.File]::ReadAllText((Join-Path $repo 'Source\rc1-tray-host.ps1'))
 Check ($hostSource.Contains('!guiAuthenticated||guiState!="CONNECTED"') -and $scriptSource.Contains('if(-not $Background){') -and $scriptSource.Contains('[RdcOwnerStartup]::IsActiveSource($root)')) 'background skips initial GUI and retains authenticated GUI gate for Remote'
}finally{
 if($key){$key.Dispose()}
 if($keyName -cmatch '^Software\\RDC-Startup-Test-[a-f0-9]{32}$'){[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($keyName,$false)}
 if([IO.Directory]::Exists($root) -and [IO.Path]::GetFileName($root) -cmatch '^RDC-STARTUP-TEST-[a-f0-9]{32}$'){
  $entries=@(Get-ChildItem -LiteralPath $root -Recurse -Force)
  foreach($e in $entries){if($e.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'STARTUP_FIXTURE_REPARSE'}}
  [IO.Directory]::Delete($root,$true)
 }
}
Write-Output ('RDC_STARTUP_PASS='+$pass+' FAIL=0')
