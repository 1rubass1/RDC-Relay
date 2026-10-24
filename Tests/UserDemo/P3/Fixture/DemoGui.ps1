# P3 owner demo. No production Remote, user account or real journal access.
param([Parameter(Mandatory=$true)][string]$TicketPath)
$ErrorActionPreference='Stop'
$GuiBuild='A'
try {
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 [Windows.Forms.Application]::EnableVisualStyles()
 Add-Type -Path (Join-Path $PSScriptRoot 'P1Wire.cs') -ReferencedAssemblies @('System.Core.dll','System.Web.Extensions.dll','System.dll','System.Security.dll')
 $ticket=[P1Wire]::Decode([IO.File]::ReadAllText($TicketPath,[Text.Encoding]::UTF8))
 $script:identity=([string]$ticket.hostPid)+'|'+([string]$ticket.hostTicks)+'|'+([string]$ticket.hostSession)
 $script:sequence=1
 $hello=[P1Wire]::Decode([P1Wire]::Request('HELLO',[string]$ticket.nonce,[string]$ticket.hostGeneration,0,$null,$script:sequence))
 $hello['guiBuild']=$GuiBuild
 $welcome=[P1Wire]::Decode([P1Wire]::Call([string]$ticket.pipe,$script:identity,[P1Wire]::Json.Serialize($hello),1200))
 if($welcome.type -ne 'WELCOME'){throw ('GUI authentication rejected: '+$welcome.code)}
}catch{[Console]::Error.WriteLine('P3_GUI_AUTH_FAILED: '+$_.Exception.Message);exit 5}
function C([string]$h){return [Drawing.ColorTranslator]::FromHtml($h)}
$bg=C '#1D2024';$surface=C '#121417';$purple=C '#7B5FA2';$orange=C '#BF7643';$gold=C '#EBB857';$fg=[Drawing.Color]::Gainsboro
$form=New-Object Windows.Forms.Form
$form.Text='RDC Relay — демонстрация (GUI '+$GuiBuild+')'
$form.Size=New-Object Drawing.Size(1074,900)
$form.MinimumSize=New-Object Drawing.Size(770,560)
$form.MaximizeBox=$false;$form.FormBorderStyle='Sizable';$form.StartPosition='CenterScreen'
$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
$form.BackColor=$bg;$form.ForeColor=$fg;$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.Icon=[Drawing.SystemIcons]::Information
$form.SuspendLayout()

# Identical high-level product proportions: header 78 px, footer 38 px,
# main terminal, purple 7 px divider and 125 px journal.
$top=New-Object Windows.Forms.Panel
$top.Dock='Top';$top.Height=78;$top.Padding=New-Object Windows.Forms.Padding(16,9,16,9)
$top.BackColor=$bg;$form.Controls.Add($top)
$top.Add_Paint({
 param($s,$e);$pen=New-Object Drawing.Pen($purple,1)
 try{$e.Graphics.DrawLine($pen,0,$s.ClientSize.Height-1,$s.ClientSize.Width,$s.ClientSize.Height-1)}
 finally{$pen.Dispose()}
})
$right=New-Object Windows.Forms.FlowLayoutPanel
$right.Dock='Right';$right.Width=320;$right.FlowDirection='RightToLeft'
$right.WrapContents=$false;$right.Padding=New-Object Windows.Forms.Padding(0,12,0,0)
$right.BackColor=$bg;$top.Controls.Add($right)
function ButtonDemo([string]$caption,[int]$width){
 $b=New-Object Windows.Forms.Button
 $b.Text=$caption;$b.Width=$width;$b.Height=36;$b.FlatStyle='Flat'
 $b.FlatAppearance.BorderColor=$orange;$b.BackColor=$bg;$b.ForeColor=$fg
 return $b
}
$stop=ButtonDemo 'Запустить' 120
$stop.Enabled=$false;$stop.AccessibleName='Запустить Remote — недоступно'
$right.Controls.Add($stop)
$help=ButtonDemo '?' 36
$help.AccessibleName='Справка о тестовой сборке'
$help.Add_Click({
 [void][Windows.Forms.MessageBox]::Show('Все данные синтетические. Закрытие X завершает только этот GUI. Двойной щелчок по значку RDC Relay DEMO в трее открывает новый GUI.','RDC Relay — демонстрация',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
})
$right.Controls.Add($help)
$account=ButtonDemo 'Аккаунт ▾' 120;$right.Controls.Add($account)
$accountMenu=New-Object Windows.Forms.ContextMenuStrip
$accountMenu.BackColor=C '#26292E';$accountMenu.ForeColor=$fg
foreach($entry in @('Сменить аккаунт…','Переподключить','Управление устройствами…','Подтвердить новое устройство…')){
 if($entry -eq 'Управление устройствами…'){[void]$accountMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))}
 $item=New-Object Windows.Forms.ToolStripMenuItem($entry)
 $item.Enabled=$false;$item.ToolTipText='Недоступно: синтетический аккаунт'
 [void]$accountMenu.Items.Add($item)
}
$account.Add_Click({$accountMenu.Show($account,0,$account.Height)})
$header=New-Object Windows.Forms.Panel
$header.Dock='Fill';$header.BackColor=$bg;$top.Controls.Add($header)
$dot=New-Object Windows.Forms.Panel
$dot.BackColor=[Drawing.Color]::Gray;$dot.Size=New-Object Drawing.Size(17,17)
$dot.Location=New-Object Drawing.Point(7,14);$header.Controls.Add($dot)
$heading=New-Object Windows.Forms.Label
$heading.Text='RDC Relay';$heading.Font=New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
$heading.ForeColor=$fg;$heading.Location=New-Object Drawing.Point(40,2)
$heading.Size=New-Object Drawing.Size(400,32);$header.Controls.Add($heading)
$status=New-Object Windows.Forms.Label
$status.Text='Remote: не подключён — демонстрация'
$status.ForeColor=[Drawing.Color]::Silver
$status.Location=New-Object Drawing.Point(40,36)
$status.Size=New-Object Drawing.Size(595,25)
$header.Controls.Add($status)

