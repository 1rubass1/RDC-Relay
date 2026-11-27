# RC1 Owner-only banner: two blank Unicode-art columns + 2px top.
# Actual production PowerShell AST and RdcLogBox WinForms/EM_SETPARAFORMAT.
# No real Remote, startup pipeline, installation or registered app is opened.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$file=Join-Path $root 'Source\remote-window.ps1'
$raw=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
$passed=0;$failed=0
function Check([bool]$ok,[string]$desc){
 if($ok){$script:passed++;Write-Output ('PASS '+$desc)}
 else{$script:failed++;Write-Output ('FAIL '+$desc)}
}
Check ($errors.Count -eq 0) 'production PowerShell parses'
$node=$ast.Find({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -ceq 'Add-Rc1OwnerBannerLeadingColumn'
},$true)
if(-not $node){throw 'OWNER_BANNER_INSET_HELPER_MISSING'}
. ([ScriptBlock]::Create($node.Extent.Text))

# Production banner input passes the actual Host's line-art allowlist.
$art=@(
 '╔═══════╗ ╔════════╗',
 '║███████║ ║████████║',
 '║██╔════╝ ║██╔═════╝',
 '║██║      ║█████╗',
 '║██║      ║██╔══╝',
 '╚══╝      ╚═╝'
)
foreach($row in $art){
 Check ($row -match '^[ \t\u00A0\u2500-\u259F/\\_|.]+$' -and
        $row -match '[\u2500-\u259F]') 'test art matches the bounded Unicode pseudographic allowlist'
}
$tail=@('','🔌 Remote Connection','','Status: Online','- User: tester@example.org','🚀 Next')
foreach($separator in @('LF','CRLF')){
 $nl=if($separator -eq 'LF'){"`n"}else{"`r`n"}
 $original=[string]::Join($nl,@($art)+$tail)
 $OwnerGui=$true
 $rendered=Add-Rc1OwnerBannerLeadingColumn $original
 $expected=[string]::Join($nl,@($art|ForEach-Object {'  '+$_})+$tail)
 Check ($rendered -ceq $expected) ('only six art lines get two leading columns newline='+$nl.Length)
 Check ($rendered.Length -eq ($original.Length+12) -and
   $rendered.EndsWith([string]::Join($nl,$tail))) ('source tail, CRLF and account text preserved newline='+$nl.Length)
 Check ($original.StartsWith($art[0]) -and -not $original.StartsWith(' ')) ('upstream input immutable newline='+$nl.Length)
 $OwnerGui=$false
 Check ((Add-Rc1OwnerBannerLeadingColumn $original) -ceq $original) ('legacy text byte-identical newline='+$nl.Length)
 $OwnerGui=$true
 Check ((Add-Rc1OwnerBannerLeadingColumn ($original -replace 'Remote Connection','Network')) -ceq
   ($original -replace 'Remote Connection','Network')) ('no marker means no transformation newline='+$nl.Length)
 $short=[string]::Join($nl,@($art[0..4])+$tail)
 Check ((Add-Rc1OwnerBannerLeadingColumn $short) -ceq $short) ('incomplete five-row banner left intact newline='+$nl.Length)
 $wrong=[string]::Join($nl,@($art[0..4])+@('Status: secret')+$tail)
 Check ((Add-Rc1OwnerBannerLeadingColumn $wrong) -ceq $wrong) ('unexpected non-art paragraph fails closed newline='+$nl.Length)
}
$OwnerGui=$true
Check ((Add-Rc1OwnerBannerLeadingColumn 'ordinary status') -ceq 'ordinary status') 'non-art Owner fallback remains untouched'
Check ($raw.Contains('$headerDisplay=Remove-Rc1OwnerWordmarkArt $headerDisplay') -and
 $raw.Contains('$headerDisplay=Convert-Rc1OwnerStartupInstructions $headerDisplay') -and
 $raw.Contains('$script:lastRenderedHeader = $headerDisplay') -and
 $raw.Contains('$headerLog.Text = $headerDisplay')) 'resource banner removes upstream art from render copy after instructions conversion'
Check ($raw.Contains('$headerLog.OwnerBannerLeadingColumn = [bool]$OwnerGui') -and
 $raw.Contains('int split = Math.Min(OwnerBannerLeadingColumn ? 63 : 61, line.Length);')) 'color boundary moves with Owner art, legacy split unchanged'
