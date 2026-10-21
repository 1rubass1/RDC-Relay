param([string]$PortableZip)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$dev = Join-Path $repo 'docs\dev'
$allowedMax = 300
$files = @(Get-ChildItem -LiteralPath $dev -Recurse -File | Where-Object { $_.Extension -in @('.md','.pen') })
if ($files.Count -gt $allowedMax) { throw "Unexpected dev file count ($($files.Count)); narrow audit" }
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$patterns = [ordered]@{
 'active-tunnel-id' = '(?<![A-Za-z0-9])tunnel_[A-Za-z0-9_-]{12,}'
 'token' = '(?i)\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{18,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'
 'email' = '[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
 'jwt' = '\beyJ[A-Za-z0-9_-]{25,}\.[A-Za-z0-9_-]{25,}'
}
$counter = 0
foreach($file in $files){
  $text = $utf8.GetString([IO.File]::ReadAllBytes($file.FullName))
  foreach($p in $patterns.GetEnumerator()){
    if([regex]::IsMatch($text, [string]$p.Value)){throw "Possible secret in $($file.Name): $($p.Key)"}
  }
  $counter++
}
$bad = '^(?:AGENTS\.md|PROJECT_(?:INDEX|CONTEXT)\.md|DECISIONS\.md|COORDINATION/|docs/dev/)'
foreach($branch in @('main','stable')){
  $lines = @(git -C $repo ls-tree -r --name-only $branch)
  if($LASTEXITCODE -ne 0){throw "Cannot inspect $branch"}
  foreach($line in $lines) { if($line -match $bad){throw "DEV-ONLY PATH IS IN $branch : $line"} }
}
$builder=[IO.File]::ReadAllText((Join-Path $repo 'Scripts\build-release.ps1'))
if($builder -notmatch '\$manifestPayload\s*=\s*@\(' -or $builder -notmatch 'foreach \(\$name in \(\$manifestPayload \+ .update-manifest.json.\)\)'){throw 'Current packaging no longer has expected explicit allowlists; review required'}
if($builder -match '(?i)docs[/\\]dev|COORDINATION|PROJECT_INDEX|PROJECT_CONTEXT|AGENTS\.md|DECISIONS\.md'){throw 'Build script mentions dev-only path'}
$zipState = 'NOT CHECKED (no ZIP supplied)'
if($PortableZip){
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PortableZip).Path)
 try{
  foreach($e in $zip.Entries){
   if($e.FullName -match '(?i)(?:^|[/\\])(?:docs|COORDINATION)(?:[/\\])|\.md$|\.pen$'){
     throw "Dev-looking file in Portable ZIP: $($e.FullName)"
   }
  }
  $zipState = "PASS ($($zip.Entries.Count) entries)"
 }finally{ $zip.Dispose() }
}
Write-Output "PASS: $counter dev text/design files scanned; main/stable exclude dev-only paths; packager explicit allowlists confirmed; Portable ZIP: $zipState"
