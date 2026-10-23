# ARCH-016-P0 disposable replaceable WinForms GUI; no Remote code, no singleton kill.
param([Parameter(Mandatory=$true)][string]$PipeName,[switch]$TestMode)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Ipc.ps1')
Assert-ProbePipeName $PipeName
# Test deliberately rewrites this PROGRAM SOURCE line A -> B between launches.
$GuiBuild = 'A'
$ProtocolVersion = '1'
try {
    $join=Invoke-ProbePipe -Name $PipeName -Command ('HELLO|'+$PID+'|'+$GuiBuild+'|'+$ProtocolVersion) -TimeoutMs 1400
    if (-not $join.ok) { throw ('GUI rejected: '+$join.error) }
} catch {
    Write-Output ('PROTOTYPE_GUI_HANDSHAKE_ERROR: '+$_.Exception.Message)
    exit 5
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$form=New-Object Windows.Forms.Form
$form.Text='RDC Relay P0 GUI - build '+$GuiBuild
$form.Width=520
$form.Height=210
$form.StartPosition=[Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::Sizable
$form.ShowInTaskbar=(-not $TestMode)
if ($TestMode) {$form.Opacity=0.0}
$header=New-Object Windows.Forms.Label
$header.AutoSize=$true
$header.Font=New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold)
$header.Location=New-Object Drawing.Point(15,16)
$header.Text='Replaceable GUI, build '+$GuiBuild
$form.Controls.Add($header)
$status=New-Object Windows.Forms.Label
$status.Location=New-Object Drawing.Point(18,65)
$status.Width=480
$status.Height=76
$status.Text='Connecting to fake background host...'
$form.Controls.Add($status)
$script:lastCloseGeneration=[int]$join.closeGeneration
$script:timer=New-Object Windows.Forms.Timer
$script:timer.Interval=225
$script:timer.Add_Tick({
    try {
        $state=Invoke-ProbePipe -Name $PipeName -Command 'STATE' -TimeoutMs 600
        if (-not $state.ok) {throw 'IPC status rejected'}
        $status.Text='Fake Remote session: '+$state.remoteId+[Environment]::NewLine+
            'Host: '+$state.hostPid+'  ticks: '+$state.tick+[Environment]::NewLine+
            'GUI build: '+$GuiBuild+'  PID: '+$PID
        if ([int]$state.closeGeneration -gt $script:lastCloseGeneration) {
            $form.Close()
        }
    } catch {
        $status.Text='IPC temporarily unavailable; fake Remote host was not stopped.'
    }
})
$form.Add_FormClosed({
    $script:timer.Stop()
    $script:timer.Dispose()
    try {
        [void](Invoke-ProbePipe -Name $PipeName -Command ('BYE|'+$PID) -TimeoutMs 400)
    } catch {}
})
try {
    $script:timer.Start()
    [Windows.Forms.Application]::Run($form)
} finally {
    $form.Dispose()
}