Check ($raw.Contains('if($OwnerGui){$headerLog.Margin = [Windows.Forms.Padding]::new(3,5,3,3)}') -and
 $raw.Contains('$headerLog.Dock = '+("'Fill'"))) 'Owner RichEdit inset adds only 2px top margin'

# Load exact, production RichTextBox class and run actual style selection.
$begin=$raw.IndexOf('public class RdcLogBox : RichTextBox {',[StringComparison]::Ordinal)
$finish=$raw.IndexOf("'@ -ReferencedAssemblies",$begin,[StringComparison]::Ordinal)
if($begin -lt 0 -or $finish -le $begin){throw 'PRODUCTION_RDC_LOGBOX_SOURCE_MISSING'}
$cs='using System;using System.IO;using System.Text;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;using System.Runtime.InteropServices;using System.Diagnostics;'+
 [Environment]::NewLine+$raw.Substring($begin,$finish-$begin)
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$orange=[Drawing.Color]::FromArgb(191,118,67)
$purple=[Drawing.Color]::FromArgb(123,95,162)
foreach($owner in @($false,$true)){
 $box=New-Object RdcLogBox
 try{
  $box.ForeColor=[Drawing.Color]::Gainsboro
  $box.OwnerBannerLeadingColumn=$owner
  $left=if($owner){'  '+('█'*61)}else{('D'*61)}
  $line=$left+$(if($owner){'╗'*12}else{'C'*12})
  $sourceText=(($line+[Environment]::NewLine)*6)+'Remote Connection'
  $box.Text=$sourceText
  Check ($box.StyleStartupBanner($orange,$purple)) ('production banner style executes Owner='+$owner)
  $split=if($owner){63}else{61}
  $box.Select(0,1)
  Check ($box.SelectionColor.ToArgb() -eq $orange.ToArgb()) ('first column remains orange Owner='+$owner)
  $box.Select($split-1,1)
  Check ($box.SelectionColor.ToArgb() -eq $orange.ToArgb()) ('last DESKTOP column correct Owner='+$owner)
  $box.Select($split,1)
  Check ($box.SelectionColor.ToArgb() -eq $purple.ToArgb()) ('first COMMANDER column correct Owner='+$owner)
  Check ($box.Text.Replace("`r",'') -ceq $sourceText.Replace("`r",'')) ('actual style preserves all art bytes Owner='+$owner)
 }finally{$box.Dispose()}
}

# Compare actual TableLayoutPanel child geometry without opening a live GUI.
$geometry=New-Object 'System.Collections.Generic.List[Drawing.Rectangle]'
foreach($owner in @($false,$true)){
 $form=New-Object Windows.Forms.Form
 $form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(-10000,-10000)
 $form.ClientSize=[Drawing.Size]::new(700,140)
 $panel=New-Object Windows.Forms.TableLayoutPanel
 $panel.Dock='Fill';$panel.RowCount=1;$panel.ColumnCount=1
 $panel.Margin=[Windows.Forms.Padding]::new(0);$panel.Padding=[Windows.Forms.Padding]::new(0)
 [void]$panel.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
 [void]$panel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
 $box=New-Object RdcLogBox
 $box.Dock='Fill';$box.Font=[Drawing.Font]::new('Consolas',9)
 if($owner){$box.Margin=[Windows.Forms.Padding]::new(3,5,3,3)}
 [void]$panel.Controls.Add($box,0,0);[void]$form.Controls.Add($panel)
 try{
  $form.Show();$panel.PerformLayout()
  $geometry.Add($box.Bounds)
  Check (($box.Margin.Left -eq 3) -and ($box.Margin.Right -eq 3) -and
    ($box.Margin.Bottom -eq 3)) ('horizontal/bottom margin unchanged Owner='+$owner)
 }finally{$form.Close();$form.Dispose()}
}
Check ($geometry.Count -eq 2 -and
 $geometry[1].Top -eq $geometry[0].Top+2 -and
 $geometry[1].Bottom -eq $geometry[0].Bottom -and
 $geometry[1].Left -eq $geometry[0].Left -and
 $geometry[1].Right -eq $geometry[0].Right) 'exact 2px top displacement, same left/right and bottom edges'
Write-Output ('RC1_OWNER_BANNER_INSET_PASS='+$passed+' FAIL='+$failed)
if($failed){exit 1}
exit 0
