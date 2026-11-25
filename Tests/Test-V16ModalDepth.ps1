param([string]$SourceRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'Source'))
# G121: Help icon next to title -> direct About -> real retained Owner journal.
# AST-driven real WinForms controls and click; no installed app, Host or Remote.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$path=Join-Path $SourceRoot 'remote-window.ps1'
Add-Type -Path (Join-Path $SourceRoot 'RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$raw=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
. (Join-Path $PSScriptRoot 'Import-V16OwnerModalButtonType.ps1') -SourcePath $path
# Compile the exact production RichEdit and overlay scrollbar controls
# in this isolated test, without launching the application or Remote.
$bufferStart=$raw.IndexOf('public class RdcBufferedPanel : Panel {',[StringComparison]::Ordinal)
$bufferEnd=$raw.IndexOf('public class RdcDividerDragPreview : Control {',$bufferStart,[StringComparison]::Ordinal)
$logStart=$raw.IndexOf('public class RdcLogBox : RichTextBox {',[StringComparison]::Ordinal)
$logEnd=$raw.IndexOf("'@ -ReferencedAssemblies",$logStart,[StringComparison]::Ordinal)
if($bufferStart -lt 0 -or $bufferEnd -le $bufferStart -or
 $logStart -lt 0 -or $logEnd -le $logStart){throw 'RC1_JOURNAL_PRODUCTION_CONTROLS_NOT_FOUND'}
$nativeCode='using System;using System.IO;using System.Text;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;using System.Runtime.InteropServices;using System.Diagnostics;' + [Environment]::NewLine +
 $raw.Substring($bufferStart,$bufferEnd-$bufferStart)+[Environment]::NewLine+
 $raw.Substring($logStart,$logEnd-$logStart)
Add-Type -TypeDefinition $nativeCode -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'PARSE'}
foreach($name in @('Get-RdcOwnerDialogText','New-RdcOwnerStopDialog','New-RdcOwnerReconnectDialog','New-RdcOwnerAccountSwitchDialog','New-RdcOwnerHelpDialog','New-RdcOwnerJournalDialog')){
 $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
 if(-not $fn){throw ('MISSING '+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
$script:ownerJournalAllowed=$true
$script:ownerTextFontFamily='Consolas'
$script:ownerUiTexts=[RdcUiLanguage]::LoadResources($SourceRoot,'ru-RU')
$script:pass=0;$script:fail=0
function Check([bool]$ok,[string]$message){if($ok){$script:pass++;Write-Output ('PASS '+$message)}else{$script:fail++;Write-Output ('FAIL '+$message)}}
function Buttons($control){foreach($child in $control.Controls){if($child -is [RdcModalButton]){$child}else{Buttons $child}}}
function MakeDialog($kind){
 switch($kind){
  'Stop'{New-RdcOwnerStopDialog}
  'Reconnect'{New-RdcOwnerReconnectDialog}
  'Account'{New-RdcOwnerAccountSwitchDialog}
  'Help'{New-RdcOwnerHelpDialog 'RDC Relay - visual test. No actual Remote actions.'}
  'Journal'{New-RdcOwnerJournalDialog 'Synthetic journal preview. No real account or log contents.'}
 }
}
foreach($kind in @('Stop','Reconnect','Account','Help','Journal')){
 $OwnerGui=$true
 $form=MakeDialog $kind
 $form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(-12000,-12000)
 try{
  $form.Show();[Windows.Forms.Application]::DoEvents();$form.PerformLayout()
  $buttons=@(Buttons $form)
  foreach($button in $buttons){
   $parent=$button.Parent
   $r=$button.Bounds
   Check ($button.AmbientShadow -and $r.Left -ge 3 -and $r.Top -ge 3 -and $r.Right+3 -le $parent.ClientSize.Width -and $r.Bottom+3 -le $parent.ClientSize.Height) "$kind $($button.Name) shadow clearance bounds=$r parent=$($parent.ClientSize)"
   $bmp=[Drawing.Bitmap]::new($parent.Width,$parent.Height)
   try{
    $parent.DrawToBitmap($bmp,[Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height))
    $cx=$r.Left+[int]($r.Width/2);$cy=$r.Top+[int]($r.Height/2)
    $expected=$form.BackColor
    if($r.Left -ge 3 -and $r.Top -ge 3 -and $r.Right+3 -le $parent.Width -and $r.Bottom+3 -le $parent.Height){
     $near=@($bmp.GetPixel($r.Left-1,$cy),$bmp.GetPixel($r.Right,$cy),$bmp.GetPixel($cx,$r.Top-1),$bmp.GetPixel($cx,$r.Bottom))
     $far=@($bmp.GetPixel($r.Left-2,$cy),$bmp.GetPixel($r.Right+1,$cy),$bmp.GetPixel($cx,$r.Top-2),$bmp.GetPixel($cx,$r.Bottom+1))
     $ok=$true
     for($i=0;$i -lt 4;$i++){if($near[$i].R -ge $far[$i].R -or $far[$i].R -ge $expected.R){$ok=$false}}
     Check $ok "$kind $($button.Name) fade in all four directions"
    }
   }finally{$bmp.Dispose()}
  }
 }finally{$form.Close();$form.Dispose()}
}
Write-Output ('MODAL_DEPTH_PASS='+$script:pass+' FAIL='+$script:fail)
if($script:fail){exit 1}