# Read-only development check for the local i18n editorial workbook.
# Does NOT execute app source, mutate installed software, or rewrite the CSV/XLSX.
param(
 [string]$WorkbookPath = (Join-Path $PSScriptRoot 'RDC_Relay_UI_Texts.xlsx'),
 [string]$InventoryPath = (Join-Path $PSScriptRoot 'STRING_INVENTORY.csv')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-Part([IO.Compression.ZipArchive]$zip,[string]$path) {
 $entry=$zip.GetEntry($path)
 if(-not $entry){throw ('XLSX_PART_MISSING '+$path)}
 $stream=$entry.Open()
 try{
  $xml=New-Object System.Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.Load($stream)
  return ,$xml
 }finally{$stream.Dispose()}
}
function Namespace([Xml.XmlDocument]$xml,[string]$prefix,[string]$url) {
 $manager=New-Object Xml.XmlNamespaceManager($xml.NameTable)
 $manager.AddNamespace($prefix,$url)
 return ,$manager
}
if(-not [IO.File]::Exists($WorkbookPath)){throw 'EDITORIAL_WORKBOOK_NOT_FOUND'}
if(-not [IO.File]::Exists($InventoryPath)){throw 'STRING_INVENTORY_NOT_FOUND'}
$inventory=@{}
foreach($entry in (Import-Csv -LiteralPath $InventoryPath -Encoding UTF8)){
 if($inventory.ContainsKey($entry.CandidateId)){throw 'INVENTORY_ID_DUPLICATE'}
 $inventory[$entry.CandidateId]=$entry
}
$zip=[IO.Compression.ZipFile]::OpenRead($WorkbookPath)
try{
 $sheetNs='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
 $officeRel='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
 $packageRel='http://schemas.openxmlformats.org/package/2006/relationships'
 $book=Read-Part $zip 'xl/workbook.xml'
 $bm=Namespace $book 's' $sheetNs
 $sheets=$book.SelectNodes('//s:sheet',$bm)
 if($sheets.Count -ne 3){throw ('WRONG_SHEET_COUNT '+$sheets.Count)}
 $wanted=$null
 foreach($item in $sheets){if($item.GetAttribute('name') -ceq 'Тексты'){$wanted=$item}}
 if(-not $wanted){throw 'TEXTS_SHEET_MISSING'}
 $relationId=$wanted.GetAttribute('id',$officeRel)
 $relationships=Read-Part $zip 'xl/_rels/workbook.xml.rels'
 $relation=$null
 foreach($item in $relationships.DocumentElement.ChildNodes){
  if($item.GetAttribute('Id') -ceq $relationId){$relation=$item;break}
 }
 if(-not $relation){throw 'SHEET_RELATIONSHIP_MISSING'}
 $target=$relation.GetAttribute('Target').TrimStart('/')
 if(-not $target.StartsWith('xl/',[StringComparison]::Ordinal)){$target='xl/'+$target}
 if($target -match '\.\.' -or $target -match '[\\:]'){throw 'UNEXPECTED_SHEET_PATH'}
 $sheet=Read-Part $zip $target
 $sm=Namespace $sheet 's' $sheetNs
 $sharedDoc=Read-Part $zip 'xl/sharedStrings.xml'
 $sharedManager=Namespace $sharedDoc 's' $sheetNs
 $shared=@($sharedDoc.SelectNodes('//s:sst/s:si',$sharedManager) | ForEach-Object {$_.InnerText})
 $byRow=@{}
 foreach($node in $sheet.SelectNodes('//s:sheetData/s:row',$sm)){
  $row=[int]$node.GetAttribute('r')
  if($row -lt 6 -or $row -gt 365){continue}
  $cells=@{}
  foreach($cell in $node.SelectNodes('s:c',$sm)){
   $address=$cell.GetAttribute('r')
   $column=[regex]::Match($address,'^[A-Z]+').Value
   if($column -notin @('A','B','C','D','E','F','G','H','I')){continue}
   $valueNode=$cell.SelectSingleNode('s:v',$sm)
   if($cell.GetAttribute('t') -ceq 's' -and $valueNode){
    $index=[int]$valueNode.InnerText
    if($index -lt 0 -or $index -ge $shared.Count){throw ('BAD_SHARED_INDEX '+$address)}
    $cells[$column]=[string]$shared[$index]
   }elseif($cell.GetAttribute('t') -ceq 'inlineStr'){
    $inline=$cell.SelectSingleNode('s:is',$sm)
    $cells[$column]=if($inline){[string]$inline.InnerText}else{''}
   }elseif($valueNode){$cells[$column]=[string]$valueNode.InnerText}
  }
  $byRow[$row]=$cells
 }
 $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
 $areaCounts=@{}
 $errors=New-Object 'System.Collections.Generic.List[string]'
 for($i=6;$i -le 365;$i++){
  if(-not $byRow.ContainsKey($i)){$errors.Add('MISSING_ROW '+$i);continue}
  $v=$byRow[$i]
  $id=[string]$v['G'];$ru=[string]$v['C'];$en=[string]$v['D']
  $source=[string]$v['H'];$area=[string]$v['A']
  if($id -cnotmatch '^TXT-[0-9a-f]{16}$' -or -not $ids.Add($id)){$errors.Add('BAD_OR_DUPLICATE_ID '+$i)}
  if(-not $inventory.ContainsKey($id)){$errors.Add('ID_NOT_IN_CSV '+$i)}
  elseif($inventory[$id].Source -cne $source){$errors.Add('SOURCE_MISMATCH '+$i)}
  if([string]::IsNullOrWhiteSpace($ru) -or [string]::IsNullOrWhiteSpace($en)){$errors.Add('MISSING_TEXT '+$i)}
  if([string]$v['E'] -cne 'На проверку'){$errors.Add('UNEXPECTED_REVIEW_STATUS '+$i)}
  $ruParams=@([regex]::Matches($ru,'\{[^{}]+\}') | ForEach-Object {$_.Value} | Sort-Object)
  $enParams=@([regex]::Matches($en,'\{[^{}]+\}') | ForEach-Object {$_.Value} | Sort-Object)
  if(([string]::Join('|',$ruParams)) -cne ([string]::Join('|',$enParams))){$errors.Add('PLACEHOLDER_MISMATCH '+$i)}
  if($ru.StartsWith(' ') -ne $en.StartsWith(' ') -or $ru.EndsWith(' ') -ne $en.EndsWith(' ')){
   $errors.Add('EDGE_SPACE_MISMATCH '+$i)
  }
  if(([regex]::Matches($ru,'\\n')).Count -ne ([regex]::Matches($en,'\\n')).Count){$errors.Add('ESCAPED_NEWLINE_MISMATCH '+$i)}
  if(-not $areaCounts.ContainsKey($area)){$areaCounts[$area]=0}
  $areaCounts[$area]++
 }
 if($errors.Count -gt 0){throw ('I18N_WORKBOOK_ERRORS='+$errors.Count+' '+($errors -join '; '))}
 Write-Output ('PASS I18N draft workbook: '+$ids.Count+' unique English/Russian pairs')
 foreach($area in @($areaCounts.Keys | Sort-Object)){Write-Output ($area+'='+$areaCounts[$area])}
 Write-Output ('PASS original CSV candidate IDs and sources; placeholders; spacing; escaped newlines')
 Write-Output 'STATUS: DRAFT ONLY. No translation has been editorially approved or activated.'
}finally{$zip.Dispose()}
