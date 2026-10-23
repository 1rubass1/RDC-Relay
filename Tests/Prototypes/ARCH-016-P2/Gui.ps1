# ARCH-016-P1 disposable GUI; real WinForms, fake Remote only.
param([Parameter(Mandatory=$true)][string]$TicketPath,[switch]$TestMode)
$ErrorActionPreference='Stop'
$GuiBuild='A'
try {
  Add-Type -AssemblyName System.Windows.Forms,System.Drawing
  Add-Type -Path (Join-Path $PSScriptRoot 'P1Wire.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
  $ticket=[P1Wire]::Decode([IO.File]::ReadAllText($TicketPath,[Text.Encoding]::UTF8))
  $serverIdentity=([string]$ticket.hostPid)+'|'+([string]$ticket.hostTicks)+'|'+([string]$ticket.hostSession)
  $script:sequence=1
  $req=[P1Wire]::Decode([P1Wire]::Request('HELLO',[string]$ticket.nonce,[string]$ticket.hostGeneration,0,$null,$script:sequence))
  $req['guiBuild']=$GuiBuild
  $joined=[P1Wire]::Decode([P1Wire]::Call([string]$ticket.pipe,$serverIdentity,[P1Wire]::Json.Serialize($req),1200))
  if($joined.type -ne 'WELCOME'){throw ('Host rejected HELLO: '+$joined.code)}
} catch {
  [Console]::Error.WriteLine(('P1_GUI_AUTH_FAILED: '+$_.Exception.Message))
  exit 5
}
# Distinct, visible P2 fixture with native WinForms controls; no real Remote action.
function Theme([string]$hex){return [Drawing.ColorTranslator]::FromHtml($hex)}
$form=New-Object Windows.Forms.Form
$form.Text='RDC Relay P2 SANDBOX - GUI Build '+$GuiBuild+' [FAKE REMOTE]'
$form.ClientSize=New-Object Drawing.Size(960,690)
$form.MinimumSize=New-Object Drawing.Size(740,530)
$form.StartPosition='CenterScreen'
$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
$form.BackColor=Theme '#1D2024'
$form.ForeColor=Theme '#E8EAED'
$form.Font=[Drawing.Font]::new('Segoe UI',10)
$form.KeyPreview=$true
if($TestMode){$form.Opacity=0.0;$form.ShowInTaskbar=$false}
$accent=if($GuiBuild -eq 'B'){'#EBB857'}else{'#BF7643'}
$form.SuspendLayout()
$headerPanel=New-Object Windows.Forms.Panel
$headerPanel.Dock='Top';$headerPanel.Height=116;$headerPanel.BackColor=Theme '#262A30'
$form.Controls.Add($headerPanel)
$heading=New-Object Windows.Forms.Label
$heading.Text='RDC RELAY  /  P2 INTERACTIVE SANDBOX'
$heading.Font=[Drawing.Font]::new('Segoe UI',17,[Drawing.FontStyle]::Bold)
$heading.ForeColor=Theme '#F2F3F5'
$heading.Location=New-Object Drawing.Point(18,12)
$heading.Size=New-Object Drawing.Size(710,38)
$heading.Anchor='Top,Left,Right'
$headerPanel.Controls.Add($heading)
$label=New-Object Windows.Forms.Label
$label.Text='GUI '+$GuiBuild+'  |  FAKE REMOTE ONLY'
$label.ForeColor=Theme '#C8CED6'
$label.Location=New-Object Drawing.Point(20,58)
$label.Size=New-Object Drawing.Size(660,48)
$label.Anchor='Top,Left,Right'
$label.AccessibleName='Fake Remote Host status and GUI build'
$headerPanel.Controls.Add($label)
$stateTag=New-Object Windows.Forms.Label
$stateTag.Text='SIMULATED / NOT CONNECTED'
$stateTag.TextAlign='MiddleCenter'
$stateTag.Font=[Drawing.Font]::new('Segoe UI',9,[Drawing.FontStyle]::Bold)
$stateTag.ForeColor=Theme '#101216'
$stateTag.BackColor=Theme $accent
$stateTag.Location=New-Object Drawing.Point(700,26)
$stateTag.Size=New-Object Drawing.Size(235,35)
$stateTag.Anchor='Top,Right'
$stateTag.AccessibleName='Fake connection state'
$headerPanel.Controls.Add($stateTag)
$separator=New-Object Windows.Forms.Panel
$separator.Dock='Bottom';$separator.Height=2;$separator.BackColor=Theme '#7B5FA2'
$headerPanel.Controls.Add($separator)
$footer=New-Object Windows.Forms.Panel
$footer.Dock='Bottom';$footer.Height=46;$footer.BackColor=Theme '#262A30'
$form.Controls.Add($footer)
$footerText=New-Object Windows.Forms.Label
$footerText.Dock='Fill';$footerText.TextAlign='MiddleLeft'
$footerText.ForeColor=Theme '#B8C0C8'
$footerText.Text='  P2 TEST ONLY  /  No real Remote or user journals'
$footer.Controls.Add($footerText)
$activityPanel=New-Object Windows.Forms.Panel
$activityPanel.Dock='Bottom';$activityPanel.Height=143
$activityPanel.Padding=New-Object Windows.Forms.Padding(15,8,15,8)
$form.Controls.Add($activityPanel)
$activityHead=New-Object Windows.Forms.Label
$activityHead.Dock='Top';$activityHead.Height=24
$activityHead.ForeColor=Theme '#E6BD89'
$activityHead.Font=[Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
$activityHead.Text='SYNTHETIC EVENTS'
$activityPanel.Controls.Add($activityHead)
$activityBox=New-Object Windows.Forms.TextBox
$activityBox.Dock='Fill';$activityBox.Multiline=$true
$activityBox.ReadOnly=$true;$activityBox.TabStop=$false
$activityBox.ScrollBars='Vertical'
$activityBox.Font=[Drawing.Font]::new('Consolas',9)
$activityBox.BackColor=Theme '#121417';$activityBox.ForeColor=Theme '#D9DEE5'
$activityBox.Text='[fixture] Synthetic Host alive. No real log is accessed.'
$activityBox.AccessibleName='Read-only synthetic event stream'
$activityPanel.Controls.Add($activityBox)
$activityBox.BringToFront()
$tools=New-Object Windows.Forms.Panel
$tools.Dock='Top';$tools.Height=78
$form.Controls.Add($tools)
$toolsLabel=New-Object Windows.Forms.Label
$toolsLabel.Text='REMOTE ACTIONS: UNAVAILABLE IN THIS FIXTURE'
$toolsLabel.ForeColor=Theme '#D6B98A'
$toolsLabel.Location=New-Object Drawing.Point(17,6)
$toolsLabel.Size=New-Object Drawing.Size(630,24)
$tools.Controls.Add($toolsLabel)
$tip=New-Object Windows.Forms.ToolTip
$px=18
foreach($name in @('Start Remote','Stop Remote','Reconnect','Account')){
  $btn=New-Object Windows.Forms.Button
  $btn.Text=$name;$btn.Width=146;$btn.Height=34
  $btn.Location=New-Object Drawing.Point($px,35)
  $btn.FlatStyle='Flat';$btn.FlatAppearance.BorderColor=Theme '#838990'
  $btn.BackColor=Theme '#2D3137';$btn.ForeColor=Theme '#B9BEC6'
  $btn.Enabled=$false
  $btn.AccessibleName=($name+' disabled; fake-only research')
  $tip.SetToolTip($btn,'Unavailable - real Remote integration is not authorized')
  $tools.Controls.Add($btn)
  $px+=157
}
$about=New-Object Windows.Forms.Button
$about.Text='&About demo';$about.Width=116;$about.Height=34
$about.Location=New-Object Drawing.Point(675,35)
$about.Anchor='Top,Right'
$about.BackColor=Theme '#30343B';$about.ForeColor=Theme '#F0F2F4'
$about.FlatStyle='Flat';$about.FlatAppearance.BorderColor=Theme '#EBB857'
$about.AccessibleName='About this fake-only demonstration'
$about.Add_Click({
  [Windows.Forms.MessageBox]::Show($form,'P2 SANDBOX: only a mock Remote session exists. Closing X fully exits this GUI process; Tray Host remains alive.','RDC Relay P2 demonstration')|Out-Null
})
$tools.Controls.Add($about)
$mainPanel=New-Object Windows.Forms.Panel
$mainPanel.Dock='Fill';$mainPanel.Padding=New-Object Windows.Forms.Padding(15,7,15,8)
$form.Controls.Add($mainPanel)
$logHead=New-Object Windows.Forms.Label
$logHead.Dock='Top';$logHead.Height=29
$logHead.Text='FAKE REMOTE MONITOR / READ-ONLY JOURNAL'
$logHead.ForeColor=Theme '#E6BD89'
$logHead.Font=[Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
$mainPanel.Controls.Add($logHead)
$log=New-Object Windows.Forms.RichTextBox
$log.Dock='Fill';$log.ReadOnly=$true;$log.TabStop=$false
$log.Font=[Drawing.Font]::new('Consolas',10)
$log.BackColor=Theme '#121417';$log.ForeColor=Theme '#DFE2E5'
$log.AccessibleName='Read-only synthetic Remote journal'
$log.Text=@'
[RDC Relay P2] FAKE-ONLY live UI prototype
Remote state        : UNKNOWN (no Remote linked)
Authentication      : NOT ATTEMPTED
Transport           : synthetic snapshot over protected local pipe
Connection history  : fabricated test data; not user activity

Close with the native X.
The separate P2 TEST Tray Host continues monitoring mock state.
Change the fixture GUI source from build A to B and double-click
its visible tray icon to load the new GUI process.
All Remote command buttons remain disabled.
'@
$mainPanel.Controls.Add($log)
$log.BringToFront()
$form.ResumeLayout($true)
$script:poll=$null
$script:closeSeen=[int]$joined.payload.closeGeneration
$script:lastEvent=0
$script:resyncs=0
$script:nextVerb='GET_SNAPSHOT'
$script:expectedGeneration=[string]$ticket.hostGeneration
$script:guiTimerTicks=0
$script:pulseFile=Join-Path $PSScriptRoot 'gui-pulse.txt'
$script:pauseFile=Join-Path $PSScriptRoot 'pause-gui-ipc.flag'
function Test-P2NoReparsePath([string]$Candidate,[switch]$AllowMissingLeaf){
  try{
    $current=[IO.Path]::GetFullPath($Candidate)
    $volume=[IO.Path]::GetPathRoot($current)
    $leaf=$true
    while(-not [string]::IsNullOrEmpty($current)){
      try{
        $attributes=[IO.File]::GetAttributes($current)
        if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
      }catch{
        if(-not ($leaf -and $AllowMissingLeaf)){return $false}
        $parent=[IO.Path]::GetDirectoryName($current)
        if(-not $parent -or -not [IO.Directory]::Exists($parent)){return $false}
        $name=[IO.Path]::GetFileName($current)
        foreach($entry in [IO.Directory]::GetFileSystemEntries($parent)){
          if([String]::Equals([IO.Path]::GetFileName($entry),$name,[StringComparison]::OrdinalIgnoreCase)){return $false}
        }
      }
      if([String]::Equals($current,$volume,[StringComparison]::OrdinalIgnoreCase)){break}
      $next=[IO.Path]::GetDirectoryName($current)
      if(-not $next -or $next -eq $current){return $false}
      $current=$next;$leaf=$false
    }
    return $true
  }catch{return $false}
}
function Test-P2PulsePathSafe {
  try{
    $root=[IO.Path]::GetFullPath($PSScriptRoot)
    $volume=[IO.Path]::GetPathRoot($root)
    if($root.Length -gt $volume.Length){$root=$root.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tempVolume=[IO.Path]::GetPathRoot($temp)
    if($temp.Length -gt $tempVolume.Length){$temp=$temp.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))}
    if(-not [IO.Directory]::Exists($root)){return $false}
    if(-not [String]::Equals([IO.Path]::GetDirectoryName($root),$temp,[StringComparison]::OrdinalIgnoreCase)){return $false}
    if([IO.Path]::GetFileName($root) -cnotmatch '^RDC-P2-[0-9a-f]{32}$'){return $false}
    $expected=[IO.Path]::GetFullPath([IO.Path]::Combine($root,'gui-pulse.txt'))
    if(-not [String]::Equals([IO.Path]::GetFullPath($script:pulseFile),$expected,[StringComparison]::OrdinalIgnoreCase)){return $false}
    if(-not (Test-P2NoReparsePath $root)){return $false}
    if(-not (Test-P2NoReparsePath $expected -AllowMissingLeaf)){return $false}
    if([IO.File]::Exists($expected) -and (([IO.File]::GetAttributes($expected) -band [IO.FileAttributes]::Directory) -ne 0)){return $false}
    return $true
  }catch{return $false}
}
function Write-P2Pulse([int]$Value){
  $stream=$null
  try{
    if(-not (Test-P2PulsePathSafe)){return}
    if([IO.File]::Exists($script:pulseFile)){
      $attributes=[IO.File]::GetAttributes($script:pulseFile)
      if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($attributes -band [IO.FileAttributes]::Directory) -ne 0){return}
      [IO.File]::Delete($script:pulseFile)
    }elseif([IO.Directory]::Exists($script:pulseFile)){return}
    # CreateNew refuses an entry inserted as a file link after validation;
    # unlike WriteAllText, it will not open/follow an existing target link.
    if(-not (Test-P2PulsePathSafe)){return}
    $bytes=[Text.Encoding]::UTF8.GetBytes([string]$Value)
    $stream=New-Object IO.FileStream($script:pulseFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush($true)
  }catch{}finally{if($stream){$stream.Dispose()}}
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=115
$timer.Add_Tick({
  $script:guiTimerTicks++
  if($TestMode -and $script:guiTimerTicks%2 -eq 0){
    Write-P2Pulse $script:guiTimerTicks
  }
  # Timer only checks COMPLETED tasks. Never synchronous frame I/O on UI thread.
  if($script:poll -and $script:poll.IsCompleted) {
    try {
      $res=[P1Wire]::Decode([string]$script:poll.GetAwaiter().GetResult())
      if($res.type -eq 'SNAPSHOT') {
        $payload=$res.payload
        if([string]$payload.hostGeneration -ne $script:expectedGeneration){throw 'Host generation changed; fail closed'}
        $label.Text='GUI '+$GuiBuild+'  |  Fake session '+$payload.remoteId+[Environment]::NewLine+'Persistent Host PID '+$payload.hostPid+'   /   tick '+$payload.tick
        $stateTag.Text='SIMULATED / NOT CONNECTED'
        $footerText.Text='  P2 TEST  |  Host '+$payload.hostPid+'  |  Fake Remote '+$payload.remoteId+'  |  GUI process '+[Diagnostics.Process]::GetCurrentProcess().Id
        if([int]$payload.closeGeneration -gt $script:closeSeen){$form.Close();return}
        $script:closeSeen=[int]$payload.closeGeneration
        $script:nextVerb='GET_EVENTS'
      } elseif($res.type -eq 'EVENT_BATCH') {
        $payload=$res.payload
        if([string]$payload.hostGeneration -ne $script:expectedGeneration){throw 'Changed Host generation'}
        if($payload.gap){
            $script:resyncs++
            $script:lastEvent=[long]$payload.lastEventSeq
            $script:nextVerb='GET_SNAPSHOT'
        } else {
            $sequence=$script:lastEvent
            foreach($event in $payload.events) {
                if([long]$event.sequence -le $sequence){throw 'Replayed event sequence'}
                $sequence=[long]$event.sequence
              if($event.source -eq 'gui' -or ($sequence%12 -eq 0)){
                $activityBox.AppendText([Environment]::NewLine+'#'+$sequence+'  '+$event.source+' / '+$event.text)
              }
            }
            $script:lastEvent=$sequence
            $script:nextVerb=if($payload.moreAvailable){'GET_EVENTS'}else{'GET_SNAPSHOT'}
        }
      }
    } catch {
      $label.Text='IPC unavailable; Host recovery pending (fake Remote unchanged)'
      $stateTag.Text='IPC RETRYING'
      $script:nextVerb='GET_SNAPSHOT'
    }
    $script:poll=$null
  }
  if(-not $script:poll) {
    # Deterministic, disposable test-only saturation hook; no real IPC commands.
    if($TestMode -and [IO.File]::Exists($script:pauseFile)){return}
    $script:sequence++
    $request=[P1Wire]::Request($script:nextVerb,[string]$ticket.nonce,[string]$ticket.hostGeneration,[long]$script:lastEvent,$null,[long]$script:sequence)
    $script:poll=[P1Wire]::CallBackground([string]$ticket.pipe,$serverIdentity,$request,750)
  }
})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose();$tip.Dispose()})
try {$timer.Start();[Windows.Forms.Application]::Run($form)}
finally {$form.Dispose()}
