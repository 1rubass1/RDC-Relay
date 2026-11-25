# Development-only RDC Relay string index. Never executes source or modifies the app.
# This is a candidate index, not the live RU/EN translation dictionary.
# -Current updates/checks the 2026-11-18 source snapshot without overwriting
# the original 360-candidate Excel's historical STRING_INVENTORY.csv references.
param([switch]$Check,[switch]$Current)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$out=Join-Path $PSScriptRoot $(if($Current){'STRING_INVENTORY_CURRENT.csv'}else{'STRING_INVENTORY.csv'})
$files=@(Get-ChildItem -LiteralPath (Join-Path $repo 'Source') -File -ErrorAction Stop |
 Where-Object {$_.Extension -in @('.ps1','.cs')})
$files+=@(Get-ChildItem -LiteralPath (Join-Path $repo 'Installer') -File -ErrorAction Stop |
 Where-Object {$_.Extension -eq '.cs' -and -not $_.Name.EndsWith('.Generated.cs',[StringComparison]::OrdinalIgnoreCase)})
$files=@($files | Sort-Object FullName)
function Area([string]$name){
 switch -Regex ($name){
  '^Source/remote-window.ps1$' {return 'legacy.gui'}
  '^Source/rc1-owner-gui.ps1$' {return 'owner.gui'}
  '^Source/RdcOwnerRuntime.cs$' {return 'owner.tray-host'}
  '^Source/(rc1-.*|RdcOwner.*)\.(ps1|cs)$' {return 'owner.internal'}
  '^Source/update-notice.ps1$' {return 'shared.update-notice'}
  '^Source/update.ps1$' {return 'legacy.updater'}
  '^Installer/RdcRelease(PathDialog|MaintenanceDialog|MaintenancePolicy)\.cs$' {return 'release.installer-draft'}
  '^Installer/Rc1.*\.cs$' {return 'rc1.pilot-installer'}
  '^Installer/' {return 'legacy.installer'}
  default {return 'shared'}
 }
}
function Redact([string]$v){
 if($v -match '(?i)(Bearer\s+[A-Za-z0-9._~+/-]{16,}|gh[pousr]_[A-Za-z0-9]{15,}|sk-[A-Za-z0-9]{16,}|https?://[^/\s]+:[^@\s]+@)'){return '[REDACTED_LITERAL]'}
 return $v
}
function Classify([string]$value,[string]$line,[string]$area){
 if($value -ceq '[REDACTED_LITERAL]'){return 'REDACTED_NEVER_TRANSLATE'}
 if($value -match '[\u0400-\u04FF]'){return 'REVIEW_TRANSLATION'}
 if($line -match '(?i)(ToolTip|Accessible(Name|Description)|MessageBox\.Show|Button|Label|\.Text\s*=|Text\s*=|\.Title\s*=|Set-State|Add-CompletedEvent|ToolStripMenuItem|SetToolTip)'){
  if($value -match '[A-Za-z]{2}'){return 'REVIEW_ENGLISH_UI'}
 }
 if($area -eq 'owner.gui' -and $value -match '^[A-Za-z][A-Za-z ]{7,}$'){return 'REVIEW_ENGLISH_UI'}
 return 'PRESERVE_PROTOCOL_OR_TECHNICAL'
}
$raw=New-Object 'System.Collections.Generic.List[object]'
function Add-CSharpTokens([string]$text,[string[]]$outerLines,[string]$path,[string]$area,[int]$baseLine){
 # C# lexical sweep: comments and CHAR LITERALS win over string tokens.
 # This correctly handles C# embedded inside PowerShell here-strings.
 $pattern='(?s:/\*.*?\*/)|//[^\r\n]*|''(?:\\.|[^''\\])*''|(?:\$@|@\$|@)"(?:[^"]|"")*"|\$?"(?:\\.|[^"\\])*"'
 $matches=[regex]::Matches($text,$pattern)
 $line=1;$offset=0
 foreach($m in $matches){
  $line+=([regex]::Matches($text.Substring($offset,$m.Index-$offset),'\n')).Count
  $sourceLine=$baseLine+$line-1
  $line+=([regex]::Matches($m.Value,'\n')).Count
  $offset=$m.Index+$m.Length
  if($m.Value.StartsWith('//') -or $m.Value.StartsWith('/*') -or $m.Value.StartsWith("'")){continue}
  $v=[string]$m.Value
  $q=$v.IndexOf('"')
  if($q -lt 0 -or $v.Length -lt $q+2){continue}
  $v=$v.Substring($q+1,$v.Length-$q-2)
  if($m.Value.StartsWith('@') -or $m.Value.StartsWith('$@') -or $m.Value.StartsWith('@$')){
   $v=$v.Replace('""','"')
  }
  $v=Redact $v
  if([string]::IsNullOrWhiteSpace($v)){continue}
  $v=$v.Replace([string][char]13,'\r').Replace([string][char]10,'\n')
  if($v.Length -gt 6000){throw ('UNEXPECTED_CSHARP_STRING_TOO_LONG '+$path+' '+$sourceLine)}
  $ctx=if($sourceLine -ge 1 -and $sourceLine -le $outerLines.Count){[string]$outerLines[$sourceLine-1]}else{''}
  $raw.Add([pscustomobject]@{Source=$path;Area=$area;Line=$sourceLine;Literal=$v;
   Hint=(Classify $v $ctx $area);Dynamic=($ctx -match '\$|\+')})
 }
}
$errorsFound=0
foreach($file in $files){
 $relative=($file.FullName.Substring($repo.Length+1) -replace '\\','/')
 $area=Area $relative
 $source=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
 $lines=[regex]::Split($source,'\r?\n')
 if($file.Extension -eq '.ps1'){
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count -ne 0){$errorsFound+=$errors.Count;continue}
  foreach($token in $tokens){
   if($token.Kind -notin @('StringLiteral','StringExpandable','HereStringLiteral','HereStringExpandable')){continue}
   $lineNumber=[int]$token.Extent.StartLineNumber
   $literal=[string]$token.Value
   if($token.Kind -in @('HereStringLiteral','HereStringExpandable') -and
      $literal.Length -gt 1000 -and $literal -match 'using System;'){
    Add-CSharpTokens $literal $lines $relative $area $lineNumber
    continue
   }
   $value=Redact $literal
   if([string]::IsNullOrWhiteSpace($value)){continue}
   if($value.Length -gt 6000){throw ('UNEXPECTED_PS_STRING_TOO_LONG '+$relative+' '+$lineNumber)}
   $value=$value.Replace([string][char]13,'\r').Replace([string][char]10,'\n')
   $ctx=if($lineNumber -ge 1 -and $lineNumber -le $lines.Count){[string]$lines[$lineNumber-1]}else{''}
   $raw.Add([pscustomobject]@{Source=$relative;Area=$area;Line=$lineNumber;Literal=$value;
    Hint=(Classify $value $ctx $area);Dynamic=($ctx -match '\$|\+')})
  }
 }else{
  Add-CSharpTokens $source $lines $relative $area 1
 }
}
if($errorsFound -gt 0){throw ('POWERSHELL_SOURCE_PARSE_ERRORS='+$errorsFound)}
$grouped=@($raw|Group-Object -Property Source,Literal)
$rows=New-Object 'System.Collections.Generic.List[object]'
$hasher=[Security.Cryptography.SHA256]::Create()
try {
 foreach($g in $grouped){
  $first=$g.Group|Sort-Object Line|Select-Object -First 1
  $lines=@($g.Group | Select-Object -ExpandProperty Line -Unique | Sort-Object)
  $dig=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes(
    $first.Source+[char]0+$first.Literal)))).Replace('-','').Substring(0,16).ToLowerInvariant()
  $hints=@($g.Group|Select-Object -ExpandProperty Hint -Unique)
  $hint=if($hints -contains 'REDACTED_NEVER_TRANSLATE'){'REDACTED_NEVER_TRANSLATE'}
   elseif($hints -contains 'REVIEW_TRANSLATION'){'REVIEW_TRANSLATION'}
   elseif($hints -contains 'REVIEW_ENGLISH_UI'){'REVIEW_ENGLISH_UI'}
   else{'PRESERVE_PROTOCOL_OR_TECHNICAL'}
  $locale=if($first.Literal -match '[\u0400-\u04FF]'){'ru-RU'}
   elseif($first.Literal -match '[A-Za-z]'){'en/neutral'}else{'neutral'}
  $rows.Add([pscustomobject][ordered]@{
   CandidateId=('TXT-'+$dig);Area=$first.Area;Source=$first.Source;
   Lines=($lines -join ';');Occurrences=$g.Count;LocaleHint=$locale;
   ReviewStatus=$hint;
   FragmentOrTemplate=(@($g.Group|Where-Object{$_.Dynamic}).Count -gt 0);
   Literal=$first.Literal
  })
 }
}finally{$hasher.Dispose()}
$ordered=@($rows | Sort-Object Area,Source,CandidateId)
if($ordered.Count -lt 100){throw ('TOO_FEW_STRINGS '+$ordered.Count)}
$csv=($ordered | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
$csv+=[Environment]::NewLine
if($Check){
 if(-not [IO.File]::Exists($out)){throw 'INVENTORY_NOT_FOUND'}
 if([IO.File]::ReadAllText($out,[Text.Encoding]::UTF8) -cne $csv){throw 'INVENTORY_STALE'}
}else{
 [IO.File]::WriteAllText($out,$csv,(New-Object Text.UTF8Encoding($false)))
}
Write-Output ('SOURCE_FILES='+$files.Count)
Write-Output ('LITERAL_OCCURRENCES='+$raw.Count)
Write-Output ('UNIQUE_LITERAL_CANDIDATES='+$ordered.Count)
foreach($kind in @('REVIEW_TRANSLATION','REVIEW_ENGLISH_UI','PRESERVE_PROTOCOL_OR_TECHNICAL','REDACTED_NEVER_TRANSLATE')){
 Write-Output ('STATUS_'+$kind+'='+@($ordered|Where-Object{$_.ReviewStatus -eq $kind}).Count)
}
Write-Output ('RESULT='+$(if($Check){'INVENTORY_REPRODUCIBLE_PASS'}else{'INVENTORY_GENERATED_PASS'}))
