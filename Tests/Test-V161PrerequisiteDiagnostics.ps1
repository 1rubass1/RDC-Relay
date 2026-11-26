# Synthetic fixtures only; never invokes Node, npm, npx, Setup or real Remote.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$raw=[IO.File]::ReadAllText((Join-Path $repo 'Source\RdcOwnerRuntime.cs'))
$a=$raw.IndexOf('public static class RdcOwnerPrerequisiteDiagnostics {',[StringComparison]::Ordinal)
$b=$raw.IndexOf('public sealed class RdcOwnerRuntime : IDisposable {',$a,[StringComparison]::Ordinal)
if($a -lt 0 -or $b -le $a){throw 'DIAGNOSTICS_SOURCE_BOUNDARY'}
Add-Type -TypeDefinition ('using System; using System.IO; using System.Diagnostics;'+$raw.Substring($a,$b-$a))
$root=Join-Path ([IO.Path]::GetTempPath()) ('RDC-V161-PREQ-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$pass=0
function Check([bool]$condition,[string]$name){if(-not $condition){throw ('FAIL '+$name)};$script:pass++;Write-Output ('PASS '+$name)}
$allow=[Action[string]]{param($path)}
$deny=[Action[string]]{param($path)throw [UnauthorizedAccessException]::new('synthetic')}
try{
 $node=Join-Path $root 'node.exe'
 $npm=Join-Path $root 'npm.cmd'
 $npx=Join-Path $root 'npx.cmd'
 $bin=Join-Path $root 'node_modules\npm\bin'
 $lines=[RdcOwnerPrerequisiteDiagnostics]::Observe($root,'Fixture',$allow)
 Check ($lines[0] -ceq 'runtime Fixture: node=missing npm=missing npx=missing') 'missing Node/npm/npx explicit'
 Check ($lines[1] -ceq 'runtime Fixture: npm-cli=missing npx-cli=missing') 'missing CLI entrypoints explicit'
 Check ([RdcOwnerPrerequisiteDiagnostics]::FileState($node,$deny) -ceq 'unknown') 'denied inspection not reported missing'
 [void][IO.Directory]::CreateDirectory($npx)
 Check ([RdcOwnerPrerequisiteDiagnostics]::FileState($npx,$allow) -ceq 'not_file') 'directory cannot be called executable'
 [IO.Directory]::Delete($npx)
 [IO.File]::WriteAllText($npx,'DO NOT EXECUTE')
 [IO.File]::WriteAllText($npm,'DO NOT EXECUTE')
 [void][IO.Directory]::CreateDirectory($bin)
 [IO.File]::WriteAllText((Join-Path $bin 'npm-cli.js'),'DO NOT EXECUTE')
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 function MakeNode([string]$version){
  $fixture=Join-Path $root 'fixture.cs'
  [IO.File]::WriteAllText($fixture,('[assembly:System.Reflection.AssemblyFileVersion("'+$version+'")] class Fixture {static void Main(){throw new System.Exception("DO NOT EXECUTE");}}'))
  $o=@(& $compiler /nologo /target:exe "/out:$node" $fixture 2>&1)
  if($LASTEXITCODE -ne 0){throw ('fixture compile failed '+($o -join ' '))}
 }
 MakeNode '22.11.0.0'
 Check ([RdcOwnerPrerequisiteDiagnostics]::NodeState($node,$allow) -ceq 'unsupported(22.11.0.0)') 'old Node reported with version'
 MakeNode '22.12.0.0'
 Check ([RdcOwnerPrerequisiteDiagnostics]::NodeState($node,$allow) -ceq 'present(22.12.0.0)') 'supported Node metadata'
 $lines=[RdcOwnerPrerequisiteDiagnostics]::Observe($root,'Fixture',$allow)
 Check ($lines[0] -ceq 'runtime Fixture: node=present(22.12.0.0) npm=present npx=present') 'component presence independent of missing CLI'
 Check ($lines[1] -ceq 'runtime Fixture: npm-cli=present npx-cli=missing') 'incomplete npm tree explicitly reported'
 Check (-not (($lines -join ' ').Contains($root)) -and @($lines|Where-Object {$_.Length -gt 120}).Count -eq 0) 'sanitized bounded event'
 [IO.File]::WriteAllText((Join-Path $bin 'npx-cli.js'),'DO NOT EXECUTE')
 Check (([RdcOwnerPrerequisiteDiagnostics]::Observe($root,'Fixture',$allow))[1] -ceq 'runtime Fixture: npm-cli=present npx-cli=present') 'both CLI files present'
 Check ($raw.Contains('RdcOwnerPrerequisiteDiagnostics.Observe(Path.GetDirectoryName(file),locations[i],CheckPath)') -and $raw.Contains('if(!File.Exists(file))continue;') -and $raw.Contains('throw new FileNotFoundException("RC1_PINNED_NPX_MISSING")')) 'observations integrated without removing existing launch gate'
}finally{
 if([IO.Path]::GetFileName($root) -cnotmatch '^RDC-V161-PREQ-[a-f0-9]{32}$'){throw 'cleanup scope'}
 # Only the fixture-owned, known paths created above; never traverse arbitrary trees.
 foreach($p in @((Join-Path $bin 'npm-cli.js'),(Join-Path $bin 'npx-cli.js'),$node,$npm,$npx,(Join-Path $root 'fixture.cs'))){if([IO.File]::Exists($p)){[IO.File]::Delete($p)}}
 foreach($p in @($npx,$bin,(Join-Path $root 'node_modules\npm'),(Join-Path $root 'node_modules'),$root)){if([IO.Directory]::Exists($p) -and [IO.Directory]::GetFileSystemEntries($p).Length -eq 0){[IO.Directory]::Delete($p,$false)}}
}
Write-Output ('RDC_V161_PREREQUISITE_DIAGNOSTICS_PASS='+$pass)
