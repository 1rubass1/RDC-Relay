# Compile the real private Setup and exercise only its read-only prerequisite policy.
# No real Node installer, download, process, current PATH/registry or installed client is used.
$ErrorActionPreference='Stop'
$r=Split-Path -Parent $PSScriptRoot
$setup=Join-Path $r 'Installer\Rc1CandidateSetup.cs'
$raw=[IO.File]::ReadAllText($setup,[Text.Encoding]::UTF8)
$shared=Join-Path $r 'Installer\RdcNodePrerequisite.cs'
$nodeRaw=[IO.File]::ReadAllText($shared,[Text.Encoding]::UTF8)
$pass=0;$fail=0
function Check([bool]$ok,[string]$label){if($ok){$script:pass++;Write-Output ('PASS '+$label)}else{$script:fail++;Write-Output ('FAIL '+$label)}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-NodePolicyTest-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 if(-not [IO.File]::Exists($compiler)){throw 'NODE_TEST_CSC_REQUIRED'}
 $dll=Join-Path $root 'Setup.dll'
 $output=@(& $compiler /nologo /target:library /define:RDC_RC1_FULL_SETUP "/out:$dll" /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Management.dll /reference:System.Windows.Forms.dll $setup $shared (Join-Path $r 'Installer\Rc1ManualUpgrade.cs') (Join-Path $r 'Source\RdcOwnerStartup.cs') (Join-Path $r 'Source\RdcUiLanguage.cs') 2>&1)
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($dll)){throw ('NODE_SETUP_COMPILE_FAILED '+($output -join ' '))}
 Check $true 'actual full private Setup with prerequisite installer compiles'
 Check ($raw.Contains('bool freshDefaults=args.Length==0&&!registered&&!priorShortcut&&') -and $raw.Contains('!Directory.Exists(priorPilotRoot)&&!File.Exists(priorPilotRoot)') -and $raw.Contains('if(freshDefaults&&result=="CREATED")')) 'defaults only for fresh installed Setup, not repair or upgrade'
 $init=$raw.IndexOf('RdcOwnerAutoConnectPreference.InitializeDisabled(RdcOwnerAutoConnectPreference.CurrentPath)')
 $register=$raw.IndexOf('RdcOwnerStartup.InitializeFreshInstalled(Path.Combine(release,"Source"))')
 $start=$raw.IndexOf('StartPrivateFull(release);',$init)
 Check ($init -gt 0 -and $register -gt $init -and $start -gt $register) 'Remote auto-connect OFF and Windows autostart ON before first GUI launch'
 $asm=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
 $type=$asm.GetType('RdcRc1CandidateSetup',$true)
 $flags=[Reflection.BindingFlags]'Static,Public,NonPublic'
 $classify=$type.GetMethod('ClassifyNodePrerequisite',$flags)
 $supported=$type.GetMethod('SupportedNodeVersion',$flags)
 function IsSupported([int]$major,[int]$minor){return [bool]$supported.Invoke($null,[object[]]@($major,$minor))}
 Check ((IsSupported 22 12) -and (IsSupported 24 0) -and (IsSupported 26 0)) 'supported Node 22.12+ including reviewed LTS majors'
 Check (-not (IsSupported 22 11) -and -not (IsSupported 18 20) -and -not (IsSupported 20 19)) 'old Node versions do not qualify as verified prerequisites'
 $one=Join-Path $root 'first';$two=Join-Path $root 'second'
 [void][IO.Directory]::CreateDirectory($one);[void][IO.Directory]::CreateDirectory($two)
 function State([string[]]$dirs){$a=New-Object 'object[]' 1;$a[0]=$dirs;return [string]$classify.Invoke($null,$a)}
 Check ((State @($one,$two)) -ceq 'MISSING') 'clean Windows missing Node/npm/npx is installable case'
 [IO.File]::WriteAllText((Join-Path $one 'npx.cmd'),'FAKE-NPX-DO-NOT-EXECUTE')
 Check ((State @($one,$two)) -ceq 'INCOMPLETE') 'orphan shim never authorizes replacing shared runtime'
 function Fixture([string]$dir,[string]$version){
  $cs=Join-Path $root ('fixture-'+[Guid]::NewGuid().ToString('N')+'.cs')
  [IO.File]::WriteAllText($cs,('[assembly:System.Reflection.AssemblyFileVersion("'+$version+'")] class FakeNode {static void Main(){throw new System.Exception("TEST MUST NOT EXECUTE");}}'))
  $node=Join-Path $dir 'node.exe'
  $o=@(& $compiler /nologo /target:exe "/out:$node" $cs 2>&1)
  if($LASTEXITCODE -ne 0){throw ('NODE_FIXTURE_COMPILE '+($o -join ' '))}
  [IO.File]::WriteAllText((Join-Path $dir 'npx.cmd'),'FAKE')
  [IO.File]::WriteAllText((Join-Path $dir 'npm.cmd'),'FAKE')
  $bin=Join-Path $dir 'node_modules\npm\bin'
  [void][IO.Directory]::CreateDirectory($bin)
  [IO.File]::WriteAllText((Join-Path $bin 'npx-cli.js'),'FAKE')
  [IO.File]::WriteAllText((Join-Path $bin 'npm-cli.js'),'FAKE')
 }
 Fixture $two '24.22.3.0'
 Check ((State @($two)) -ceq 'READY') 'complete supported runtime is reused without installation'
 Check ((State @($one,$two)) -ceq 'INCOMPLETE') 'broken earlier shim cannot accidentally select another Node'
 [IO.File]::Delete((Join-Path $one 'npx.cmd'))
 Check ((State @($one,$two)) -ceq 'READY') 'complete later runtime is correctly detected'
 Fixture $one '18.20.8.0'
 Check ((State @($one,$two)) -ceq 'EXISTING_UNSUPPORTED') 'existing obsolete Node is not silently upgraded'
 $url=$type.GetField('NodeMsiUrl',$flags).GetRawConstantValue()
 $hash=$type.GetField('NodeMsiSha256',$flags).GetRawConstantValue()
 Check ($url -ceq 'https://nodejs.org/dist/v24.22.3/node-v24.22.3-x64.msi' -and $hash -ceq '4A1AB5BDEC5434BAE58EFAE6C3E5077A011F6F1E76D2B47B7B10AF043F7DB545') 'exact official MSI URL and independently published SHA256 pinned'
 $consent=$nodeRaw.IndexOf('if(answer!=System.Windows.Forms.DialogResult.Yes)return false;',[StringComparison]::Ordinal)
 $download=$nodeRaw.IndexOf('DownloadPinnedNodeWithProgress(msi,en);',[StringComparison]::Ordinal)
 $execute=$nodeRaw.IndexOf('using(Process child=Process.Start(start)){',[StringComparison]::Ordinal)
 $hook=$raw.IndexOf('if(args.Length==0 && !EnsureNodePrerequisite(registered||priorShortcut))return 1;',[StringComparison]::Ordinal)
 $prepare=$raw.IndexOf('RdcRc1ManualUpgrade.Prepare(source,local,Required)',[StringComparison]::Ordinal)
 Check ($consent -gt 0 -and $consent -lt $download -and $download -lt $execute) 'download and Windows Installer occur only after explicit Yes'
 Check ($hook -gt 0 -and $hook -lt $prepare -and $raw.Contains('#if RDC_RC1_BLOCKED')) 'interactive prerequisite check precedes any product publication and blocked path stays inert'
 Check ($nodeRaw.Contains('request.AllowAutoRedirect=false') -and $nodeRaw.Contains('RC1_NODE_MSI_HASH_MISMATCH') -and $nodeRaw.Contains('SecurityProtocolType.Tls12') -and $nodeRaw.Contains('cancellation.Register(()=>request.Abort())')) 'download uses TLS, no redirects, hash pin and explicit cancellation'
 Check ($nodeRaw.Contains('/passive /norestart') -and $nodeRaw.Contains('start.Verb="runas"') -and $nodeRaw.Contains('if(child.ExitCode==3010)') -and $nodeRaw.Contains('if(ClassifyNodePrerequisite(roots)!="READY")')) 'MSI quiet progress, UAC, no reboot, strict postinstall verification'
 Check ($nodeRaw.Contains('if(state!="MISSING"||OtherNodeOnPath()||OtherNodeRegistered())') -and $nodeRaw.Contains('RC1_NODE_STATE_CHANGED') -and $nodeRaw.Contains('RegistryHive.LocalMachine,RegistryHive.CurrentUser')) 'never installs over detected or registered existing runtime and rechecks immediately before MSI'
 $hostSource=[IO.File]::ReadAllText((Join-Path $r 'Source\RdcOwnerRuntime.cs'))
 Check ($hostSource.Contains('Required Node.js runtime is missing; run RDC Relay Setup') -and $hostSource.Contains('return Error(requestId,"MANAGED_NODE_MISSING")') -and $hostSource.Contains('ResolvePinnedNpx();StopManagedRemote();StartManagedRemote();')) 'missing runtime diagnosed; reconnect preflights before stopping'
}finally{if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}}
Write-Output ('RDC_NODE_PREREQUISITE_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
