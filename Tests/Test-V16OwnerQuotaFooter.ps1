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
 Put 94 'tester@example.org' $now.AddMinutes(-91).ToString('yyyy-MM-ddTHH:mm:ssZ') 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'stale data expires after a 90-minute hourly-poll allowance'
 Put 94 'tester@example.org' $now.AddMinutes(3).ToString('yyyy-MM-ddTHH:mm:ssZ') 'official-remote-who-am-i'
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'reject excessive future date'
 [IO.File]::WriteAllText($file,('A'*1000),[Text.Encoding]::UTF8)
 Check ((Get-Rc1QuotaStatus $file 'tester@example.org' $now) -ceq 'Остаток вызовов —') 'bounded cache size'
 $layout=[IO.File]::ReadAllText((Join-Path $source 'remote-window.ps1'),[Text.Encoding]::UTF8)
 $owner=[IO.File]::ReadAllText((Join-Path $source 'rc1-owner-gui.ps1'),[Text.Encoding]::UTF8)
 Check ($layout.Contains('if(-not $OwnerGui){$infoHost.Controls.Add($runtimeSep)}') -and
 $layout.Contains('if(-not $OwnerGui){$infoHost.Controls.Add($accountSep)}')) 'owner hides both footer dividers while legacy keeps them'
 Check ($layout.Contains('if($OwnerGui){$infoHost.Controls.Add($quotaLabel)}') -and
 $layout.IndexOf('$infoHost.Controls.Add($runtimeLeft)') -lt $layout.IndexOf('$infoHost.Controls.Add($quotaLabel)') -and
 $layout.IndexOf('$infoHost.Controls.Add($quotaLabel)') -lt $layout.IndexOf('$infoHost.Controls.Add($runtimeRight)')) 'quota is between PID and uptime'
 Check ($layout.Contains('if(-not $OwnerGui){') -and
 $layout.Contains('$hintHost.Controls.Add($hintVersion)') -and
 $layout.Contains('if($OwnerGui){110}else{440}')) 'version right aligned in narrow owner-only corner column'
Check ($layout.Contains('$script:ownerVersionIntroTimer.Interval=25') -and
 $layout.Contains('if([Windows.Forms.SystemInformation]::HighContrast)') -and
 $layout.Contains('$script:ownerVersionIntroTimer.Dispose()')) 'version fades into far corner with high-contrast and disposal safeguards'
 Check ($layout.Contains('if($OwnerGui){'+'$runtimeLeft.Margin=') -and
 $layout.Contains('Остаток вызовов —')) 'owner has neutral spacing and unavailable label'
 Check (-not $owner.Contains("('Remote PID '") -and -not $owner.Contains("Set-RuntimeDisplay 'Remote PID")) 'PID label omits word Remote'
 Check ($layout.Contains("$"+'quotaAuthItem.Add_Click({') -and
 $layout.Contains("$"+'quotaAuthItem.Visible=[bool]$OwnerGui') -and
 $owner.Contains('quotaAuthItem.Enabled=$script:ownerRealMode')) 'OAuth authorization requires explicit owner Account click'
 Check ($owner.Contains('Остаток вызовов 0%') -and $owner.Contains('[Drawing.Color]::LightCoral')) 'genuine zero remaining appears in red'
 Check ($owner.Contains('Get-Rc1QuotaStatus $script:ownerQuotaPath') -and
 $owner.Contains('AddSeconds(15)')) 'quota file polled without remote OAuth or UI thread network calls'
 $errors=$null;$tokens=$null
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'remote-window.ps1'),[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'legacy shell and owner footer parse'
 $errors=$null;$tokens=$null
 [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'rc1-owner-gui.ps1'),[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'owner quota helper syntax parses'
}finally{if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
Write-Output ('RC1_QUOTA_FOOTER_PASS='+$pass+' FAIL='+$fail)
if($fail){exit 1}
exit 0
