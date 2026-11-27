$ErrorActionPreference='Stop'
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'
$raw=[IO.File]::ReadAllText((Join-Path $src 'remote-window.ps1'))
$gui=[IO.File]::ReadAllText((Join-Path $src 'rc1-owner-gui.ps1'))
$pass=0
function Check([bool]$ok,[string]$label){if(!$ok){throw ('FAIL '+$label)};$script:pass++;'PASS '+$label}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($raw,[ref]$t,[ref]$e)
Check ($e.Count -eq 0) 'GUI AST'
$a=$raw.IndexOf('public class RdcLogBox : RichTextBox {')
$b=$raw.IndexOf("'@ -ReferencedAssemblies",$a)
if($a -lt 0 -or $b -le $a){throw 'CLASS_BOUNDARY'}
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type -ReferencedAssemblies System.dll,System.Drawing,System.Windows.Forms -TypeDefinition ('using System;using System.IO;using System.Text;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;using System.Runtime.InteropServices;using System.Diagnostics;'+$raw.Substring($a,$b-$a))
foreach($name in @('Convert-Rc1OwnerStartupGlyphs','Apply-Rc1OwnerStartupGlyphs')){
 $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
 if(!$fn){throw ('FUNCTION '+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
$globe=[char]::ConvertFromUtf32(0x1F310)
$rocket=[char]::ConvertFromUtf32(0x1F680)
$network=[string][char]0x25CE
$start=[string][char]0x25B6
foreach($nl in @([string][char]10,[Environment]::NewLine)){
 $original=$globe+' Remote Connection'+$nl+$rocket+' Starting MCP Device...'+$nl+'ordinary '+$rocket+' text'+$nl+'Device ready:'
 $expected=$network+' Remote Connection'+$nl+$start+' Starting MCP Device...'+$nl+'ordinary '+$rocket+' text'+$nl+'Device ready:'
 $out=Convert-Rc1OwnerStartupGlyphs $original
 Check ($out -ceq $expected) ('exact two heading glyphs newline '+$nl.Length)
 Check ($original.StartsWith($globe)) 'original immutable'
 Check ((Convert-Rc1OwnerStartupGlyphs ($rocket+' Starting MCP Device... unexpected')) -ceq ($rocket+' Starting MCP Device... unexpected')) 'unrecognized suffix unchanged'
 Check ((Convert-Rc1OwnerStartupGlyphs $out) -ceq $out) 'idempotent'
}
Check ($gui.Contains("         'Remote Connection','',") -and !$gui.Contains("         '','Remote Connection','',") -and !$gui.Contains("         "+'$safeArt'+",'','Remote Connection','',")) 'no fallback leading blank'
Check ($raw.Contains('$headerDisplay=Convert-Rc1OwnerStartupGlyphs $headerDisplay') -and $raw.Contains('if($OwnerGui){Apply-Rc1OwnerStartupGlyphs $headerLog}')) 'real Owner renderer invokes conversion and style'
$accentNetwork=[Drawing.Color]::FromArgb(89,172,220)
$accentOrange=[Drawing.Color]::FromArgb(191,118,67)
$box=New-Object RdcLogBox
$font=New-Object Drawing.Font('Consolas',9)
try{
 $box.Font=$font;$box.ForeColor=[Drawing.Color]::Gainsboro;$box.Size=[Drawing.Size]::new(650,180)
 [void]$box.Handle
 $box.Text=$network+' Remote Connection'+[Environment]::NewLine+$start+' Starting MCP Device...'+[Environment]::NewLine+'ordinary '+$network+' text'
 Apply-Rc1OwnerStartupGlyphs $box
 foreach($pair in @(@($network,$accentNetwork),@($start,$accentOrange))){
  $p=$box.Text.IndexOf($pair[0]);$box.Select($p,1)
  Check ($box.SelectionFont.FontFamily.Name -ceq 'Segoe UI Symbol') 'actual RichEdit heading symbol font'
  Check ($box.SelectionColor.ToArgb() -eq $pair[1].ToArgb()) 'actual RichEdit heading symbol color'
  $box.Select($p+2,1)
  Check ($box.SelectionFont.FontFamily.Name -ceq 'Consolas' -and $box.SelectionColor.ToArgb() -eq $box.ForeColor.ToArgb()) 'surrounding text unchanged'
 }
 $p=$box.Text.LastIndexOf($network);$box.Select($p,1)
 Check ($box.SelectionFont.FontFamily.Name -ceq 'Consolas') 'ordinary same character not restyled'
}finally{$box.Dispose();$font.Dispose()}
'RDC_STARTUP_GLYPHS_PASS='+$pass
