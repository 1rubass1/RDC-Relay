# RC1 owner-only footer and strictly expiring public quota percentage.
# Synthetic private cache only; no OAuth login, network or real Remote used.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Source'
. (Join-Path $source 'rc1-owner-gui.ps1')
$pass=0;$fail=0
function Check([bool]$ok,[string]$name){
 if($ok){$script:pass++;Write-Output ('PASS '+$name)}
 else{$script:fail++;Write-Output ('FAIL '+$name)}
}
$now=[DateTime]::UtcNow
$file=Join-Path $env:TEMP ('RdcQuota-'+[guid]::NewGuid().ToString('N')+'.json')
function Put($percent,$email,$date,$origin){
 $data=@{remainingPercent=$percent;accountEmail=$email;observedAtUtc=$date;source=$origin}
 [IO.File]::WriteAllText($file,($data|ConvertTo-Json -Compress),[Text.Encoding]::UTF8)
}
try {
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'no cache means unknown, not fake 94%'
 $iso=$now.ToString('yyyy-MM-ddTHH:mm:ssZ',[Globalization.CultureInfo]::InvariantCulture)
 Put 94 'tester@example.org' $iso 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов 94%') 'fresh official quota is shown'
 Check ((Get-Rc1QuotaStatus $file 'other@example.org' $now) -ceq 'Остаток вызовов —') 'quota cannot leak across different account'
 Put 0 'tester@example.org' $iso 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов 0%') 'zero percent is valid'
 Put 100 'tester@example.org' $iso 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов 100%') '100 percent is valid'
 Put 101 'tester@example.org' $iso 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'reject out of range'
 Put 'nope' 'tester@example.org' $iso 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'reject nonnumber'
 Put 94 'tester@example.org' $iso 'untrusted-local-guess'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'reject wrong provenance'
 Put 94 'tester@example.org' $now.AddMinutes(-59).ToString('yyyy-MM-ddTHH:mm:ssZ') 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов 94%') 'last confirmed value remains visible just before one hour'
 $nowExact=$now.AddTicks(-($now.Ticks % [TimeSpan]::TicksPerSecond))
 Put 94 'tester@example.org' $nowExact.AddMinutes(-60).ToString('yyyy-MM-ddTHH:mm:ssZ') 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $nowExact) -ceq 'Остаток вызовов —') 'value becomes unavailable exactly at one hour'
 Put 94 'tester@example.org' $now.AddMinutes(-61).ToString('yyyy-MM-ddTHH:mm:ssZ') 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'stale value stays hidden after one hour'
 Put 94 'tester@example.org' $now.AddMinutes(3).ToString('yyyy-MM-ddTHH:mm:ssZ') 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'reject excessive future date'
 [IO.File]::WriteAllText($file,('A'*1000),[Text.Encoding]::UTF8)
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'bounded cache size'
 $layout=[IO.File]::ReadAllText((Join-Path $source 'remote-window.ps1'),[Text.Encoding]::UTF8)
 $owner=[IO.File]::ReadAllText((Join-Path $source 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
 Check ($layout.Contains('$infoHost.Controls.Add($accountSep)') -and
 $layout.Contains('$infoHost.Controls.Add($runtimeSep)') -and
 $layout.Contains('$accountSep.Margin = New-Object Windows.Forms.Padding(6,2,6,0)') -and
 $layout.Contains('$runtimeSep.Margin = New-Object Windows.Forms.Padding(6,2,6,0)') -and
 $layout.Contains('$accountSep.ForeColor = $accentOrange') -and
 $layout.Contains('$runtimeSep.ForeColor = $accentOrange')) 'owner and legacy use original 1.5.18 orange pipe separators'
 Check ($layout.Contains('if(-not $OwnerGui){$infoHost.Controls.Add($runtimeLeft)}') -and
 $layout.Contains('if($OwnerGui){$infoHost.Controls.Add($quotaLabel)}') -and
 $layout.IndexOf('$infoHost.Controls.Add($quotaLabel)') -lt $layout.IndexOf('$infoHost.Controls.Add($runtimeRight)')) 'RC1 footer shows account, quota, uptime without PID; legacy retains PID'
 Check ($layout.Contains('if(-not $OwnerGui){') -and
 $layout.Contains('$hintHost.Controls.Add($hintVersion)') -and
 $layout.Contains('if($OwnerGui){110}else{440}')) 'version right aligned in narrow owner-only corner column'
Check ($layout.Contains('$script:ownerVersionIntroTimer.Interval=25') -and
 $layout.Contains('if([Windows.Forms.SystemInformation]::HighContrast)') -and
 $layout.Contains('$script:ownerVersionIntroTimer.Dispose()')) 'version fades into far corner with high-contrast and disposal safeguards'
 Check ($layout.Contains('$quotaLabel.Margin = New-Object Windows.Forms.Padding(0,2,0,0)') -and
 $layout.Contains('$runtimeRight.Margin = New-Object Windows.Forms.Padding(0,2,0,0)') -and
 $layout.Contains('Остаток вызовов —')) 'owner quota and uptime align after stable separators'
 Check ($layout.Contains('$hintVersion.Font = if($OwnerGui){$form.Font}else{$hint.Font}') -and
 $layout.Contains('$form.Font = New-Object Drawing.Font('+"'Segoe UI',10"+')') -and
 $layout.Contains('$hintVersion.ForeColor = if($OwnerGui){$accountInfo.ForeColor}else{[Drawing.Color]::Gray}') -and
 $layout.Contains('$hintVersion.Margin = New-Object Windows.Forms.Padding(0,$(if($OwnerGui){2}else{6}),0,0)') -and
 $layout.Contains('$to=$accountInfo.ForeColor') -and
 $layout.Contains('$hintVersion.ForeColor=$accountInfo.ForeColor')) 'version matches owner footer typography, color and adjusted baseline, including fade completion'
 Check ($layout.Contains("'PID Remote: ' + "+'$helpPid') -and
 $layout.Contains('$script:ownerRemotePid') -and
 $layout.Contains('Закрытие окна закрывает только GUI') -and
 -not $layout.Contains('Host запускает Desktop Commander Remote 0.2.52 в отдельной проверяемой Windows Job.')) 'About explains lifecycle in plain language and shows current Remote PID last'
 Check ($layout.Contains('if(-not $OwnerGui){[void]$accountMenu.Items.Add($verifyDeviceItem)}') -and
 $layout.Contains('if($OwnerGui){[void]$accountMenu.Items.Add($quotaAuthItem)}')) 'RC1 hides redundant device verification but keeps manual quota link'
 $hostRuntime=[IO.File]::ReadAllText((Join-Path $source 'RdcOwnerRuntime.cs'),[Text.Encoding]::UTF8)
 Check ($hostRuntime.Contains('{"deviceVerificationLink",false}') -and
 -not $hostRuntime.Contains('if(destination=="DEVICE_VERIFICATION")')) 'RC1 Host refuses redundant device verification navigation'
 Check (-not $owner.Contains("('Remote PID '") -and -not $owner.Contains("Set-RuntimeDisplay 'Remote PID")) 'PID label omits word Remote'
 Check ($layout.Contains("$"+'quotaAuthItem.Add_Click({') -and
 $layout.Contains("$"+'quotaAuthItem.Visible=[bool]$OwnerGui') -and
 $owner.Contains('quotaAuthItem.Enabled=$script:ownerRealMode')) 'OAuth authorization requires explicit owner Account click'
 Check ($owner.Contains('Остаток вызовов 0%') -and $owner.Contains('[Drawing.Color]::LightCoral')) 'genuine zero remaining appears in red'
 Check ($owner.Contains('Get-Rc1QuotaStatus $script:ownerQuotaPath') -and
 $owner.Contains('AddSeconds(15)')) 'quota file polled without remote OAuth or UI thread network calls'
 $errors=$null;$tokens=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'remote-window.ps1'),[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'legacy shell and owner footer parse'
 # Execute the exact production setter against disposable label stand-ins;
 # a source check alone missed the old owner-only separator suppression.
 $setter=$ast.Find({param($node)
   $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
   $node.Name -ceq 'Set-RuntimeDisplay'
 },$true)
 if($setter){
  . ([scriptblock]::Create($setter.Extent.Text))
  foreach($ownerMode in @($true,$false)){
   $OwnerGui=$ownerMode
   $runtimeLeft=[pscustomobject]@{Text=''}
   $runtimeRight=[pscustomobject]@{Text='';Visible=$false}
   $runtimeSep=[pscustomobject]@{Visible=$false}
   Set-RuntimeDisplay 'PID 42' 'Время работы 00:03:00' $true
   Check ($runtimeSep.Visible -and $runtimeRight.Visible -and
    $runtimeRight.Text -ceq 'Время работы 00:03:00') ('runtime divider visible with uptime, owner='+$ownerMode)
   Set-RuntimeDisplay 'PID 42' '' $true
   Check (-not $runtimeSep.Visible -and -not $runtimeRight.Visible) ('runtime divider hidden with no uptime, owner='+$ownerMode)
  }
 }else{Check $false 'production runtime setter found for executable regression'}
 # Control construction without installing or launching Remote proves the
 # owner's version inherits the actual 10pt Form font, not an early 8.25pt
 # default from a not-yet-parented FlowLayoutPanel.
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 $probeForm=New-Object Windows.Forms.Form
 try{
  $probeForm.Font=New-Object Drawing.Font('Segoe UI',10)
  $probePanel=New-Object Windows.Forms.FlowLayoutPanel
  $probeAccount=New-Object Windows.Forms.Label
  $probeVersion=New-Object Windows.Forms.Label
  $probeVersion.Font=$probeForm.Font
  $probeForm.Controls.Add($probePanel)
  $probePanel.Controls.Add($probeAccount)
  $probePanel.Controls.Add($probeVersion)
  Check ([Math]::Abs($probeAccount.Font.SizeInPoints-$probeVersion.Font.SizeInPoints) -lt 0.01 -and
   $probeAccount.PreferredHeight -eq $probeVersion.PreferredHeight) 'version 10pt label and account share line-height after parent layout'
 }finally{$probeForm.Dispose()}
 $errors=$null;$tokens=$null
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'rc1-owner-gui.ps1'),[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'owner quota helper syntax parses'
}finally{if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
Write-Output ('RC1_QUOTA_FOOTER_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
