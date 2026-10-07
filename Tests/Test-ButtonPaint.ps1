param([string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Source\remote-window.ps1'),[string]$PreviewPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
$node=$ast.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('public class RdcCircleButton')},$true)
Add-Type -TypeDefinition ($node.Value + ' public class RdcPaintProbeForm : System.Windows.Forms.Form { protected override bool ShowWithoutActivation { get { return true; } } }') -ReferencedAssemblies System.Windows.Forms,System.Drawing
$form=New-Object RdcPaintProbeForm
$form.BackColor=[Drawing.Color]::FromArgb(29,32,36)
$panel=New-Object Windows.Forms.FlowLayoutPanel
$panel.BackColor=$form.BackColor
$panel.Size=New-Object Drawing.Size(400,80)
$form.Controls.Add($panel)
$buttons=@((New-Object RdcRoundedButton),(New-Object RdcCircleButton),(New-Object RdcRoundedButton))
$buttons[0].Text='Account';$buttons[1].Text='?';$buttons[2].Text='Stop'
$buttons[0].Size=New-Object Drawing.Size(120,36)
$buttons[2].Size=New-Object Drawing.Size(120,36)
foreach($button in $buttons){$panel.Controls.Add($button)}
$form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=New-Object Drawing.Point(-10000,-10000); $form.Show(); [Windows.Forms.Application]::DoEvents()
$failures=0
foreach($button in $buttons) {
    $button.CreateControl()
    $bitmap=New-Object Drawing.Bitmap($button.Width,$button.Height)
    $g=[Drawing.Graphics]::FromImage($bitmap)
    $g.Clear([Drawing.Color]::Magenta)
    $paint=New-Object Windows.Forms.PaintEventArgs($g,$button.ClientRectangle)
    $paintMethod=$button.GetType().GetMethod('OnPaint',[Reflection.BindingFlags]'Instance,NonPublic')
    # Mirror the live opaque-control path: OnPaintBackground is not invoked.
    $paintMethod.Invoke($button,[object[]]@($paint.PSObject.BaseObject))
    $unpainted=0
    $magenta=[Drawing.Color]::Magenta.ToArgb()
    for($y=0;$y -lt $bitmap.Height;$y++){for($x=0;$x -lt $bitmap.Width;$x++){
        if($bitmap.GetPixel($x,$y).ToArgb() -eq $magenta){$unpainted++}
    }}
    $opaque=($button.BackColor.A -eq 255)

    $button.Tag=0
    $clickHandler=[EventHandler]{param($sender,$args) $sender.Tag=[int]$sender.Tag+1}
    $button.add_Click($clickHandler)
    $keyDown=$button.GetType().GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
    $keyUp=$button.GetType().GetMethod('OnKeyUp',[Reflection.BindingFlags]'Instance,NonPublic')
    foreach($key in @([Windows.Forms.Keys]::Space,[Windows.Forms.Keys]::Enter)){
        $down=New-Object Windows.Forms.KeyEventArgs($key)
        $up=New-Object Windows.Forms.KeyEventArgs($key)
        $keyDown.Invoke($button,[object[]]@($down.PSObject.BaseObject))
        $keyUp.Invoke($button,[object[]]@($up.PSObject.BaseObject))
    }
    $button.remove_Click($clickHandler)
    $keyboardClicks=[int]$button.Tag

    Write-Output ($button.GetType().Name+' unpainted_pixels='+$unpainted+' opaque_background='+$opaque+' keyboard_clicks='+$keyboardClicks)
    if($unpainted -or -not $opaque -or $keyboardClicks -ne 2){$failures++}
    $g.Dispose();$bitmap.Dispose()
}
if ($PreviewPath) { $strip=New-Object Drawing.Bitmap($panel.Width,$panel.Height); $panel.DrawToBitmap($strip,$panel.ClientRectangle); $strip.Save($PreviewPath,[Drawing.Imaging.ImageFormat]::Png); $strip.Dispose() }
$form.Dispose()
if($failures){exit 1}
Write-Output 'BUTTON FULL-PAINT TEST PASSED'
