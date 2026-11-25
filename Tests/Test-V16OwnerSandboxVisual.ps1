# Isolated Windows Sandbox visual capture of the real Owner confirmation dialogs.
# ASCII-only PowerShell 5.1 source; localized UI strings come from verified JSON.
# Must be run in an STA session. No Host/Remote, IPC, login, browser or installer.
param([string]$OutputDir = (Join-Path $env:TEMP 'RdcOwnerI18nVisual'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'Source'
. (Join-Path $PSScriptRoot 'Import-V16OwnerModalButtonType.ps1') -SourcePath (Join-Path $src 'remote-window.ps1')
Add-Type -Path (Join-Path $src 'RdcUiLanguage.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'remote-window.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count -ne 0){throw 'RDC_VISUAL_SCRIPT_PARSE_FAILED'}
foreach($name in @('Get-RdcOwnerDialogText','New-RdcOwnerStopDialog','New-RdcOwnerReconnectDialog','New-RdcOwnerAccountSwitchDialog')){
 $node=$ast.Find({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq $name},$true)
 if(-not $node){throw ('RDC_VISUAL_FUNCTION_MISSING '+$name)}
 . ([scriptblock]::Create($node.Extent.Text))
}
$OwnerGui=$true
function Get-RdcOwnerUiText([string]$key,[string]$fallback){
 return [RdcUiLanguage]::Text($script:ownerUiTexts,$key,$fallback)
}
[void][IO.Directory]::CreateDirectory($OutputDir)
$results=New-Object 'System.Collections.Generic.List[string]'
$count=0
foreach($locale in @('ru-RU','en-US')){
 $script:ownerUiTexts=[RdcUiLanguage]::LoadResources($src,$locale)
 if($script:ownerUiTexts.Count -lt 139){throw ('RDC_VISUAL_CATALOG_MISSING '+$locale)}
 foreach($type in @('Stop','Reconnect','AccountSwitch')){
  $factory='New-RdcOwner'+$(if($type -eq 'AccountSwitch'){'AccountSwitch'}else{$type})+'Dialog'
  $form=& $factory
  if(-not $form){throw 'RDC_VISUAL_FORM_MISSING'}
  try{
   $form.StartPosition=[Windows.Forms.FormStartPosition]::CenterScreen
   $form.ShowInTaskbar=$false
   $form.Show()
   [Windows.Forms.Application]::DoEvents()
   Start-Sleep -Milliseconds 120
   [Windows.Forms.Application]::DoEvents()
   if($form.IsDisposed -or $form.Width -lt 180 -or $form.Height -lt 150){throw 'RDC_VISUAL_FORM_INVALID'}
   $yes=@($form.Controls.Find($('rc1-'+$(if($type -eq 'AccountSwitch'){'account-switch'}else{$type.ToLowerInvariant()+'-remote'})+'-yes'),$true))
   $png=Join-Path $OutputDir ($locale+'-'+$type.ToLowerInvariant()+'.png')
   $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
   try{
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
     $graphics.CopyFromScreen($form.Left,$form.Top,0,0,$bitmap.Size)
    }finally{$graphics.Dispose()}
    $bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
   }finally{$bitmap.Dispose()}
   if((Get-Item -LiteralPath $png).Length -lt 3000){throw ('RDC_VISUAL_SCREENSHOT_TOO_SMALL '+$png)}
   $dpi=$form.CreateGraphics()
   try{$dpiX=$dpi.DpiX;$dpiY=$dpi.DpiY}finally{$dpi.Dispose()}
   $record=$locale+' '+$type+' size='+$form.Width+'x'+$form.Height+' dpi='+$dpiX+'x'+$dpiY+' title='+$form.Text
   [void]$results.Add($record)
   Write-Output ('PASS_SCREEN '+$record)
   $count++
  }finally{$form.Close();$form.Dispose()}
 }
}
if($count -ne 6){throw ('RDC_VISUAL_BAD_SCREENSHOT_COUNT '+$count)}
$report=Join-Path $OutputDir 'visual-summary.txt'
[IO.File]::WriteAllLines($report,$results.ToArray(),(New-Object Text.UTF8Encoding($true)))
Write-Output ('RDC_VISUAL_SCREENSHOTS='+$count+' FAIL=0')
