# Read-only schema and parity validation for editorial preview resources.
# Never loads these DRAFT files into RDC Relay runtime.
param([string]$Folder = $PSScriptRoot)
$ErrorActionPreference='Stop'
$ru=Get-Content -LiteralPath (Join-Path $Folder 'ru-RU.preview.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$en=Get-Content -LiteralPath (Join-Path $Folder 'en-US.preview.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($ru.schema -cne 'rdc-relay-editorial-preview-v1' -or $en.schema -cne $ru.schema){throw 'BAD_PREVIEW_SCHEMA'}
if($ru.locale -cne 'ru-RU' -or $en.locale -cne 'en-US'){throw 'LOCALE_MISMATCH'}
if($ru.status -cne 'DRAFT_NOT_RUNTIME' -or $en.status -cne 'DRAFT_NOT_RUNTIME'){throw 'UNSAFE_RUNTIME_STATUS'}
$rKeys=@($ru.strings.PSObject.Properties.Name | Sort-Object)
$eKeys=@($en.strings.PSObject.Properties.Name | Sort-Object)
if($rKeys.Count -lt 40 -or [string]::Join('|',$rKeys) -cne [string]::Join('|',$eKeys)){throw 'PREVIEW_KEYS_MISMATCH'}
foreach($key in $rKeys){
 if($key -cnotmatch '^[a-z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$' -or $key -match '^TXT-'){throw ('INVALID_SEMANTIC_KEY '+$key)}
 $r=[string]$ru.strings.$key
 $e=[string]$en.strings.$key
 if([string]::IsNullOrWhiteSpace($r) -or [string]::IsNullOrWhiteSpace($e)){throw ('EMPTY_RESOURCE '+$key)}
 $rArgs=@([regex]::Matches($r,'\{[a-zA-Z][a-zA-Z0-9_]*\}') | ForEach-Object {$_.Value} | Sort-Object)
 $eArgs=@([regex]::Matches($e,'\{[a-zA-Z][a-zA-Z0-9_]*\}') | ForEach-Object {$_.Value} | Sort-Object)
 if([string]::Join('|',$rArgs) -cne [string]::Join('|',$eArgs)){throw ('TEMPLATE_ARGS_MISMATCH '+$key)}
 if($r.StartsWith(' ') -ne $e.StartsWith(' ') -or $r.EndsWith(' ') -ne $e.EndsWith(' ')){throw ('EDGE_SPACE_MISMATCH '+$key)}
}
$templates=@($rKeys | Where-Object {$ru.strings.$_ -match '\{[a-zA-Z][a-zA-Z0-9_]*\}'})
$add=Get-Content -LiteralPath (Join-Path $Folder 'COVERAGE_ADDENDUM_KEYS.preview.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($add.status -cne 'DRAFT_NOT_RUNTIME' -or @($add.entries).Count -ne 30){throw 'BAD_ADDENDUM_COUNT_OR_STATUS'}
$addKeys=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$projectRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Folder))
foreach($entry in @($add.entries)){
 $key=[string]$entry.key
 if(-not $addKeys.Add($key)){throw ('DUPLICATE_ADDENDUM_KEY '+$key)}
 if($key -cnotmatch '^[a-z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$'){throw ('INVALID_ADDENDUM_KEY '+$key)}
 if(-not ($rKeys -ccontains $key)){throw ('ADDENDUM_KEY_NOT_MERGED '+$key)}
 if([string]$ru.strings.$key -cne [string]$entry.'ru-RU' -or [string]$en.strings.$key -cne [string]$entry.'en-US'){throw ('ADDENDUM_VALUE_DIFFERENCE '+$key)}
 if(-not (Test-Path -LiteralPath (Join-Path $projectRoot ([string]$entry.source)))){throw ('ADDENDUM_SOURCE_NOT_FOUND '+$key)}
}
Write-Output ('PASS resources: '+$rKeys.Count+' semantic keys, ru-RU/en-US parity, '+$templates.Count+' parameterized templates')
Write-Output ('PASS coverage addendum: '+$addKeys.Count+' manually sourced candidate keys')
Write-Output 'PASS DRAFT_NOT_RUNTIME enforced; no live software or installed files accessed'