$footer=New-Object Windows.Forms.Panel
$footer.Dock='Bottom';$footer.Height=38;$footer.BackColor=$bg
$footer.Padding=New-Object Windows.Forms.Padding(12,7,12,6)
$form.Controls.Add($footer)
$footerLeft=New-Object Windows.Forms.Label
$footerLeft.Dock='Left';$footerLeft.Width=550;$footerLeft.ForeColor=[Drawing.Color]::Silver
$footerLeft.Text='Аккаунт: демо   |   Host: получение статуса…'
$footer.Controls.Add($footerLeft)
$footerRight=New-Object Windows.Forms.Label
$footerRight.Dock='Fill';$footerRight.TextAlign='MiddleRight'
$footerRight.ForeColor=[Drawing.Color]::Gray
$footerRight.Text='v1.5.18 — образец   |   P3 DEMO '+$GuiBuild
$footer.Controls.Add($footerRight);$footerRight.BringToFront()
$activityPanel=New-Object Windows.Forms.Panel
$activityPanel.Dock='Bottom';$activityPanel.Height=125;$activityPanel.BackColor=$surface
$form.Controls.Add($activityPanel)
$activity=New-Object Windows.Forms.RichTextBox
$activity.Dock='Fill';$activity.BackColor=$surface;$activity.ForeColor=$fg
$activity.Font=New-Object Drawing.Font('Consolas',9)
$activity.ReadOnly=$true;$activity.TabStop=$false;$activity.WordWrap=$false
$activity.BorderStyle='None';$activity.ScrollBars='Both';$activity.DetectUrls=$false
$activity.AccessibleName='Синтетический журнал событий'
$activity.Text=('[ДЕМОНСТРАЦИЯ] Все события вымышлены.'+[Environment]::NewLine+'[00:00:01] GUI открылся в новом процессе.'+[Environment]::NewLine+'[00:00:02] Настоящий Remote не подключён.')
$activityPanel.Controls.Add($activity)
$divider=New-Object Windows.Forms.Panel
$divider.Dock='Bottom';$divider.Height=7;$divider.BackColor=$surface
$divider.Add_Paint({
 param($s,$e);$pen=New-Object Drawing.Pen($purple,1)
 try{$e.Graphics.DrawLine($pen,0,0,$s.Width,0);$e.Graphics.DrawLine($pen,0,$s.Height-1,$s.Width,$s.Height-1)}
 finally{$pen.Dispose()}
})
$form.Controls.Add($divider)
$terminalHost=New-Object Windows.Forms.Panel
$terminalHost.Dock='Fill';$terminalHost.BackColor=$surface
$form.Controls.Add($terminalHost);$terminalHost.BringToFront()
$terminal=New-Object Windows.Forms.RichTextBox
$terminal.Dock='Fill';$terminal.BackColor=$surface;$terminal.ForeColor=$fg
$terminal.Font=New-Object Drawing.Font('Consolas',10)
$terminal.ReadOnly=$true;$terminal.TabStop=$false;$terminal.WordWrap=$false
$terminal.BorderStyle='None';$terminal.ScrollBars='Both';$terminal.DetectUrls=$false
$terminal.AccessibleName='Синтетическая область терминала'
$terminal.Text=@'
RDC Relay — синтетический терминал
─────────────────────────────────────────────────────────────

