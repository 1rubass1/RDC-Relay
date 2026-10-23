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
$form=New-Object Windows.Forms.Form
$form.Text='RDC P1 fake GUI '+$GuiBuild
$form.Width=480;$form.Height=210
$form.StartPosition='CenterScreen'
if($TestMode){$form.Opacity=0.0;$form.ShowInTaskbar=$false}
$label=New-Object Windows.Forms.Label
$label.Width=440;$label.Height=140
$label.Location=New-Object Drawing.Point(15,15)
$label.Text='GUI '+$GuiBuild+' / fake Remote only'
$form.Controls.Add($label)
$script:poll=$null
$script:closeSeen=[int]$joined.payload.closeGeneration
$script:lastEvent=0
$script:resyncs=0
$script:nextVerb='GET_SNAPSHOT'
$script:expectedGeneration=[string]$ticket.hostGeneration
$script:guiTimerTicks=0
$script:pulseFile=Join-Path $PSScriptRoot 'gui-pulse.txt'
$timer=New-Object Windows.Forms.Timer
$timer.Interval=115
$timer.Add_Tick({
  $script:guiTimerTicks++
  if($TestMode -and $script:guiTimerTicks%2 -eq 0){
    try{[IO.File]::WriteAllText($script:pulseFile,[string]$script:guiTimerTicks)}catch{}
  }
  # Timer only checks COMPLETED tasks. Never synchronous frame I/O on UI thread.
  if($script:poll -and $script:poll.IsCompleted) {
    try {
      $res=[P1Wire]::Decode([string]$script:poll.GetAwaiter().GetResult())
      if($res.type -eq 'SNAPSHOT') {
        $payload=$res.payload
        if([string]$payload.hostGeneration -ne $script:expectedGeneration){throw 'Host generation changed; fail closed'}
        $label.Text='GUI '+$GuiBuild+' / fake session '+$payload.remoteId+[Environment]::NewLine+'Host tick '+$payload.tick
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
            }
            $script:lastEvent=$sequence
            $script:nextVerb=if($payload.moreAvailable){'GET_EVENTS'}else{'GET_SNAPSHOT'}
        }
      }
    } catch {
      $label.Text='IPC unavailable; full snapshot resync pending'
      $script:nextVerb='GET_SNAPSHOT'
    }
    $script:poll=$null
  }
  if(-not $script:poll) {
    $script:sequence++
    $request=[P1Wire]::Request($script:nextVerb,[string]$ticket.nonce,[string]$ticket.hostGeneration,[long]$script:lastEvent,$null,[long]$script:sequence)
    $script:poll=[P1Wire]::CallBackground([string]$ticket.pipe,$serverIdentity,$request,750)
  }
})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose()})
try {$timer.Start();[Windows.Forms.Application]::Run($form)}
finally {$form.Dispose()}
