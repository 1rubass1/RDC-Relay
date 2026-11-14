# Compile exactly the production main/Owner modal button classes for isolated
# WinForms tests. Never starts Owner GUI, Host, Remote, browser or credentials.
param([Parameter(Mandatory=$true)][string]$SourcePath)
$source=[IO.File]::ReadAllText($SourcePath,[Text.Encoding]::UTF8)
$start=$source.IndexOf('public enum RdcButtonGlyph {',[StringComparison]::Ordinal)
$end=$source.IndexOf('public class RdcStatusIndicator : Control {',$start,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -le $start){throw 'PRODUCTION_MODAL_CHROME_SOURCE_NOT_FOUND'}
$code='using System;using System.Drawing;using System.Drawing.Drawing2D;using System.Windows.Forms;'+
 [Environment]::NewLine+$source.Substring($start,$end-$start)
Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.dll','System.Drawing.dll','System.Windows.Forms.dll')
if(-not ('RdcModalButton' -as [type]) -or -not ('RdcRoundedButton' -as [type])){
 throw 'PRODUCTION_MODAL_CHROME_COMPILATION_FAILED'
}