Статус Remote: НЕ ПОДКЛЮЧЕН
Аккаунт: DEMO USER (не настоящий аккаунт)

> Mock Host: доступен
> Локальный IPC: демонстрационный защищённый канал
> Настоящий процесс Remote: не запускается
> Пользовательские журналы: не считываются

Это интерактивная тестовая сборка интерфейса.
Закройте окно крестиком X и откройте через значок в трее.
'@
$terminalHost.Controls.Add($terminal)
$bannerPath=Join-Path $PSScriptRoot 'rdc-banner.png'
$banner=$null
if([IO.File]::Exists($bannerPath)){
 try{
  $banner=New-Object Windows.Forms.PictureBox
  $banner.Height=77;$banner.Dock='Top';$banner.SizeMode='Zoom'
  $banner.BackColor=$surface;$banner.Image=[Drawing.Image]::FromFile($bannerPath)
  $terminalHost.Controls.Add($banner);$banner.BringToFront()
 }catch{}
}
$buildBar=New-Object Windows.Forms.Panel
$buildBar.Dock='Bottom';$buildBar.Height=3
if($GuiBuild -eq 'B'){$buildBar.BackColor=$gold}else{$buildBar.BackColor=$orange}
$footer.Controls.Add($buildBar);$buildBar.BringToFront()
$form.ResumeLayout($true)

$script:expectedGen=[string]$ticket.hostGeneration
$script:closeSeen=[int]$welcome.payload.closeGeneration
$script:lastEvent=0;$script:nextVerb='GET_SNAPSHOT';$script:pending=$null
$timer=New-Object Windows.Forms.Timer;$timer.Interval=125
$timer.Add_Tick({
 if($script:pending -and $script:pending.IsCompleted){
  try{
   $result=[P1Wire]::Decode([string]$script:pending.GetAwaiter().GetResult())
   if($result.type -eq 'SNAPSHOT'){
    $s=$result.payload
    if([string]$s.hostGeneration -ne $script:expectedGen){throw 'Host identity changed'}
    if([int]$s.closeGeneration -gt $script:closeSeen){$form.Close();return}
    $script:closeSeen=[int]$s.closeGeneration
    $footerLeft.Text='Аккаунт: демо  |  Host PID: '+$s.hostPid+'  |  Сессия: '+([string]$s.remoteId).Substring(0,8)
    $status.Text='Remote: не подключён  |  GUI '+$GuiBuild+'  |  Host активен'
    $script:nextVerb='GET_EVENTS'
   }elseif($result.type -eq 'EVENT_BATCH'){
    $s=$result.payload
    if([string]$s.hostGeneration -ne $script:expectedGen){throw 'Host identity changed'}
    if($s.gap){$script:lastEvent=[long]$s.lastEventSeq;$script:nextVerb='GET_SNAPSHOT'}
    else{
     foreach($ev in $s.events){
      if([long]$ev.sequence -le $script:lastEvent){throw 'Duplicate event'}
      $script:lastEvent=[long]$ev.sequence
      if($ev.source -eq 'gui' -or ($script:lastEvent%12 -eq 0)){
       $activity.AppendText([Environment]::NewLine+'#'+$ev.sequence+' '+$ev.source+' / '+$ev.text)
      }
     }
     $script:nextVerb=if($s.moreAvailable){'GET_EVENTS'}else{'GET_SNAPSHOT'}
    }
   }
  }catch{$status.Text='IPC недоступен — повторная попытка (Remote не подключён)';$script:nextVerb='GET_SNAPSHOT'}
  $script:pending=$null
 }
 if(-not $script:pending){
  $script:sequence++
  $wire=[P1Wire]::Request($script:nextVerb,[string]$ticket.nonce,[string]$ticket.hostGeneration,[long]$script:lastEvent,$null,[long]$script:sequence)
  $script:pending=[P1Wire]::CallBackground([string]$ticket.pipe,$script:identity,$wire,800)
 }
})
$form.Add_FormClosed({
 $timer.Stop();$timer.Dispose();$accountMenu.Dispose()
 try{if($banner -and $banner.Image){$banner.Image.Dispose()}}catch{}
})
try{$timer.Start();[Windows.Forms.Application]::Run($form)}
finally{$form.Dispose()}
