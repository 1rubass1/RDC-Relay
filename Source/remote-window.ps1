param([switch]$SelfTest,[switch]$SkipUpdate,[switch]$Preview,[switch]$OwnerGui,[string]$OwnerTicketPath='',[string]$OwnerTrialRoot='')
$ErrorActionPreference = 'Stop'
if($OwnerGui){
 if($SelfTest -or $Preview -or [string]::IsNullOrWhiteSpace($OwnerTicketPath)){
  throw 'RC1_OWNER_GUI_REQUIRES_PRIVATE_TICKET'
 }
 # Suppresses legacy process/startup/update/user registry side effects.
 # A separate Host owns all lifecycle operations in this branch.
 $Preview=$true
}
$root = $PSScriptRoot
# Branch-only RC1 source marker blocks accidental legacy GUI execution against
# a real Remote from the candidate checkout or a staged owner payload.
if(-not $SelfTest -and -not $Preview -and -not $OwnerGui -and
   [IO.File]::Exists((Join-Path $root 'rc1-candidate.json'))){
 throw 'RC1_DEFAULT_LEGACY_REMOTE_LAUNCH_BLOCKED'
}
$appVersion = if($OwnerGui){'1.6.0 RC1'}else{
    $versionFile=Join-Path $root 'version.txt'
    if(-not [IO.File]::Exists($versionFile)){throw 'RDC_RELEASE_VERSION_FILE_MISSING'}
    $installedVersion=[IO.File]::ReadAllText($versionFile,[Text.Encoding]::UTF8).Trim()
    if($installedVersion -cnotmatch '^\d+\.\d+\.\d+$'){throw 'RDC_RELEASE_VERSION_INVALID'}
    $installedVersion
}
# Flip to $false to remove the optional update notice and restore the original
# startup auto-updater/footer with no other runtime or UI modifications.
$script:enableUpdateNotice = -not $OwnerGui
# Owner pilot: retain the accepted compact read-only update notice UI, but
# NEVER offer an invented RC2. Only the official published stable manifest
# may activate it. Candidate installation/auto-update remain blocked.
$script:ownerUpdateDemoMode=[bool]($OwnerGui -and -not $SelfTest)
if($script:ownerUpdateDemoMode){$script:enableUpdateNotice=$true}
$script:updateInstallRequested = $false
# Per-user auto-update startup-install preference. Missing marker = ON.
# The passive version notice and explicit update-button action NEVER consult
# this setting; a denied RC1 installer remains denied regardless of this value.
$script:autoUpdatePreferencePath=Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'RDCRelayOwnerPilot') 'auto-update.opt-out'
function Test-RdcAutoUpdateEnabled([string]$path) {
    try {
        if([string]::IsNullOrWhiteSpace($path)){return $false}
        if(-not [IO.File]::Exists($path)){return $true}
        $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           ($file.Length -ne 10 -and $file.Length -ne 11)){return $false}
        return [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -ceq 'enabled-v1'
    }catch{return $false}
}
function Set-RdcAutoUpdateEnabled([string]$path,[bool]$enabled) {
    if([string]::IsNullOrWhiteSpace($path)){throw 'RC1_AUTO_UPDATE_PATH_REQUIRED'}
    $dir=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
    if(-not $dir){throw 'RC1_AUTO_UPDATE_PARENT_REQUIRED'}
    if([IO.Directory]::Exists($dir) -and
      ([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'RC1_AUTO_UPDATE_REPARSE_DENIED'
    }
    if($enabled){
        if([IO.File]::Exists($path)){
            if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'RC1_AUTO_UPDATE_REPARSE_DENIED'
            }
            [IO.File]::Delete($path)
        }
        if([IO.File]::Exists($path)){throw 'RC1_AUTO_UPDATE_ENABLE_FAILED'}
        return
    }
    if(-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'RC1_AUTO_UPDATE_REPARSE_DENIED'
    }
    $temp=Join-Path $dir ('auto-update-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    $backup=Join-Path $dir ('auto-update-'+[Guid]::NewGuid().ToString('N')+'.bak')
    try {
        [IO.File]::WriteAllText($temp,'disabled-v1',(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($path)){
            if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'RC1_AUTO_UPDATE_REPARSE_DENIED'
            }
            [IO.File]::Replace($temp,$path,$backup)
        }else{[IO.File]::Move($temp,$path)}
        if([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -cne 'disabled-v1'){
            throw 'RC1_AUTO_UPDATE_VERIFY_FAILED'
        }
    }finally{
        if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
        if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
    }
}
$desktopCommanderPackage = '@wonderwhy-er/desktop-commander@latest'
$logPath = Join-Path $root 'remote-session.log'
$iconPath = Join-Path $root 'RDCRelay.ico'

if (-not ('RdcShellIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RdcShellIdentity {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(
        uint eventId,
        uint flags,
        IntPtr item1,
        IntPtr item2);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
}

try {
    $ownerAppId=if($OwnerGui){'RDCRelay.OwnerPilot.1_6_RC1'}else{'RDCRelay.App'}
    [void][RdcShellIdentity]::SetCurrentProcessExplicitAppUserModelID($ownerAppId)
} catch {}


function Test-RdcShortcutOwner([string]$Path) {
    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)
        $scriptPath = Join-Path $root 'remote-window.ps1'
        $isPowerShell = [IO.Path]::GetFileName($shortcut.TargetPath) -ieq 'powershell.exe'
        if ($isPowerShell -and $shortcut.Arguments -match ('(?i)(?:^|\s)-File\s+"' + [regex]::Escape($scriptPath) + '"(?:\s|$)')) { return $true }
        foreach ($name in @('RDC Relay.exe','RDC Relay.cmd','Remote Desktop Commander.cmd','CommanderRelay.cmd')) {
            if ([string]::Equals($shortcut.TargetPath,(Join-Path $root $name),[StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    } catch { return $false }
    finally {
        if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

# Branding migration cleanup. Keep the legacy install directory/mutex for
# compatibility, but remove obsolete launchers once the new payload exists.
if (-not $SelfTest -and -not $Preview -and (Test-Path -LiteralPath (Join-Path $root 'RDC Relay.cmd'))) {
    foreach ($legacyLauncher in @('Remote Desktop Commander.cmd','CommanderRelay.cmd')) {
        try {
            $legacyPath = Join-Path $root $legacyLauncher
            if (Test-Path -LiteralPath $legacyPath) {
                Remove-Item -LiteralPath $legacyPath -Force -ErrorAction Stop
            }
        } catch {}
    }

    $shortcutRoots = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory),
        [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    )

    foreach ($shortcutRoot in $shortcutRoots) {
        if ([string]::IsNullOrWhiteSpace($shortcutRoot)) { continue }

        $newShortcut = Join-Path $shortcutRoot 'RDC Relay.lnk'
        foreach ($legacyShortcutName in @(
            'Remote Desktop Commander.lnk',
            'CommanderRelay.lnk'
        )) {
            try {
                $legacyShortcut = Join-Path $shortcutRoot $legacyShortcutName
                if (-not (Test-Path -LiteralPath $legacyShortcut)) { continue }
                if (-not (Test-RdcShortcutOwner $legacyShortcut)) { continue }

                if (Test-Path -LiteralPath $newShortcut) {
                    Remove-Item -LiteralPath $legacyShortcut -Force -ErrorAction Stop
                } else {
                    Move-Item -LiteralPath $legacyShortcut -Destination $newShortcut -Force -ErrorAction Stop
                }
            } catch {}
        }
    }

}

function Sync-RdcShortcuts([string[]]$ShortcutRootsOverride = $null) {
    if (($SelfTest -or $Preview) -and (-not $ShortcutRootsOverride -or $ShortcutRootsOverride.Count -eq 0)) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $iconPath)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'RDC Relay.cmd'))) { return $false }

    try {
        $shortcutRoots = if ($ShortcutRootsOverride -and $ShortcutRootsOverride.Count -gt 0) {
            @($ShortcutRootsOverride)
        } else {
            @(
                [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory),
                [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
            )
        }

        $iconHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $iconPath).Hash.Substring(0,8)
        $shortcutIcon = Join-Path $root ('RDCRelay-v' + $appVersion + '-' + $iconHash + '.ico')
        if (-not (Test-Path -LiteralPath $shortcutIcon)) {
            Copy-Item -LiteralPath $iconPath -Destination $shortcutIcon -Force
        }

        $powershellDir = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0'
        $expectedTarget = Join-Path $powershellDir 'powershell.exe'
        $expectedArgs = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
            (Join-Path $root 'remote-window.ps1') + '"'
        $expectedIcon = $shortcutIcon + ',0'

        $shell = New-Object -ComObject WScript.Shell
        $hadShortcut = $false
        $allSynced = $true

        try {
            foreach ($shortcutRoot in $shortcutRoots) {
                if ([string]::IsNullOrWhiteSpace($shortcutRoot)) { continue }

                $shortcutPath = Join-Path $shortcutRoot 'RDC Relay.lnk'
                if (-not (Test-Path -LiteralPath $shortcutPath)) { continue }
                if (-not (Test-RdcShortcutOwner $shortcutPath)) { continue }
                $hadShortcut = $true
                $saved = $false

                for ($attempt = 1; $attempt -le 4 -and -not $saved; $attempt++) {
                    $shortcut = $null
                    try {
                        $shortcut = $shell.CreateShortcut($shortcutPath)
                        $shortcut.TargetPath = $expectedTarget
                        $shortcut.Arguments = $expectedArgs
                        $shortcut.WorkingDirectory = $root
                        $shortcut.IconLocation = $expectedIcon
                        $shortcut.Description = 'RDC Relay'
                        $shortcut.Save()
                    }
                    catch {}
                    finally {
                        if ($shortcut) {
                            try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) } catch {}
                            $shortcut = $null
                        }
                    }

                    $verify = $null
                    try {
                        $verify = $shell.CreateShortcut($shortcutPath)
                        $saved =
                            $verify.TargetPath -eq $expectedTarget -and
                            $verify.Arguments -eq $expectedArgs -and
                            $verify.WorkingDirectory -eq $root -and
                            $verify.IconLocation -eq $expectedIcon -and
                            $verify.Description -eq 'RDC Relay'
                    }
                    catch {
                        $saved = $false
                    }
                    finally {
                        if ($verify) {
                            try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verify) } catch {}
                            $verify = $null
                        }
                    }

                    if (-not $saved -and $attempt -lt 4) {
                        Start-Sleep -Milliseconds (150 * $attempt)
                    }
                }

                if (-not $saved) { $allSynced = $false }
            }
        }
        finally {
            try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } catch {}
        }

        if ($allSynced -and $hadShortcut) {
            try {
                Get-ChildItem -LiteralPath $root -Filter 'DesktopCommander*.ico' -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Get-ChildItem -LiteralPath $root -Filter 'RDCRelay-v*.ico' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -ne $shortcutIcon } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } catch {}

            if (-not $SelfTest) {
                try {
                    [RdcShellIdentity]::SHChangeNotify(
                        0x08000000,
                        0,
                        [IntPtr]::Zero,
                        [IntPtr]::Zero)
                } catch {}

                try {
                    $iconRefresh = Join-Path $env:WINDIR 'System32\ie4uinit.exe'
                    if (Test-Path -LiteralPath $iconRefresh) {
                        Start-Process -FilePath $iconRefresh -ArgumentList '-show' -WindowStyle Hidden
                    }
                } catch {}
            }
        }

        return $allSynced
    }
    catch {
        if ($SelfTest) {
            Write-Host ('SHORTCUT_SYNC_ERROR: ' + $_.Exception.GetType().FullName + ': ' + $_.Exception.Message)
        }
        return $false
    }
}

function Ensure-InstalledAppRegistration {
    if ($SelfTest -or $Preview) { return $false }

    $defaultRoot = [IO.Path]::GetFullPath(
        (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'RemoteDesktopCommanderLauncher')
    ).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $currentRoot = [IO.Path]::GetFullPath($root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if (-not [string]::Equals($currentRoot,$defaultRoot,[StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $bs = [char]92
    $keyPath =
        'Software'+$bs+'Microsoft'+$bs+'Windows'+$bs+'CurrentVersion'+$bs+
        'Uninstall'+$bs+'RDC Relay'
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($keyPath)
    if (-not $key) { return $false }

    try {
        $powershell = Join-Path (Join-Path (Join-Path (Join-Path $env:WINDIR 'System32') 'WindowsPowerShell') 'v1.0') 'powershell.exe'
        $updater = Join-Path $root 'update.ps1'
        $quote = [char]34
        $baseArgs =
            '-NoProfile -ExecutionPolicy Bypass -File ' + $quote + $updater + $quote +
            ' -InstallRoot ' + $quote + $root + $quote +
            ' -CurrentVersion ' + $quote + $appVersion + $quote +
            ' -Uninstall'
        $uninstall = $quote + $powershell + $quote + ' ' + $baseArgs

        $bytes = 0L
        try {
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object { $bytes += [long]$_.Length }
        } catch {}
        $estimatedKb = [Math]::Max(1,[Math]::Min([int]::MaxValue,[Math]::Ceiling($bytes/1024.0)))

        $key.SetValue('DisplayName','RDC Relay',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('DisplayVersion',$appVersion,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('Publisher','RUBASS',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('InstallLocation',$root,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('DisplayIcon',$iconPath,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('URLInfoAbout','https://github.com/Rubo-Facility/RDC-Relay',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('UninstallString',$uninstall,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('QuietUninstallString',$uninstall+' -Silent',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('NoModify',1,[Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('NoRepair',1,[Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('EstimatedSize',[int]$estimatedKb,[Microsoft.Win32.RegistryValueKind]::DWord)
        return $true
    }
    finally {
        $key.Dispose()
    }
}

function Resolve-NpxPath {
    $resolved = Get-Command npx.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved -and $resolved.Source) { return [string]$resolved.Source }

    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'nodejs\npx.cmd') }
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) { $candidates += (Join-Path $programFilesX86 'nodejs\npx.cmd') }
    if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'npm\npx.cmd') }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw 'npx.cmd не найден. Установите Node.js 18 или новее.'
}

$windowMutex = $null
if (-not $SelfTest -and -not $OwnerGui) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLowerInvariant()))).Replace('-','')
    $sha.Dispose()
    $windowMutex = New-Object Threading.Mutex($false,('Local\RemoteDesktopCommanderWindow-'+$key))
    try { $ownsWindow = $windowMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsWindow = $true }
    if (-not $ownsWindow) {
        # A second launcher should reactivate the existing GUI. If the mutex
        # owner has become a stale PowerShell process with no top-level window,
        # recycle only that GUI process and take over the mutex.
        $runtimeNeedle = Join-Path $PSScriptRoot 'remote-window.ps1'
        $peerProcesses = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProcessId -ne $PID -and
                    $_.Name -eq 'powershell.exe' -and
                    $_.CommandLine -and
                    $_.CommandLine.IndexOf($runtimeNeedle,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $_.CommandLine -notmatch '(?i)-SelfTest|-Preview'
                }
        )

        $reactivated = $false
        $reactivateDeadline = (Get-Date).AddSeconds(1.5)
        do {
            foreach ($peer in $peerProcesses) {
                try {
                    $peerProcess = Get-Process -Id $peer.ProcessId -ErrorAction Stop
                    if ($peerProcess.MainWindowHandle -ne [IntPtr]::Zero) {
                        [void][RdcShellIdentity]::ShowWindow($peerProcess.MainWindowHandle,9)
                        [void][RdcShellIdentity]::SetForegroundWindow($peerProcess.MainWindowHandle)
                        $reactivated = $true
                        break
                    }
                } catch {}
            }
            if (-not $reactivated) { Start-Sleep -Milliseconds 100 }
        } while (-not $reactivated -and (Get-Date) -lt $reactivateDeadline)

        if ($reactivated) {
            $windowMutex.Dispose()
            exit 0
        }

        $staleStopped = $false
        foreach ($peer in $peerProcesses) {
            try {
                $peerProcess = Get-Process -Id $peer.ProcessId -ErrorAction Stop
                $ageSeconds = ((Get-Date) - $peerProcess.StartTime).TotalSeconds
                if ($peerProcess.MainWindowHandle -eq [IntPtr]::Zero -and $ageSeconds -ge 5.0) {
                    Stop-Process -Id $peer.ProcessId -Force -ErrorAction Stop
                    $staleStopped = $true
                }
            } catch {}
        }

        if ($staleStopped) {
            Start-Sleep -Milliseconds 350
            try {
                $ownsWindow = $windowMutex.WaitOne(1500)
            } catch [Threading.AbandonedMutexException] {
                $ownsWindow = $true
            }
        }

        if (-not $ownsWindow) {
            $windowMutex.Dispose()
            exit 0
        }
    }
}

# The updater is launched from Shown, after the window owns its mutex.
$script:updateProc = $null
$script:initializing = $false
$script:remoteOperation = $null
$script:allowClose = $false
$script:closeRequested = $false

# Fresh setup registers this immediately. This second path makes an existing
# installation become a normal Installed Apps entry after an in-place update.
if (-not $SelfTest -and -not $Preview) {
    try { [void](Ensure-InstalledAppRegistration) } catch {}
}

Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class RdcNativeWindow {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        int dwAttribute,
        ref int pvAttribute,
        int cbAttribute
    );
}

public class RdcMenuColorTable : ProfessionalColorTable {
    private readonly Color accent = Color.FromArgb(191,118,67);
    private readonly Color accentSoft = Color.FromArgb(166,98,55);

    public RdcMenuColorTable() {
        UseSystemColors = false;
    }

    public override Color ImageMarginGradientBegin { get { return accent; } }
    public override Color ImageMarginGradientMiddle { get { return accent; } }
    public override Color ImageMarginGradientEnd { get { return accent; } }

    public override Color CheckBackground { get { return accent; } }
    public override Color CheckPressedBackground { get { return accentSoft; } }
    public override Color CheckSelectedBackground { get { return accent; } }

    // Keep the selection outline fully opaque, but let the menu surface show
    // through the purple interior at exactly half alpha.
    public override Color MenuItemSelected { get { return Color.FromArgb(128,91,67,126); } }
    public override Color MenuItemBorder { get { return Color.FromArgb(123,95,162); } }
    public override Color MenuItemPressedGradientBegin { get { return Color.FromArgb(128,74,55,103); } }
    public override Color MenuItemPressedGradientMiddle { get { return Color.FromArgb(128,74,55,103); } }
    public override Color MenuItemPressedGradientEnd { get { return Color.FromArgb(128,74,55,103); } }
}

// Owner-only checkbox affordance: the orange image-margin is shared by all
// Account commands, so show an actual high-contrast square for the quota toggle.
// ToolStripMenuItem still owns Checked/CheckOnClick, keyboard and accessibility.
public class RdcOwnerAccountMenuRenderer : ToolStripProfessionalRenderer {
    // Both Account and tray share the same user-affordance painter.
    // Names are intentionally bounded to the four known checkbox actions.
    private const string QuotaItemName = "rc1-quota-display-toggle";
    private const string AutoUpdateItemName = "rc1-auto-update-toggle";
    private const string TrayQuotaItemName = "rc1-tray-quota-toggle";
    private const string TrayAutoUpdateItemName = "rc1-tray-auto-update-toggle";
    public const int CornerRadius = 6; // RdcRoundedButton.OnPaint Rounded(r,6f)
    private static bool IsCheckItem(ToolStripItem item) {
        if (item == null) return false;
        return item.Name == QuotaItemName || item.Name == AutoUpdateItemName ||
               item.Name == TrayQuotaItemName || item.Name == TrayAutoUpdateItemName ||
               item.Name == "rc1-auto-connect-toggle" || item.Name == "rc1-tray-auto-connect-toggle" ||
               item.Name == "rc1-tray-auto-start-toggle" ||
               item.Name == "rc1-tray-language_ru" || item.Name == "rc1-tray-language_en";
    }

    public RdcOwnerAccountMenuRenderer(ProfessionalColorTable colors) : base(colors) { }

    // Owner Account only: remove the orange image-column fill without
    // changing the shared color table (used by the Help and legacy menus).
    // Use the actual menu BackColor so the glyph gutter joins the text area.
    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) {
        using (Brush brush = new SolidBrush(e.ToolStrip.BackColor))
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
    }

    public static Rectangle QuotaBoxBounds(ToolStripItem item) {
        const int side = 16;
        // Owner-approved correction: retain the 3px horizontal inset
        // and lower the prior glyph position by exactly one pixel.
        return new Rectangle(8, Math.Max(0, (item.Height - side) / 2), side, side);
    }

    public static void PaintQuotaBox(Graphics g, ToolStripMenuItem item) {
        Rectangle rect = QuotaBoxBounds(item);
        if (rect.Right > item.Width || rect.Bottom > item.Height) return;

        SmoothingMode oldSmoothing = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        try {
            // Let Windows supply actual contrast colors when High Contrast is on.
            bool highContrast = SystemInformation.HighContrast;
            Color fill = highContrast
                ? (item.Checked ? SystemColors.Highlight : SystemColors.Window)
                : (item.Enabled
                  ? (item.Checked ? Color.FromArgb(63, 46, 82) : Color.FromArgb(37, 40, 47))
                  : Color.FromArgb(66, 66, 70));
            Color outline = highContrast
                ? (item.Checked ? SystemColors.HighlightText : SystemColors.WindowText)
                : (!item.Enabled ? Color.FromArgb(148, 148, 148)
                  : (item.Selected ? Color.White
                  : (item.Checked ? Color.FromArgb(255, 224, 160) : Color.FromArgb(238, 238, 238))));
            using (Brush brush = new SolidBrush(fill))
                g.FillRectangle(brush, rect);
            using (Pen border = new Pen(outline, 1.35f))
                g.DrawRectangle(border, rect.X + 0.65f, rect.Y + 0.65f,
                                rect.Width - 1.3f, rect.Height - 1.3f);
            if (item.Checked) {
                Color tick = highContrast ? SystemColors.HighlightText
                    : (item.Enabled ? Color.White : Color.FromArgb(195, 195, 195));
                using (Pen pen = new Pen(tick, 2.15f)) {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    g.DrawLines(pen, new PointF[] {
                        new PointF(rect.X + 3.5f, rect.Y + 8.0f),
                        new PointF(rect.X + 6.6f, rect.Y + 11.2f),
                        new PointF(rect.X + 12.3f, rect.Y + 4.9f)
                    });
                }
            }
        } finally { g.SmoothingMode = oldSmoothing; }
    }

    // Single contract for both popup surfaces. The Region clips the actual
    // native drop-down HWND, not just a painted fake rounded border.
    public static GraphicsPath RoundedMenuPath(RectangleF bounds) {
        GraphicsPath path = new GraphicsPath();
        float r = Math.Min(CornerRadius, Math.Min(bounds.Width,bounds.Height)/2f);
        if(r<=0){path.AddRectangle(bounds);return path;}
        float d=2f*r;
        path.AddArc(bounds.Left,bounds.Top,d,d,180f,90f);
        path.AddArc(bounds.Right-d,bounds.Top,d,d,270f,90f);
        path.AddArc(bounds.Right-d,bounds.Bottom-d,d,d,0f,90f);
        path.AddArc(bounds.Left,bounds.Bottom-d,d,d,90f,90f);
        path.CloseFigure();
        return path;
    }
    public static void ApplyRoundedRegion(ContextMenuStrip menu) {
        if(menu==null||menu.IsDisposed||menu.Width<=CornerRadius*2||
           menu.Height<=CornerRadius*2)return;
        using(GraphicsPath p=RoundedMenuPath(new RectangleF(0f,0f,menu.Width,menu.Height))){
            Region previous=menu.Region;
            menu.Region=new Region(p);
            if(previous!=null)previous.Dispose();
        }
    }
    public static void ConfigureOwnerMenu(ContextMenuStrip menu){
        if(menu==null)throw new ArgumentNullException("menu");
        menu.BackColor=Color.FromArgb(38,41,46);
        menu.ForeColor=Color.Gainsboro;
        // Caller owns the renderer; this helper only owns the shared shape.
        menu.SizeChanged+=(s,e)=>ApplyRoundedRegion(menu);
        menu.Opening+=(s,e)=>ApplyRoundedRegion(menu);
        ApplyRoundedRegion(menu);
        // One extra pixel above every command row, not above separators.
        // Apply once when inserted, including language submenu items.
        foreach(ToolStripItem item in menu.Items)PadCommandRow(item);
        menu.ItemAdded+=(s,e)=>PadCommandRow(e.Item);
        // Cancel only the native ItemClicked dismissal for preference rows.
        // Escape, outside clicks, focus loss and explicit Close stay native.
        bool keepOpen=false;
        menu.Opening+=(s,e)=>keepOpen=false;
        menu.ItemClicked+=(s,e)=>{
            ToolStripMenuItem item=e.ClickedItem as ToolStripMenuItem;
            keepOpen=item!=null && (item.CheckOnClick ||
                item.Name=="rc1-tray-language_ru" || item.Name=="rc1-tray-language_en");
        };
        menu.Closing+=(s,e)=>{
            if(e.CloseReason==ToolStripDropDownCloseReason.ItemClicked && keepOpen)
                e.Cancel=true;
            keepOpen=false;
        };
    }
    static void PadCommandRow(ToolStripItem item){
        if(!(item is ToolStripMenuItem))return;
        Padding p=item.Padding;
        item.Padding=new Padding(p.Left,p.Top+1,p.Right,p.Bottom);
    }
    public static Rectangle SeparatorLineBounds(ToolStrip strip,ToolStripItem item){
        if(strip==null||item==null)return Rectangle.Empty;
        // OnRenderSeparator receives an ITEM-LOCAL graphics surface:
        // using item.Bounds.Top (menu coordinates) silently clips the
        // whole line out of the actual popup. Separator items start at
        // menu x=2 and end 2px from the opposite edge by native layout.
        return new Rectangle(0,item.Height/2,Math.Max(0,item.Width),1);
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e){
        if(!(e.ToolStrip is ContextMenuStrip)){base.OnRenderSeparator(e);return;}
        Rectangle line=SeparatorLineBounds(e.ToolStrip,e.Item);
        if(line.Width<=0)return;
        Color ink=SystemInformation.HighContrast
             ?SystemColors.WindowText:Color.FromArgb(188,195,207);
        using(Brush b=new SolidBrush(ink))e.Graphics.FillRectangle(b,line);
    }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e){
        if(!(e.ToolStrip is ContextMenuStrip)){base.OnRenderToolStripBorder(e);return;}
        Rectangle bounds=e.ToolStrip.ClientRectangle;
        if(bounds.Width<3||bounds.Height<3)return;
        SmoothingMode prev=e.Graphics.SmoothingMode;
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        try{
            using(GraphicsPath p=RoundedMenuPath(
                   new RectangleF(0.5f,0.5f,bounds.Width-1f,bounds.Height-1f)))
            using(Pen outline=new Pen(SystemInformation.HighContrast
                   ?SystemColors.WindowText:Color.FromArgb(110,118,130),1f)){
                e.Graphics.DrawPath(outline,p);
            }
        }finally{e.Graphics.SmoothingMode=prev;}
    }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if(!(e.ToolStrip is ContextMenuStrip)){
            base.OnRenderMenuItemBackground(e);
            return;
        }
        ToolStripMenuItem item=e.Item as ToolStripMenuItem;
        if(item==null){base.OnRenderMenuItemBackground(e);return;}
        // Paint *every* row on its item-local surface; inherited native
        // Professional hover rendering varies with system menus. One
        // explicit purple selection formula now serves Account and tray.
        using(Brush background=new SolidBrush(e.ToolStrip.BackColor))
            e.Graphics.FillRectangle(background,new Rectangle(Point.Empty,item.Size));
        if(item.Selected && item.Enabled){
            if(SystemInformation.HighContrast)base.OnRenderMenuItemBackground(e);
            else{
                SmoothingMode prior=e.Graphics.SmoothingMode;
                e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
                try{
                    // Selection outline is intentionally RECTANGULAR; only
                    // the outer menu window retains the 6px rounded region.
                    RectangleF selected = new RectangleF(
                        2.5f, 0.5f, Math.Max(0,item.Width-4f),
                        Math.Max(0,item.Height-1f));
                    using(Brush fill=new SolidBrush(Color.FromArgb(128,91,67,126)))
                    using(Pen edge=new Pen(Color.FromArgb(123,95,162),1f)){
                        e.Graphics.FillRectangle(fill,selected);
                        e.Graphics.DrawRectangle(edge,selected.X,selected.Y,
                                                 selected.Width,selected.Height);
                    }
                }finally{e.Graphics.SmoothingMode=prior;}
            }
        }
        if(IsCheckItem(item))PaintQuotaBox(e.Graphics,item);
        if(item.Name=="rc1-tray-auto-start-toggle" && item.Image!=null){
            Rectangle rect=RightArtworkBounds(item);
            if(item.Enabled)e.Graphics.DrawImage(item.Image,rect);
            else ControlPaint.DrawImageDisabled(e.Graphics,item.Image,rect.X,rect.Y,e.ToolStrip.BackColor);
        }
    }
    // Right-edge artwork lives outside the checkbox gutter. The tray reserves
    // room for it based on actual localized text widths.
    // Keep the accepted top edge; grow square artwork downward and about
    // its horizontal center. Odd-pixel growth is rounded toward the center.
    public static Rectangle LeftArtworkBounds(ToolStripItem item){
        Rectangle box=QuotaBoxBounds(item);
        int extra=item.Name=="rc1-tray-open"?3:(item.Name=="rc1-tray-auto-start-toggle"?2:1);
        return new Rectangle(box.X-extra/2,box.Y,box.Width+extra,box.Height+extra);
    }
    public static Rectangle RightArtworkBounds(ToolStripItem item){
        Rectangle left=LeftArtworkBounds(item);
        return new Rectangle(Math.Max(0,item.Width-left.Right),
            left.Y,left.Width,left.Height);
    }
    protected override void OnRenderItemImage(ToolStripItemImageRenderEventArgs e) {
        if(e.Item.Name=="rc1-tray-auto-start-toggle")return;
        if((e.Item.Name=="rc1-tray-help" || e.Item.Name=="rc1-tray-open") && e.Image!=null){
            Rectangle rect=LeftArtworkBounds(e.Item);
            e.Graphics.DrawImage(e.Image,rect);
            return;
        }
        Rectangle native=e.ImageRectangle;
        if(e.ToolStrip is ContextMenuStrip)native.Offset(0,1);
        base.OnRenderItemImage(new ToolStripItemImageRenderEventArgs(e.Graphics,e.Item,e.Image,native));
    }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) {
        if (IsCheckItem(e.Item)) return;
        Rectangle native=e.ImageRectangle;
        if(e.ToolStrip is ContextMenuStrip)native.Offset(0,1);
        base.OnRenderItemCheck(new ToolStripItemImageRenderEventArgs(e.Graphics,e.Item,e.Image,native));
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e){
        if(e.ToolStrip is ContextMenuStrip && e.Item is ToolStripMenuItem){
            Rectangle text=e.TextRectangle;
            text.Offset(0,1);
            e.TextRectangle=text;
        }
        base.OnRenderItemText(e);
    }
    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e){
        if(e.Item is ToolStripMenuItem && e.Item.Owner is ContextMenuStrip){
            Rectangle arrow=e.ArrowRectangle;
            arrow.Offset(0,1);
            e.ArrowRectangle=arrow;
        }
        base.OnRenderArrow(e);
    }
}

// Native ContextMenuStrip ignores direct Padding assignments in its
// ToolStripDropDownMenu layout. Override DefaultPadding instead so first and
// last rows clear the outer popup's 6px rounded corners by one extra pixel.
public class RdcOwnerPaddedContextMenuStrip : ContextMenuStrip {
    public const int ExtraEdgeSpace = RdcOwnerAccountMenuRenderer.CornerRadius + 1;
    protected override Padding DefaultPadding {
        get {
            Padding original = base.DefaultPadding;
            return new Padding(original.Left, original.Top + ExtraEdgeSpace,
                               original.Right, original.Bottom + ExtraEdgeSpace);
        }
    }
}

public class RdcCircleButton : Control {
    private bool hovered;
    private bool pressed;

    protected override void OnPaintBackground(PaintEventArgs e) {
        // This control is intentionally opaque. Transparent ButtonBase
        // composition can sample neighbouring controls into rounded corners.
        e.Graphics.Clear(BackColor);
    }

    public RdcCircleButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque, true);
        SetStyle(ControlStyles.SupportsTransparentBackColor, false);
        SetStyle(ControlStyles.Selectable, true);
        BackColor = Color.FromArgb(29,32,36);
        ForeColor = Color.FromArgb(248,248,248);
        Font = new Font("Segoe UI", 11f, FontStyle.Bold);
        Cursor = Cursors.Hand;
        TabStop = true;
        AccessibleRole = AccessibleRole.PushButton;
        Size = new Size(36,36);
    }

    protected override void OnMouseEnter(EventArgs e) {
        hovered = true; Invalidate(); base.OnMouseEnter(e);
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e);
    }
    private static bool IsActivationKey(Keys key) {
        return key == Keys.Space || key == Keys.Enter;
    }
    protected override bool IsInputKey(Keys keyData) {
        if (IsActivationKey(keyData & Keys.KeyCode)) return true;
        return base.IsInputKey(keyData);
    }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (Enabled && IsActivationKey(e.KeyCode)) {
            pressed = true;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
            return;
        }
        base.OnKeyDown(e);
    }
    protected override void OnKeyUp(KeyEventArgs e) {
        if (IsActivationKey(e.KeyCode)) {
            bool click = Enabled && pressed;
            pressed = false;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
            if (click) OnClick(EventArgs.Empty);
            return;
        }
        base.OnKeyUp(e);
    }
    protected override void OnGotFocus(EventArgs e) {
        base.OnGotFocus(e);
        Invalidate();
    }
    protected override void OnLostFocus(EventArgs e) {
        pressed = false;
        base.OnLostFocus(e);
        Invalidate();
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) {
            Focus();
            pressed = true;
            Invalidate();
        }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false; Invalidate(); base.OnMouseUp(e);
    }
    protected override void OnPaint(PaintEventArgs e) {
        // Opaque controls do not receive the normal background paint pass.
        // Clear the complete client area here so no stale sibling pixels can survive.
        e.Graphics.Clear(BackColor);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        Color fill = pressed ? Color.FromArgb(61,44,87)
                   : hovered ? Color.FromArgb(91,67,126)
                   : Color.FromArgb(74,55,103);
        Color edge = pressed ? Color.FromArgb(139,81,45)
                   : hovered ? Color.FromArgb(207,132,75)
                   : Color.FromArgb(191,118,67);
        // Keep the full 36x36 hit target, but use a quieter 30x30
        // visual circle centered inside it.
        float visualSize = Math.Min(30f,Math.Min(Width,Height));
        float visualX = (Width-visualSize)/2f;
        float visualY = (Height-visualSize)/2f;
        RectangleF r = new RectangleF(
            visualX,
            visualY,
            visualSize,
            visualSize);
        using (SolidBrush b = new SolidBrush(fill)) e.Graphics.FillEllipse(b,r);
        using (Pen p = new Pen(edge,1f)) e.Graphics.DrawEllipse(p,r);
        TextRenderer.DrawText(
            e.Graphics, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-5,-5), ForeColor, BackColor);
    }
}

public class RdcAccentCheckBox : CheckBox {
    private readonly Color accent = Color.FromArgb(191,118,67);
    private readonly Color textColor = Color.FromArgb(184,184,184);

    public RdcAccentCheckBox() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw, true);
        AutoSize = false;
        Size = new Size(126,22);
        Font = new Font("Segoe UI", 9f, FontStyle.Regular);
        ForeColor = textColor;
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        // This control is mouse-operable, but primary keyboard traversal is
        // deliberately reserved for the three action buttons.
        TabStop = false;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent != null ? Parent.BackColor : BackColor);

        Rectangle box = new Rectangle(1,3,14,14);
        using (Pen border = new Pen(accent,1.2f))
            e.Graphics.DrawRectangle(border,box);

        if (Checked) {
            using (SolidBrush fill = new SolidBrush(Color.FromArgb(74,55,103)))
                e.Graphics.FillRectangle(fill,new Rectangle(2,4,13,13));
            using (Pen check = new Pen(Color.FromArgb(238,238,238),1.7f)) {
                check.StartCap = LineCap.Round;
                check.EndCap = LineCap.Round;
                e.Graphics.DrawLines(check,new Point[] {
                    new Point(4,10), new Point(7,13), new Point(12,7)
                });
            }
        }

        Rectangle textRect = new Rectangle(21,0,Width-21,Height);
        TextRenderer.DrawText(
            e.Graphics, Text, Font, textRect, ForeColor,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-1,-1), ForeColor, BackColor);
    }

    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

    protected override void OnCheckedChanged(EventArgs e) {
        Invalidate();
        base.OnCheckedChanged(e);
    }
}

public enum RdcButtonGlyph {
    None,
    Stop,
    Play
}

public enum RdcButtonTone {
    Accent,
    Neutral
}

public class RdcRoundedButton : Control {
    private bool hovered;
    private bool pressed;

    protected override void OnPaintBackground(PaintEventArgs e) {
        // Own every background pixel. The rounded foreground is painted on an
        // opaque host-colored surface, never through ButtonBase transparency.
        e.Graphics.Clear(BackColor);
    }
    private RdcButtonGlyph glyph = RdcButtonGlyph.None;
    private RdcButtonTone tone = RdcButtonTone.Accent;
    private bool showMenuChevron;

    private int ambientShadowRadius;
    public int AmbientShadowRadius {
        get { return ambientShadowRadius; }
        set {
            if(value!=0&&value!=3)throw new ArgumentOutOfRangeException("value");
            if(ambientShadowRadius==value)return;
            ambientShadowRadius=value; Invalidate();
            if(Parent!=null)Parent.Invalidate();
        }
    }

    // Keep the Account icon and label centered as one visual group, using
    // exactly the same grouping geometry as the Stop/Play button.
    public bool ShowMenuChevron {
        get { return showMenuChevron; }
        set { showMenuChevron = value; Invalidate(); }
    }

    public RdcButtonGlyph Glyph {
        get { return glyph; }
        set { glyph = value; Invalidate(); }
    }

    public RdcButtonTone Tone {
        get { return tone; }
        set { tone = value; Invalidate(); }
    }

    public RdcRoundedButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque, true);
        SetStyle(ControlStyles.SupportsTransparentBackColor, false);
        SetStyle(ControlStyles.Selectable, true);
        BackColor = Color.FromArgb(29,32,36);
        ForeColor = Color.FromArgb(238,238,238);
        Font = new Font("Segoe UI Semibold", 10f, FontStyle.Regular);
        Cursor = Cursors.Hand;
        TabStop = true;
        AccessibleRole = AccessibleRole.PushButton;
    }

    protected override void OnEnabledChanged(EventArgs e) {
        Invalidate();
        base.OnEnabledChanged(e);
    }

    protected override void OnMouseEnter(EventArgs e) {
        if (Enabled) hovered = true;
        Invalidate();
        base.OnMouseEnter(e);
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e);
    }
    private static bool IsActivationKey(Keys key) {
        return key == Keys.Space || key == Keys.Enter;
    }
    protected override bool IsInputKey(Keys keyData) {
        if (IsActivationKey(keyData & Keys.KeyCode)) return true;
        return base.IsInputKey(keyData);
    }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (Enabled && IsActivationKey(e.KeyCode)) {
            pressed = true;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
            return;
        }
        base.OnKeyDown(e);
    }
    protected override void OnKeyUp(KeyEventArgs e) {
        if (IsActivationKey(e.KeyCode)) {
            bool click = Enabled && pressed;
            pressed = false;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
            if (click) OnClick(EventArgs.Empty);
            return;
        }
        base.OnKeyUp(e);
    }
    protected override void OnGotFocus(EventArgs e) {
        base.OnGotFocus(e);
        Invalidate();
    }
    protected override void OnLostFocus(EventArgs e) {
        pressed = false;
        base.OnLostFocus(e);
        Invalidate();
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (Enabled && e.Button == MouseButtons.Left) {
            Focus();
            pressed = true;
            Invalidate();
        }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false; Invalidate(); base.OnMouseUp(e);
    }
    private static GraphicsPath Rounded(RectangleF r, float radius) {
        GraphicsPath p = new GraphicsPath();
        float d = radius * 2f;
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
    }

    // Symmetric per-button ambient falloff, painted on the parent and on the
    // opaque button surface using identical local coordinates. No changes
    // to the chrome, text geometry, native hit target or modal buttons.
    public static void PaintAmbientShadow(Graphics g,Rectangle bounds,int radius) {
        if(SystemInformation.HighContrast||bounds.Width<=3||bounds.Height<=3||radius==0)return;
        GraphicsState state=g.Save();
        try{
            g.SmoothingMode=SmoothingMode.AntiAlias;
            g.PixelOffsetMode=PixelOffsetMode.HighQuality;
            RectangleF face=new RectangleF(bounds.X+1f,bounds.Y+1f,bounds.Width-2f,bounds.Height-2f);

            // Nested contours: composited alpha falls outward rather
            // than forming a directional offset or a hard second frame.
            for(int distance=radius;distance>=1;distance--){
                RectangleF halo=face;
                halo.Inflate(distance,distance);
                int alpha=distance==3?35:(distance==2?65:110);
                using(GraphicsPath shape=Rounded(halo,6f+distance))
                using(SolidBrush ink=new SolidBrush(Color.FromArgb(alpha,0,0,0)))
                    g.FillPath(ink,shape);
            }
        }finally{g.Restore(state);}
    }

    // Shared native-looking palette and 6px corner geometry. The main
    // Stop/Account buttons and all Owner modal buttons call this exact
    // painter; modal buttons intentionally have no glyph or chevron.
    public static Color PaintChrome(Graphics graphics, int width, int height,
        Color background, Color foreground, bool enabled, bool hovered,
        bool pressed) {
        return PaintChrome(graphics,width,height,background,foreground,enabled,hovered,pressed,0);
    }

    internal static Color PaintChrome(Graphics graphics,int width,int height,
        Color background,Color foreground,bool enabled,bool hovered,
        bool pressed,int ambientShadowRadius) {
        graphics.Clear(background);
        if(ambientShadowRadius>0)PaintAmbientShadow(graphics,new Rectangle(0,0,width,height),ambientShadowRadius);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        Color fill;
        Color edge;
        Color content;
        if (!enabled) {
            fill=Color.FromArgb(49,53,59);
            edge=Color.FromArgb(82,84,88);
            content=Color.FromArgb(132,135,139);
        } else {
            fill=pressed ? Color.FromArgb(42,46,51)
                : hovered ? Color.FromArgb(61,66,72)
                : Color.FromArgb(49,53,59);
            edge=pressed ? Color.FromArgb(139,81,45)
                : hovered ? Color.FromArgb(207,132,75)
                : Color.FromArgb(191,118,67);
            content=foreground;
        }
        if (width>3 && height>3) {
            RectangleF r=new RectangleF(1f,1f,width-2f,height-2f);
            using(GraphicsPath path=Rounded(r,6f))
            using(SolidBrush brush=new SolidBrush(fill))
            using(Pen pen=new Pen(edge,1f)) {
                graphics.FillPath(brush,path);
                graphics.DrawPath(pen,path);
            }
        }
        return content;
    }

    private void DrawGlyph(Graphics g, Rectangle r, Color color) {
        int cx = r.Left + r.Width / 2;
        int cy = r.Top + r.Height / 2;
        using (SolidBrush b = new SolidBrush(color))
        using (Pen p = new Pen(color,1.8f)) {
            p.StartCap = LineCap.Round;
            p.EndCap = LineCap.Round;
            if (glyph == RdcButtonGlyph.Stop) {
                g.FillRectangle(b,new Rectangle(cx-4,cy-4,9,9));
            } else if (glyph == RdcButtonGlyph.Play) {
                Point[] tri = {
                    new Point(cx-4,cy-5),
                    new Point(cx+5,cy),
                    new Point(cx-4,cy+5)
                };
                g.FillPolygon(b,tri);
            }
        }
    }

    private Rectangle GetGroupIconBounds(int textWidth) {
        // Used by both Account (chevron) and Stop/Play (action glyph).
        const int iconSize = 12;
        const int gap = 7;
        int groupWidth = iconSize + gap + textWidth;
        int left = Math.Max(5,(Width-groupWidth)/2);
        return new Rectangle(left,(Height-iconSize)/2,iconSize,iconSize);
    }

    private void DrawMenuChevron(Graphics g, Rectangle iconBounds, Color color) {
        // 10x8 dropdown arrow centered within the same 12x12 glyph slot
        // occupied by Stop/Play, on the LEFT of the Account label.
        int x = iconBounds.Left + (iconBounds.Width-10)/2;
        int y = iconBounds.Top + (iconBounds.Height-8)/2;
        using (Pen pen = new Pen(color,1.7f)) {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            pen.LineJoin = LineJoin.Round;
            g.DrawLines(pen,new Point[] {
                new Point(x+1,y+2),
                new Point(x+5,y+6),
                new Point(x+9,y+2)
            });
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        // The modal version shares precisely this paint path and palette.
        // Opaque backgrounds, 6px corners and 1px outline stay unchanged.
        Color content=PaintChrome(e.Graphics,Width,Height,BackColor,ForeColor,
                                  Enabled,hovered,pressed,ambientShadowRadius);

        TextFormatFlags flags =
            TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine |
            TextFormatFlags.NoPadding;
        Size textSize = TextRenderer.MeasureText(
            e.Graphics,Text,Font,new Size(Int32.MaxValue,Height),flags);

        if (glyph == RdcButtonGlyph.None && !showMenuChevron) {
            TextRenderer.DrawText(
                e.Graphics,Text,Font,ClientRectangle,content,
                flags | TextFormatFlags.HorizontalCenter);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-5,-5), ForeColor, BackColor);
            return;
        }

        // Account dropdown and Stop/Play share the identical centered
        // 12px glyph + 7px gap + measured-text composition.
        Rectangle iconRect = GetGroupIconBounds(textSize.Width);
        if (showMenuChevron && glyph == RdcButtonGlyph.None)
            DrawMenuChevron(e.Graphics,iconRect,content);
        else
            DrawGlyph(e.Graphics,iconRect,content);

        Rectangle textRect = new Rectangle(
            iconRect.Right + 7,
            0,
            Math.Max(1,Width-(iconRect.Right+7)-5),
            Height);
        TextRenderer.DrawText(
            e.Graphics,Text,Font,textRect,content,
            flags | TextFormatFlags.Left);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-5,-5), ForeColor, BackColor);
    }
}

// Retains native Button/DialogResult/PerformClick/Enter/Escape behavior,
// but shares the main RdcRoundedButton's exact 6px rounded chrome. Unlike
// the main control-panel actions, Owner modal actions have no glyphs.
public sealed class RdcHeaderActionPanel : FlowLayoutPanel {
    public RdcHeaderActionPanel(){
        SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint|
                 ControlStyles.ResizeRedraw,true);
    }
    protected override void OnLayout(LayoutEventArgs e){
        base.OnLayout(e);
        Invalidate();
    }
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);
        foreach(Control child in Controls){
            RdcRoundedButton button=child as RdcRoundedButton;
            if(button!=null&&button.Visible&&button.AmbientShadowRadius>0)
                RdcRoundedButton.PaintAmbientShadow(e.Graphics,button.Bounds,button.AmbientShadowRadius);
        }
    }
}

public sealed class RdcModalButton : Button {
    private bool hovered;
    private bool pressed;
    // Native button remains the click/focus target. Paint the portion of
    // the halo outside its HWND on its immediate parent, and the same
    // contour inside its opaque client area. Never attach to legacy
    // dialogs unless explicitly enabled by the Owner GUI.
    private bool ambientShadow;
    private Control shadowParent;
    public bool AmbientShadow {
        get { return ambientShadow; }
        set {
            if(ambientShadow==value)return;
            ambientShadow=value;
            AttachShadowParent();
            Invalidate();
        }
    }
    private void AttachShadowParent(){
        if(shadowParent!=null){
            shadowParent.Paint-=PaintParentShadow;
            shadowParent.Invalidate();
        }
        shadowParent=ambientShadow?Parent:null;
        if(shadowParent!=null){
            shadowParent.Paint+=PaintParentShadow;
            shadowParent.Invalidate();
        }
    }
    private void PaintParentShadow(object sender,PaintEventArgs e){
        if(ambientShadow&&Visible&&!IsDisposed)
            RdcRoundedButton.PaintAmbientShadow(e.Graphics,Bounds,3);
    }
    protected override void OnParentChanged(EventArgs e){
        base.OnParentChanged(e);
        AttachShadowParent();
    }
    protected override void OnLocationChanged(EventArgs e){
        base.OnLocationChanged(e);
        if(shadowParent!=null)shadowParent.Invalidate();
    }
    protected override void OnSizeChanged(EventArgs e){
        base.OnSizeChanged(e);
        if(shadowParent!=null)shadowParent.Invalidate();
    }
    protected override void OnVisibleChanged(EventArgs e){
        base.OnVisibleChanged(e);
        if(shadowParent!=null)shadowParent.Invalidate();
    }
    protected override void Dispose(bool disposing){
        if(disposing&&shadowParent!=null){
            shadowParent.Paint-=PaintParentShadow;
            shadowParent.Invalidate();
            shadowParent=null;
        }
        base.Dispose(disposing);
    }
    public RdcModalButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque,true);
        SetStyle(ControlStyles.SupportsTransparentBackColor,false);
        BackColor=Color.FromArgb(29,32,36);
        ForeColor=Color.FromArgb(238,238,238);
        Font=new Font("Segoe UI Semibold",10f,FontStyle.Regular);
        Cursor=Cursors.Hand;
        FlatStyle=FlatStyle.Flat;
        UseVisualStyleBackColor=false;
        TabStop=true;
        AccessibleRole=AccessibleRole.PushButton;
    }
    protected override void OnPaintBackground(PaintEventArgs e) {
        e.Graphics.Clear(BackColor);
    }
    protected override void OnPaint(PaintEventArgs e) {
        Color textColor=RdcRoundedButton.PaintChrome(
            e.Graphics,Width,Height,BackColor,ForeColor,Enabled,hovered,pressed,ambientShadow?3:0);
        TextRenderer.DrawText(e.Graphics,Text,Font,ClientRectangle,textColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
            TextFormatFlags.NoPadding | TextFormatFlags.HorizontalCenter);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics,
                Rectangle.Inflate(ClientRectangle,-5,-5),ForeColor,BackColor);
    }
    protected override void OnEnabledChanged(EventArgs e) {
        base.OnEnabledChanged(e);
        Invalidate();
    }
    protected override void OnMouseEnter(EventArgs e) {
        hovered=Enabled;
        base.OnMouseEnter(e);
        Invalidate();
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered=false;
        pressed=false;
        base.OnMouseLeave(e);
        Invalidate();
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (Enabled && e.Button==MouseButtons.Left) pressed=true;
        base.OnMouseDown(e);
        Invalidate();
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed=false;
        base.OnMouseUp(e);
        Invalidate();
    }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (Enabled && (e.KeyCode==Keys.Space || e.KeyCode==Keys.Enter))
            pressed=true;
        base.OnKeyDown(e);
        Invalidate();
    }
    protected override void OnKeyUp(KeyEventArgs e) {
        pressed=false;
        base.OnKeyUp(e);
        Invalidate();
    }
    protected override void OnGotFocus(EventArgs e) {
        base.OnGotFocus(e);
        Invalidate();
    }
    protected override void OnLostFocus(EventArgs e) {
        pressed=false;
        base.OnLostFocus(e);
        Invalidate();
    }
}

public class RdcStatusIndicator : Control {
    private Color indicatorColor = Color.Gray;
    public Color IndicatorColor {
        get { return indicatorColor; }
        set { indicatorColor = value; Invalidate(); }
    }
    private bool ownerCapsule;
    public bool OwnerCapsule {
        get { return ownerCapsule; }
        set { ownerCapsule = value; Invalidate(); }
    }

    public RdcStatusIndicator() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        TabStop = false;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        if (ownerCapsule) {
            // Exact decorative vertical scrollbar thumb: 17px rail minus
            // 2px each side -> 13px wide, with a 6px rounded end radius.
            // Owner optical refinement: keep the upper painted edge at
            // header Y=21, raise only the accepted lower edge Y=59 to Y=58.
            // GDI+ antialiasing: the Y=20..58 outline paints Y=21..58.
            // Preserve the scrollbar's 13px width and 6px end radius.
            const int width = 13, height = 39, radius = 6;
            int capX = (Width-width)/2;
            int capY = Math.Min(Math.Max(0,Height-40),8);
            if (Width < width || Height < height) return;
            int d = radius*2;
            using (GraphicsPath path = new GraphicsPath()) {
                path.AddArc(capX,capY,d,d,180,90);
                path.AddArc(capX+width-d,capY,d,d,270,90);
                path.AddArc(capX+width-d,capY+height-d,d,d,0,90);
                path.AddArc(capX,capY+height-d,d,d,90,90);
                path.CloseFigure();
                if(SystemInformation.HighContrast){
                    using(SolidBrush b=new SolidBrush(indicatorColor))
                        e.Graphics.FillPath(b,path);
                }else{
                    // Keep the accepted outer capsule width and end radii.
                    // 2px inward contour tracks the current status color.
                    Color rim=Color.FromArgb((int)(indicatorColor.R*0.70f),
                        (int)(indicatorColor.G*0.70f),(int)(indicatorColor.B*0.70f));
                    using(SolidBrush b=new SolidBrush(rim))
                        e.Graphics.FillPath(b,path);
                    const int inset=2;
                    int ix=capX+inset,iy=capY+inset,iw=width-2*inset,ih=height-2*inset;
                    int innerD=d-2*inset;
                    using(GraphicsPath inner=new GraphicsPath()){
                        inner.AddArc(ix,iy,innerD,innerD,180,90);
                        inner.AddArc(ix+iw-innerD,iy,innerD,innerD,270,90);
                        inner.AddArc(ix+iw-innerD,iy+ih-innerD,innerD,innerD,0,90);
                        inner.AddArc(ix,iy+ih-innerD,innerD,innerD,90,90);
                        inner.CloseFigure();
                        using(SolidBrush b=new SolidBrush(indicatorColor))
                            e.Graphics.FillPath(b,inner);
                        GraphicsState state=e.Graphics.Save();
                        try{
                            e.Graphics.SetClip(inner,CombineMode.Intersect);
                            RectangleF shine=new RectangleF(ix+1f,iy+1f,4f,13f);
                            using(LinearGradientBrush gloss=new LinearGradientBrush(shine,
                                Color.FromArgb(110,255,255,255),Color.FromArgb(0,255,255,255),
                                LinearGradientMode.Vertical))
                                e.Graphics.FillEllipse(gloss,shine);
                        }finally{e.Graphics.Restore(state);}
                    }
                }
            }
            return;
        }
        // Legacy circle geometry and paint remain untouched.
        int diameter = 18;
        int x = (Width - diameter) / 2;
        int y = (Height - diameter) / 2;
        using (SolidBrush b = new SolidBrush(indicatorColor))
            e.Graphics.FillEllipse(b, x, y, diameter, diameter);
    }
}

// Resource-only Owner banner: one paint surface, no RichEdit glyph rows.
public sealed class RdcOwnerWordmark : Control {
    private readonly Bitmap[] images;
    // RDC_WORDMARK_RESOURCES_BEGIN
    private static readonly string[] resources = new string[] {
        "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",
    };
    // RDC_WORDMARK_RESOURCES_END
    public RdcOwnerWordmark() {
        SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|
            ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);
        TabStop=false; AccessibleName="Desktop Commander";
        AccessibleRole=AccessibleRole.Graphic;
        images=new Bitmap[resources.Length];
        try {
            for(int i=0;i<images.Length;i++){
                using(var stream=new MemoryStream(Convert.FromBase64String(resources[i]),false))
                using(var decoded=new Bitmap(stream)) images[i]=new Bitmap(decoded);
            }
        } catch {foreach(Bitmap bmp in images)if(bmp!=null)bmp.Dispose();throw;}
    }
    private static int Px(float dpi,int value){
        return Math.Max(1,(int)Math.Round(value*dpi/96.0));
    }
    public static int PreferredRowHeight(int width,int available,float dpi) {
        int inset=Px(dpi,17)+Px(dpi,3);
        int w=Math.Max(1,Math.Min(width-inset,Px(dpi,997)));
        int natural=(int)Math.Ceiling(w*74.0/997.0)+Px(dpi,8);
        return Math.Max(0,Math.Min(natural,available-Px(dpi,16)));
    }
    public int RowHeight(int width,int available){
        using(Graphics g=CreateGraphics())return PreferredRowHeight(width,available,g.DpiX);
    }
    public static Rectangle ImageBounds(int width,int height,float dpi){
        int x=Px(dpi,17),y=Px(dpi,5);
        int w=Math.Min(width-x-Px(dpi,3),Px(dpi,997));
        int h=height-y-Px(dpi,3);
        if(w<=0||h<=0)return Rectangle.Empty;
        w=Math.Min(w,(int)Math.Floor(h*997.0/74.0));
        h=Math.Max(1,(int)Math.Round(w*74.0/997.0));
        if(w<=0)return Rectangle.Empty;
        return new Rectangle(x,y,w,h);
    }
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);
        Rectangle target=ImageBounds(ClientSize.Width,ClientSize.Height,e.Graphics.DpiX);
        if(target.IsEmpty)return;
        Bitmap selected=images[images.Length-1];
        foreach(Bitmap bmp in images){if(bmp.Width>=target.Width){selected=bmp;break;}}
        e.Graphics.InterpolationMode=InterpolationMode.HighQualityBicubic;
        e.Graphics.PixelOffsetMode=PixelOffsetMode.HighQuality;
        using(var attributes=new System.Drawing.Imaging.ImageAttributes()){
            attributes.SetWrapMode(WrapMode.TileFlipXY);
            e.Graphics.DrawImage(selected,target,0,0,selected.Width,selected.Height,GraphicsUnit.Pixel,attributes);
        }
    }
    protected override void Dispose(bool disposing){
        if(disposing&&images!=null)foreach(Bitmap bmp in images)if(bmp!=null)bmp.Dispose();
        base.Dispose(disposing);
    }
}

public class RdcBufferedPanel : Panel {
    public RdcBufferedPanel() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw, true);
        DoubleBuffered = true;
    }
}

public class RdcDividerDragPreview : Control {
    private Bitmap headerImage;
    private Bitmap logImage;
    private Bitmap upperVScrollImage;
    private Bitmap lowerVScrollImage;
    private bool lowerRailDecorative;
    private Bitmap hScrollImage;
    private Bitmap cornerImage;
    private int dividerY;

    private readonly System.Windows.Forms.Timer fadeTimer;
    private readonly System.Diagnostics.Stopwatch fadeWatch =
        new System.Diagnostics.Stopwatch();
    private float rulerOpacity = 1f;
    private float fadeFrom = 1f;
    private float fadeTo = 1f;
    private int fadeDelayMs;
    private int fadeDurationMs;
    private bool completeFadeOut;

    public event EventHandler FadeOutCompleted;

    public RdcDividerDragPreview() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque, true);
        BackColor = Color.FromArgb(18,20,23);
        TabStop = false;
        Enabled = false;

        fadeTimer = new System.Windows.Forms.Timer();
        fadeTimer.Interval = 15;
        fadeTimer.Tick += FadeTimer_Tick;
    }

    private static Bitmap CaptureControl(Control control) {
        if (control == null || control.Width <= 0 || control.Height <= 0)
            return null;

        Bitmap bmp = new Bitmap(control.Width,control.Height);
        using (Graphics g = Graphics.FromImage(bmp)) {
            Point screen = control.PointToScreen(Point.Empty);
            g.CopyFromScreen(screen,Point.Empty,control.Size,CopyPixelOperation.SourceCopy);
        }
        return bmp;
    }

    private static Bitmap RenderControl(Control control) {
        if (control == null || control.Width <= 0 || control.Height <= 0)
            return null;

        Bitmap bmp = new Bitmap(control.Width,control.Height);
        control.DrawToBitmap(
            bmp,
            new Rectangle(0,0,control.Width,control.Height));
        return bmp;
    }

    private void DisposeVerticalImages() {
        if (upperVScrollImage != null) {
            upperVScrollImage.Dispose();
            upperVScrollImage = null;
        }
        if (lowerVScrollImage != null) {
            lowerVScrollImage.Dispose();
            lowerVScrollImage = null;
        }
    }

    private void DisposeImages() {
        if (headerImage != null) { headerImage.Dispose(); headerImage = null; }
        if (logImage != null) { logImage.Dispose(); logImage = null; }
        DisposeVerticalImages();
        if (hScrollImage != null) { hScrollImage.Dispose(); hScrollImage = null; }
        if (cornerImage != null) { cornerImage.Dispose(); cornerImage = null; }
    }

    private static void DrawImageAlpha(
        Graphics g,
        Bitmap image,
        Rectangle dest,
        float alpha) {

        if (image == null || dest.Width <= 0 || dest.Height <= 0 || alpha <= 0f)
            return;

        alpha = Math.Max(0f,Math.Min(1f,alpha));
        System.Drawing.Imaging.ColorMatrix matrix =
            new System.Drawing.Imaging.ColorMatrix();
        matrix.Matrix33 = alpha;

        using (System.Drawing.Imaging.ImageAttributes attrs =
            new System.Drawing.Imaging.ImageAttributes()) {
            attrs.SetColorMatrix(matrix);
            g.DrawImage(
                image,
                dest,
                0,0,image.Width,image.Height,
                GraphicsUnit.Pixel,
                attrs);
        }
    }

    private void BeginFade(
        float target,
        int delayMs,
        int durationMs,
        bool completeOnEnd) {

        fadeTimer.Stop();
        fadeFrom = rulerOpacity;
        fadeTo = Math.Max(0f,Math.Min(1f,target));
        fadeDelayMs = Math.Max(0,delayMs);
        fadeDurationMs = Math.Max(1,durationMs);
        completeFadeOut = completeOnEnd;
        fadeWatch.Restart();
        fadeTimer.Start();
    }

    private void FadeTimer_Tick(object sender,EventArgs e) {
        double elapsed = fadeWatch.Elapsed.TotalMilliseconds;
        if (elapsed < fadeDelayMs) return;

        double t = Math.Min(
            1.0,
            (elapsed-fadeDelayMs)/Math.Max(1.0,fadeDurationMs));

        // Fast ease-out on appearance, smoothstep on disappearance.
        double eased = fadeTo > fadeFrom
            ? 1.0-Math.Pow(1.0-t,3.0)
            : t*t*(3.0-2.0*t);

        rulerOpacity =
            fadeFrom + (fadeTo-fadeFrom)*(float)eased;
        Invalidate();

        if (t >= 1.0) {
            fadeTimer.Stop();
            fadeWatch.Stop();
            rulerOpacity = fadeTo;
            Invalidate();

            if (completeFadeOut) {
                completeFadeOut = false;
                EventHandler handler = FadeOutCompleted;
                if (handler != null)
                    handler(this,EventArgs.Empty);
            }
        }
    }

    public void FadeIn(int durationMs) {
        BeginFade(1f,0,durationMs,false);
    }

    public void FadeOut(int settleDelayMs,int durationMs) {
        BeginFade(0f,settleDelayMs,durationMs,true);
    }

    public void CaptureFinalScrollbars(
        Control upperVScroll,
        Control lowerVScroll) {

        DisposeVerticalImages();
        upperVScrollImage = RenderControl(upperVScroll);
        lowerVScrollImage = RenderControl(lowerVScroll);
        RdcOverlayScrollBar lower = lowerVScroll as RdcOverlayScrollBar;
        lowerRailDecorative = lower != null && lower.DecorativeFullTrack;
        Invalidate();
    }

    private GraphicsPath Rounded(Rectangle r, int radius) {
        GraphicsPath p = new GraphicsPath();
        int d = radius * 2;
        if (d <= 0 || r.Width <= d || r.Height <= d) {
            p.AddRectangle(r);
            return p;
        }
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
    }

    public void BeginPreview(
        Control headerText,
        Control log,
        Control upperVScroll,
        Control lowerVScroll,
        Control hScroll,
        Control corner,
        int initialDividerY) {

        fadeTimer.Stop();
        fadeWatch.Reset();
        completeFadeOut = false;
        DisposeImages();

        headerImage = CaptureControl(headerText);
        logImage = CaptureControl(log);
        upperVScrollImage = RenderControl(upperVScroll);
        lowerVScrollImage = RenderControl(lowerVScroll);
        RdcOverlayScrollBar lower = lowerVScroll as RdcOverlayScrollBar;
        lowerRailDecorative = lower != null && lower.DecorativeFullTrack;
        hScrollImage = CaptureControl(hScroll);
        cornerImage = CaptureControl(corner);

        dividerY = initialDividerY;
        rulerOpacity = 0f;
        Invalidate();
    }

    public void UpdateDivider(int value) {
        dividerY = Math.Max(0,Math.Min(Math.Max(0,Height-7),value));
        Invalidate();
        Update();
    }

    public void EndPreview() {
        fadeTimer.Stop();
        fadeWatch.Reset();
        completeFadeOut = false;
        rulerOpacity = 1f;
        DisposeImages();
        Invalidate();
    }

    protected override void Dispose(bool disposing) {
        if (disposing) {
            fadeTimer.Stop();
            fadeTimer.Dispose();
            fadeWatch.Stop();
            DisposeImages();
        }
        base.Dispose(disposing);
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(BackColor);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        int splitY = Math.Max(0,Math.Min(Math.Max(0,Height-7),dividerY));
        int lowerTop = Math.Min(Height,splitY+7);
        int scrollSize = 17;
        int contentWidth = Math.Max(0,Width-scrollSize);
        int bottomBarTop = Math.Max(0,Height-scrollSize);
        int lowerContentHeight = Math.Max(0,bottomBarTop-lowerTop);

        // Preview only the text portions. The two real vertical scrollbars are
        // intentionally omitted and replaced with one unified drag ruler.
        if (headerImage != null && splitY > 0 && contentWidth > 0) {
            Region oldClip = e.Graphics.Clip.Clone();
            try {
                e.Graphics.SetClip(new Rectangle(0,0,contentWidth,splitY));
                e.Graphics.DrawImageUnscaled(headerImage,0,0);
            } finally {
                e.Graphics.Clip = oldClip;
                oldClip.Dispose();
            }
        }

        if (logImage != null && lowerContentHeight > 0 && contentWidth > 0) {
            Rectangle dest = new Rectangle(0,lowerTop,contentWidth,lowerContentHeight);
            Region oldClip = e.Graphics.Clip.Clone();
            try {
                e.Graphics.SetClip(dest);
                e.Graphics.DrawImageUnscaled(logImage,0,lowerTop);
            } finally {
                e.Graphics.Clip = oldClip;
                oldClip.Dispose();
            }
        }

        if (hScrollImage != null && contentWidth > 0) {
            e.Graphics.DrawImage(
                hScrollImage,
                new Rectangle(0,bottomBarTop,contentWidth,scrollSize),
                new Rectangle(0,0,hScrollImage.Width,hScrollImage.Height),
                GraphicsUnit.Pixel);
        }

        if (cornerImage != null) {
            e.Graphics.DrawImageUnscaled(
                cornerImage,
                Math.Max(0,Width-scrollSize),
                bottomBarTop);
        }

        // One temporary vertical ruler for both text panes. Keep only the
        // outer arrows. The entire body is orange and carries a continuous
        // gray 45-degree hatch so it reads as a neutral resize scale rather
        // than either pane's actual scroll thumb.
        Rectangle rightColumn = new Rectangle(contentWidth,0,scrollSize,bottomBarTop);
        using (SolidBrush trackBack = new SolidBrush(Color.FromArgb(18,20,23)))
            e.Graphics.FillRectangle(trackBack,rightColumn);

        float realBarsOpacity = Math.Max(0f,Math.Min(1f,1f-rulerOpacity));
        if (realBarsOpacity > 0f) {
            DrawImageAlpha(
                e.Graphics,
                upperVScrollImage,
                new Rectangle(contentWidth,0,scrollSize,Math.Max(0,splitY)),
                realBarsOpacity);
            DrawImageAlpha(
                e.Graphics,
                lowerVScrollImage,
                new Rectangle(
                    contentWidth,
                    lowerTop,
                    scrollSize,
                    Math.Max(0,lowerContentHeight)),
                realBarsOpacity);
        }

        int rulerAlpha = Math.Max(
            0,
            Math.Min(255,(int)Math.Round(255f*rulerOpacity)));

        int arrow = 16;
        int bodyTop = arrow;
        int bodyBottom = Math.Max(bodyTop,bottomBarTop-arrow);
        Rectangle body = new Rectangle(
            contentWidth+2,
            bodyTop,
            Math.Max(1,scrollSize-4),
            Math.Max(1,bodyBottom-bodyTop));

        int bodyRadius = Math.Min(7,Math.Min(body.Width,body.Height)/2);
        using (GraphicsPath bodyPath = Rounded(body,bodyRadius))
        using (SolidBrush orange = new SolidBrush(
            Color.FromArgb(rulerAlpha,191,118,67))) {
            e.Graphics.FillPath(orange,bodyPath);

            Region hatchClip = e.Graphics.Clip.Clone();
            try {
                e.Graphics.SetClip(bodyPath);

                SmoothingMode oldSmoothing = e.Graphics.SmoothingMode;
                PixelOffsetMode oldPixelOffset = e.Graphics.PixelOffsetMode;
                try {
                    // Full-length pixel-grid hatch: 2 px dark diagonal,
                    // 2 px orange gap, repeated every 4 px. The strokes are
                    // deliberately extended beyond both X edges, then clipped
                    // by the rounded thumb path, so their end caps cannot form
                    // visible vertical projection bands at the sides.
                    e.Graphics.SmoothingMode = SmoothingMode.None;
                    e.Graphics.PixelOffsetMode = PixelOffsetMode.None;

                    using (Pen hatch = new Pen(
                        Color.FromArgb(rulerAlpha,18,20,23),
                        2f)) {

                        hatch.StartCap = LineCap.Flat;
                        hatch.EndCap = LineCap.Flat;

                        const int spacing = 4;
                        const int overscan = 4;
                        int diagonal = Math.Max(1,body.Width-1);

                        for (int y = body.Top-diagonal-overscan;
                             y < body.Bottom+diagonal+overscan;
                             y += spacing) {
                            e.Graphics.DrawLine(
                                hatch,
                                body.Left-overscan,
                                y+diagonal+overscan,
                                body.Right-1+overscan,
                                y-overscan);
                        }
                    }
                } finally {
                    e.Graphics.SmoothingMode = oldSmoothing;
                    e.Graphics.PixelOffsetMode = oldPixelOffset;
                }
            } finally {
                e.Graphics.Clip = hatchClip;
                hatchClip.Dispose();
            }

            // Preserve the exact capsule geometry used by the real scrollbar.
            // Build a 5 px inward fade from independent 1 px capsule contours
            // instead of one thick pen, so the end caps keep their shape.
            float[] fadeAlpha = { 1.00f, 0.70f, 0.48f, 0.28f, 0.12f };

            for (int depth = 0; depth < fadeAlpha.Length; depth++) {
                int alpha = (int)Math.Round(
                    rulerAlpha * fadeAlpha[depth]);

                if (depth == 0) {
                    using (Pen outline = new Pen(
                        Color.FromArgb(alpha,191,118,67),
                        1f)) {
                        outline.LineJoin = LineJoin.Round;
                        e.Graphics.DrawPath(outline,bodyPath);
                    }
                    continue;
                }

                Rectangle layerRect = new Rectangle(
                    body.X+depth,
                    body.Y+depth,
                    Math.Max(1,body.Width-(depth*2)),
                    Math.Max(1,body.Height-(depth*2)));

                int layerRadius = Math.Max(
                    1,
                    Math.Min(
                        bodyRadius-depth,
                        Math.Min(layerRect.Width,layerRect.Height)/2));

                using (GraphicsPath layerPath = Rounded(
                    layerRect,
                    layerRadius))
                using (Pen layer = new Pen(
                    Color.FromArgb(alpha,191,118,67),
                    1f)) {
                    layer.LineJoin = LineJoin.Round;
                    e.Graphics.DrawPath(layer,layerPath);
                }
            }
        }

        // The real upper scrollbar retains normal gray navigation arrows;
        // the lower inactive rail uses its own darker track-gray arrows.
        // Keep both when fading the divider so no bright arrow flashes.
        using (SolidBrush arrows = new SolidBrush(
            Color.FromArgb(rulerAlpha,112,115,120)))
        using (SolidBrush lowerArrows = new SolidBrush(
            Color.FromArgb(rulerAlpha,lowerRailDecorative
                ? RdcOverlayScrollBar.TrackBackground
                : Color.FromArgb(112,115,120)))) {
            int cx = contentWidth + scrollSize/2;
            Point[] up = {
                new Point(cx,5),
                new Point(cx-4,10),
                new Point(cx+4,10)
            };
            Point[] down = {
                new Point(cx,Math.Max(0,bottomBarTop-5)),
                new Point(cx-4,Math.Max(0,bottomBarTop-10)),
                new Point(cx+4,Math.Max(0,bottomBarTop-10))
            };
            e.Graphics.FillPolygon(arrows,up);
            // Its glyph is decorative; match the lower track even here.
            e.Graphics.FillPolygon(lowerArrows,down);
        }

        // Fade only the temporary pin around the divider crossing. The fade
        // belongs to the pin layer; the animated divider is painted afterwards
        // as an independent foreground element.
        int topPurpleY = splitY;
        int bottomPurpleY = Math.Min(
            Height-1,
            splitY+6);
        int dividerHeight = Math.Max(
            0,
            bottomPurpleY-topPurpleY+1);

        int crossingFade = 15;
        // Narrow blackout around the divider. The final center geometry below
        // keeps 3 px of full cover above and 2 px below the 7 px divider.
        int crossingCenterExtra = 6;
        int crossingCenterPad = crossingCenterExtra / 2;
        Color crossingBack = Color.FromArgb(18,20,23);

        // Three-part pin mask:
        // 1) a fully hidden center with 3 px above and 2 px below the
        //    visible 7 px divider;
        // 2) a 15 px upper linear alpha fade from 0 to 250;
        // 3) a mirrored 15 px lower fade from 250 to 0.
        int crossingCenterTop =
            topPurpleY-crossingCenterPad;
        // Keep 3 px of full cover above the 7 px divider, but only
        // 2 px below it; the previous symmetric arithmetic looked one pixel
        // heavier on the lower side in the rendered drag overlay.
        int crossingCenterHeight =
            dividerHeight+crossingCenterExtra-1;
        int crossingCenterBottom =
            crossingCenterTop+crossingCenterHeight; // exclusive

        // Use a rectangular mask with 1 px horizontal overscan instead of
        // clipping the mask to the rounded pin path. The previous rounded clip
        // preserved anti-aliased orange edge pixels at the crossing, which made
        // the pin appear to touch the purple divider even inside the 100% zone.
        int maskLeft = Math.Max(0,body.Left-1);
        int maskRight = Math.Min(Width,body.Right+1);
        int maskWidth = Math.Max(0,maskRight-maskLeft);

        int fadeDenominator = Math.Max(1,crossingFade-1);
        for (int i = 0; i < crossingFade; i++) {
            // Simple linear mask requested for the scrollbar crossing:
            // outer edge = 0 alpha, inner edge = 250 alpha. The fully opaque
            // center is painted separately, so there is no dark rectangular
            // plateau across the fade itself.
            int upperAlpha = (int)Math.Round(
                250.0 * i / fadeDenominator);
            int lowerAlpha = (int)Math.Round(
                250.0 * (crossingFade-1-i) / fadeDenominator);

            int upperY =
                crossingCenterTop-crossingFade+i;
            int lowerY =
                crossingCenterBottom+i;

            if (upperY >= 0 && upperY < Height && maskWidth > 0) {
                using (SolidBrush fade = new SolidBrush(
                    Color.FromArgb(
                        upperAlpha,
                        crossingBack.R,
                        crossingBack.G,
                        crossingBack.B))) {
                    e.Graphics.FillRectangle(
                        fade,
                        maskLeft,
                        upperY,
                        maskWidth,
                        1);
                }
            }

            if (lowerY >= 0 && lowerY < Height && maskWidth > 0) {
                using (SolidBrush fade = new SolidBrush(
                    Color.FromArgb(
                        lowerAlpha,
                        crossingBack.R,
                        crossingBack.G,
                        crossingBack.B))) {
                    e.Graphics.FillRectangle(
                        fade,
                        maskLeft,
                        lowerY,
                        maskWidth,
                        1);
                }
            }
        }

        using (SolidBrush crossingClear = new SolidBrush(crossingBack)) {
            int centerTop = Math.Max(
                0,
                crossingCenterTop);
            int centerBottom = Math.Min(
                Height,
                crossingCenterBottom);
            int centerHeight = Math.Max(
                0,
                centerBottom-centerTop);

            if (centerHeight > 0 && maskWidth > 0) {
                e.Graphics.FillRectangle(
                    crossingClear,
                    maskLeft,
                    centerTop,
                    maskWidth,
                    centerHeight);
            }
        }

        // The divider keeps its own opaque textbox-background strip and is
        // painted after the pin fade, so the fade can never cover the line.
        using (SolidBrush dividerBack = new SolidBrush(crossingBack)) {
            e.Graphics.FillRectangle(
                dividerBack,
                0,
                topPurpleY,
                Width,
                dividerHeight);
        }

        using (Pen purple = new Pen(Color.FromArgb(123,95,162),1f))
        using (Pen orangeLine = new Pen(Color.FromArgb(191,118,67),1f)) {
            e.Graphics.DrawLine(
                purple,
                0,
                topPurpleY,
                Width,
                topPurpleY);
            e.Graphics.DrawLine(
                orangeLine,
                0,
                Math.Min(Height-1,topPurpleY+3),
                Width,
                Math.Min(Height-1,topPurpleY+3));
            e.Graphics.DrawLine(
                purple,
                0,
                bottomPurpleY,
                Width,
                bottomPurpleY);
        }
    }
}

public class RdcLogBox : RichTextBox {
    private const int WM_HSCROLL = 0x0114;
    private const int WM_VSCROLL = 0x0115;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_MOUSEHWHEEL = 0x020E;
    private const int WM_SETREDRAW = 0x000B;
    private const int WM_SETFOCUS = 0x0007;
    private const int EM_HIDESELECTION = 0x043F;
    private const int MK_CONTROL = 0x0008;

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct PARAFORMAT2 {
        public uint cbSize;
        public uint dwMask;
        public ushort wNumbering;
        public ushort wReserved;
        public int dxStartIndent;
        public int dxRightIndent;
        public int dxOffset;
        public ushort wAlignment;
        public short cTabCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=32)]
        public int[] rgxTabs;
        public int dySpaceBefore;
        public int dySpaceAfter;
        public int dyLineSpacing;
        public short sStyle;
        public byte bLineSpacingRule;
        public byte bOutlineLevel;
        public ushort wShadingWeight;
        public ushort wShadingStyle;
        public ushort wNumberingStart;
        public ushort wNumberingStyle;
        public ushort wNumberingTab;
        public ushort wBorderSpace;
        public ushort wBorderWidth;
        public ushort wBorders;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(
        IntPtr hWnd, uint msg, IntPtr wParam, ref PARAFORMAT2 lParam);

    private const uint EM_SETPARAFORMAT = 0x0447;
    private const uint PFM_LINESPACING = 0x00000100;

    [StructLayout(LayoutKind.Sequential)]
    private struct VIEWPOINT { public int X; public int Y; }
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, ref VIEWPOINT lParam);
    private const uint EM_GETSCROLLPOS = 0x04DD;
    private const uint EM_SETSCROLLPOS = 0x04DE;

    public event EventHandler ScrollActivity;
    // The read-only Journal is an interactive document, unlike the two
    // telemetry panes: native selection/copy and wheel navigation are allowed.
    public bool JournalNativeInteraction { get; set; }
    private int journalWheelRemainder;
    private const int EM_LINESCROLL = 0x00B6;
    private bool preserveViewAfterFocusClick;
    private int preservedFocusX;
    private int preservedFocusY;
    private bool horizontalExtentDirty = true;
    private int cachedHorizontalMaximum;

    public RdcLogBox() {
        ZoomFactor = 1.0f;
        HideSelection = true;
    }

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        horizontalExtentDirty = true;
    }

    protected override void OnTextChanged(EventArgs e) {
        horizontalExtentDirty = true;
        ownerBannerStart=ownerBannerEnd=-1;
        base.OnTextChanged(e);
    }

    protected override void OnResize(EventArgs e) {
        horizontalExtentDirty = true;
        base.OnResize(e);
    }

    protected override void OnFontChanged(EventArgs e) {
        horizontalExtentDirty = true;
        base.OnFontChanged(e);
    }

    public int GetHorizontalMaximum() {
        if (!IsHandleCreated || WordWrap) return 0;
        if (!horizontalExtentDirty) return cachedHorizontalMaximum;

        VIEWPOINT original = new VIEWPOINT();
        SendMessage(Handle,EM_GETSCROLLPOS,IntPtr.Zero,ref original);
        VIEWPOINT probe = original;
        probe.X = 0x3fffffff;

        SendMessage(Handle,WM_SETREDRAW,IntPtr.Zero,IntPtr.Zero);
        try {
            SendMessage(Handle,EM_SETSCROLLPOS,IntPtr.Zero,ref probe);
            VIEWPOINT clamped = new VIEWPOINT();
            SendMessage(Handle,EM_GETSCROLLPOS,IntPtr.Zero,ref clamped);
            cachedHorizontalMaximum = Math.Max(0,clamped.X);
            SendMessage(Handle,EM_SETSCROLLPOS,IntPtr.Zero,ref original);
            horizontalExtentDirty = false;
        }
        finally {
            SendMessage(Handle,WM_SETREDRAW,new IntPtr(1),IntPtr.Zero);
        }
        return cachedHorizontalMaximum;
    }

    private void ApplyExactLineSpacing(int start,int length,float subtractPixels) {
        ApplyExactLineSpacing(start,length,subtractPixels,Font);
    }
    private void ApplyExactLineSpacing(int start,int length,float subtractPixels,Font metricsFont) {
        if (length <= 0 || !IsHandleCreated) return;

        int oldStart = SelectionStart;
        int oldLength = SelectionLength;
        try {
            float dpiY;
            float linePx;
            using (Graphics g = CreateGraphics()) {
                dpiY = g.DpiY;
                linePx = Math.Max(1f,metricsFont.GetHeight(g)-Math.Max(0f,subtractPixels));
            }

            PARAFORMAT2 pf = new PARAFORMAT2();
            pf.cbSize = (uint)Marshal.SizeOf(typeof(PARAFORMAT2));
            pf.dwMask = PFM_LINESPACING;
            pf.rgxTabs = new int[32];
            pf.dyLineSpacing = Math.Max(1,(int)Math.Round(linePx*1440.0/dpiY));
            pf.bLineSpacingRule = 4;

            Select(Math.Max(0,start),Math.Min(length,Math.Max(0,TextLength-start)));
            SendMessage(Handle,EM_SETPARAFORMAT,IntPtr.Zero,ref pf);
        }
        finally {
            Select(Math.Min(oldStart,TextLength),
                Math.Min(oldLength,Math.Max(0,TextLength-Math.Min(oldStart,TextLength))));
        }
    }

    public void ApplyCompactLineSpacing() {
        ApplyExactLineSpacing(0,TextLength,1.0f);
    }

    // RC1 header only: tighten adjacent Unicode box-drawing paragraphs.
    // Regular text, status colors and emoji must keep natural font metrics:
    // the old global 1px reduction clips taller fallback glyphs (notably
    // the green connection icons) and can paint stray colored fragments.
    // The six-line Desktop Commander banner is tightened separately by
    // StyleStartupBanner(), preserving its seamless full-block artwork.
    public void ApplyCompactHeaderLineArtSpacing() {
        if (!IsHandleCreated || TextLength == 0) return;
        string all = Text;
        int start = 0;
        while (start < all.Length) {
            int eol = all.IndexOf('\n',start);
            if (eol < 0) eol = all.Length;
            int contentStart = start;
            while (contentStart < eol && (all[contentStart] == ' ' ||
                   all[contentStart] == '\t' || all[contentStart] == '\r'))
                contentStart++;
            if (contentStart < eol) {
                char c = all[contentStart];
                if (c >= '\u2500' && c <= '\u259F')
                    if(start<ownerBannerStart||start>=ownerBannerEnd)
                        ApplyExactLineSpacing(start,eol-start,1.0f);
            }
            if (eol == all.Length) break;
            start = eol + 1;
        }
    }

    public static string ReadChunk(TextReader reader, int maxChars) {
        if (reader == null || maxChars <= 0) return String.Empty;
        char[] buffer = new char[maxChars];
        int count = reader.Read(buffer, 0, buffer.Length);
        return count > 0 ? new String(buffer, 0, count) : String.Empty;
    }

    public void BeginUpdate() {
        SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
    }

    public void EndUpdate() {
        SendMessage(Handle, WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
        Invalidate();
    }

    public Point GetViewPosition() {
        VIEWPOINT pt = new VIEWPOINT();
        SendMessage(Handle,EM_GETSCROLLPOS,IntPtr.Zero,ref pt);
        return new Point(pt.X,pt.Y);
    }

    public void SetViewPosition(int x,int y) {
        VIEWPOINT pt = new VIEWPOINT();
        pt.X = Math.Max(0,x);
        pt.Y = Math.Max(0,y);
        SendMessage(Handle,EM_SETSCROLLPOS,IntPtr.Zero,ref pt);
    }

    public void RefreshViewport() {
        if (IsDisposed || !IsHandleCreated) return;
        Invalidate();
        Update();
        try {
            BeginInvoke((MethodInvoker)delegate {
                if (IsDisposed || !IsHandleCreated) return;
                Invalidate();
                Update();
            });
        } catch { }
    }

    public void SetSelectionHidden(bool hidden) {
        SendMessage(Handle, EM_HIDESELECTION, hidden ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero);
    }

    // Owner-only: its displayed six-row artwork gets two leading blank
    // columns. Shift the DESKTOP/COMMANDER color split with them, leaving
    // the legacy 61-character boundary byte-for-byte unchanged.
    public bool OwnerBannerLeadingColumn { get; set; }
    private int ownerBannerStart=-1,ownerBannerEnd=-1;
    public string BannerLayoutKey {
        get {
            if(!IsHandleCreated)return String.Empty;
            using(Graphics g=CreateGraphics())return ClientSize.Width.ToString()+":"+g.DpiX.ToString(System.Globalization.CultureInfo.InvariantCulture)+":"+g.DpiY.ToString(System.Globalization.CultureInfo.InvariantCulture)+":"+Font.Name+":"+Font.SizeInPoints.ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
    }

    public bool StyleStartupBanner(Color leftColor, Color rightColor) {
        const string marker = "Remote Connection";
        string all = Text;
        int markerIndex = all.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (markerIndex <= 0) return false;

        // In Owner mode the marker may have an emoji prefix on its own
        // paragraph. It is not a seventh row of the six-row artwork.
        int prefixEnd=OwnerBannerLeadingColumn?all.LastIndexOf('\n',markerIndex)+1:markerIndex;
        string prefix = all.Substring(0, prefixEnd);
        string[] lines = prefix.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n');
        System.Collections.Generic.List<string> banner = new System.Collections.Generic.List<string>();
        for (int i = 0; i < lines.Length; i++) {
            if (!String.IsNullOrWhiteSpace(lines[i])) banner.Add(lines[i]);
        }
        if (banner.Count < 6) return false;

        string[] target = banner.GetRange(banner.Count - 6, 6).ToArray();
        if(OwnerBannerLeadingColumn){
            ownerBannerStart=ownerBannerEnd=-1;
            // Only actual pseudographic rows are fitted; no arbitrary log text.
            foreach(string row in target){
                if(!System.Text.RegularExpressions.Regex.IsMatch(row,@"\A[ \t\u00A0\u2500-\u259F/\\_|.]+\z")||
                   !System.Text.RegularExpressions.Regex.IsMatch(row,@"[\u2500-\u259F]"))return false;
            }
        }
        var rowStarts=new System.Collections.Generic.List<int>();
        SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
        try {
            int searchFrom = 0;
            int bannerStart = -1;
            int bannerEnd = -1;
            foreach (string line in target) {
                int start = all.IndexOf(line, searchFrom, StringComparison.Ordinal);
                if (start < 0) continue;
                rowStarts.Add(start);
                if (bannerStart < 0) bannerStart = start;
                bannerEnd = Math.Max(bannerEnd,start + line.Length);

                int split = Math.Min(OwnerBannerLeadingColumn ? 63 : 61, line.Length);
                if (split > 0) {
                    Select(start, split);
                    SelectionColor = leftColor;
                }
                if (line.Length > split) {
                    Select(start + split, line.Length - split);
                    SelectionColor = rightColor;
                }
                searchFrom = start + line.Length;
            }

            if (bannerStart >= 0 && bannerEnd > bannerStart) {
                if(OwnerBannerLeadingColumn&&rowStarts.Count==6){
                    ownerBannerStart=bannerStart;ownerBannerEnd=bannerEnd;
                    // Keep the approved 9pt font whenever it fits. Measure
                    // actual RichEdit layout after each bounded adjustment.
                    // Do not change the body's font or WordWrap policy.
                    float original=Font.SizeInPoints;
                    float minimum=Math.Min(original,6.0f);
                    for(float size=original;;size=Math.Max(minimum,size-0.25f)){
                        using(var fitted=new Font(Font.FontFamily,size,Font.Style,GraphicsUnit.Point)){
                            for(int i=0;i<rowStarts.Count;i++){
                                Select(rowStarts[i],target[i].Length);
                                SelectionFont=fitted;
                            }
                            ApplyExactLineSpacing(bannerStart,bannerEnd-bannerStart,1.0f,fitted);
                            bool fits=true;
                            for(int i=0;i<rowStarts.Count;i++){
                                int start=rowStarts[i],last=target[i].TrimEnd().Length-1;
                                if(last>=0&&GetPositionFromCharIndex(start).Y!=GetPositionFromCharIndex(start+last).Y){fits=false;break;}
                            }
                            if(fits||size<=minimum)break;
                        }
                    }
                }else ApplyExactLineSpacing(bannerStart,bannerEnd-bannerStart,1.0f);
            }

            Select(TextLength, 0);
            SelectionColor = ForeColor;
        }
        finally {
            SendMessage(Handle, WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
            Invalidate();
        }
        return true;
    }

    public void RemoveLeadingText(int count) {
        if (count <= 0 || TextLength <= 0) return;

        count = Math.Min(count, TextLength);
        bool wasReadOnly = ReadOnly;
        int oldStart = SelectionStart;
        int oldLength = SelectionLength;
        bool hadUserSelection = Focused && oldLength > 0;

        SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
        try {
            if (wasReadOnly) ReadOnly = false;
            Select(0, count);
            SelectedText = String.Empty;

            if (hadUserSelection) {
                int newStart = Math.Max(0, oldStart - count);
                int newLength = Math.Min(oldLength, Math.Max(0, TextLength - newStart));
                Select(newStart, newLength);
            } else {
                Select(TextLength, 0);
            }
        }
        finally {
            if (wasReadOnly) ReadOnly = true;
            SendMessage(Handle, WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
            Invalidate();
        }
    }

    protected override void WndProc(ref Message m) {
        // RichEdit with native scrollbars hidden is controlled by our overlay
        // tracks. Give the Journal its own deterministic physical wheel route.
        // Do not alter the main telemetry-pane focus and wheel contract.
        if (JournalNativeInteraction && m.Msg == WM_MOUSEWHEEL &&
            IsHandleCreated && ((m.WParam.ToInt64() & MK_CONTROL) == 0)) {
            int delta = unchecked((short)((m.WParam.ToInt64() >> 16) & 0xFFFF));
            journalWheelRemainder += delta;
            int notches = journalWheelRemainder / 120;
            journalWheelRemainder %= 120;
            if (notches != 0) {
                int lines = SystemInformation.MouseWheelScrollLines;
                if (lines == -1) lines = Math.Max(1,ClientSize.Height / Math.Max(1,Font.Height) - 1);
                lines = Math.Max(0,Math.Min(120,lines));
                if (lines > 0) {
                    SendMessage(Handle,EM_LINESCROLL,IntPtr.Zero,new IntPtr(-notches*lines));
                    if (ScrollActivity != null) ScrollActivity(this,EventArgs.Empty);
                }
            }
            m.Result=IntPtr.Zero;
            return;
        }
        Point focusView = new Point(-1,-1);
        if (!JournalNativeInteraction && m.Msg == WM_SETFOCUS && IsHandleCreated) {
            try {
                focusView = GetViewPosition();
                preservedFocusX = focusView.X;
                preservedFocusY = focusView.Y;
                preserveViewAfterFocusClick = true;
            } catch { focusView = new Point(-1,-1); }
        }

        bool scrollMessage =
            m.Msg == WM_HSCROLL ||
            m.Msg == WM_VSCROLL ||
            m.Msg == WM_MOUSEWHEEL ||
            m.Msg == WM_MOUSEHWHEEL;

        if (m.Msg == WM_MOUSEWHEEL || m.Msg == WM_MOUSEHWHEEL) {
            long raw = m.WParam.ToInt64();
            int keyState = (int)(raw & 0xFFFF);

            if (!JournalNativeInteraction && (keyState & MK_CONTROL) != 0) {
                raw &= ~((long)MK_CONTROL);
                m.WParam = new IntPtr(raw);
            }
        }

        base.WndProc(ref m);

        if (focusView.X >= 0 && focusView.Y >= 0 && IsHandleCreated) {
            try {
                SetViewPosition(focusView.X,focusView.Y);
                BeginInvoke((MethodInvoker)delegate {
                    if (IsDisposed) return;
                    try { SetViewPosition(focusView.X,focusView.Y); } catch { }
                });
            } catch { }
        }

        if (scrollMessage && ScrollActivity != null && IsHandleCreated) {
            try {
                BeginInvoke((MethodInvoker)delegate {
                    if (!IsDisposed && ScrollActivity != null)
                        ScrollActivity(this, EventArgs.Empty);
                });
            } catch { }
        }
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        bool restoreView = !JournalNativeInteraction && preserveViewAfterFocusClick;
        int savedX = preservedFocusX;
        int savedY = preservedFocusY;
        base.OnMouseDown(e);
        if (restoreView && IsHandleCreated) {
            preserveViewAfterFocusClick = false;
            try {
                SetViewPosition(savedX,savedY);
                BeginInvoke((MethodInvoker)delegate {
                    if (IsDisposed) return;
                    try { SetViewPosition(savedX,savedY); } catch { }
                });
            } catch { }
        }
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        if (!JournalNativeInteraction && e.Control &&
            (e.KeyCode == Keys.Add ||
             e.KeyCode == Keys.Subtract ||
             e.KeyCode == Keys.Oemplus ||
             e.KeyCode == Keys.OemMinus ||
             e.KeyCode == Keys.D0 ||
             e.KeyCode == Keys.NumPad0)) {
            e.SuppressKeyPress = true;
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }

    protected override void OnKeyPress(KeyPressEventArgs e) {
        if (!JournalNativeInteraction && ReadOnly && e.KeyChar != (char)3) {
            e.Handled = true;
            return;
        }
        base.OnKeyPress(e);
    }
}

public class RdcScrollCorner : Control {
    private bool dragging;
    private int lastScreenY;
    private int pendingDelta;
    private readonly System.Diagnostics.Stopwatch dragWatch =
        new System.Diagnostics.Stopwatch();

    public int VerticalDelta { get; private set; }
    public bool IsDragging { get { return dragging; } }
    public event EventHandler DragDelta;

    public RdcScrollCorner() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque, true);
        Cursor = Cursors.SizeNS;
    }

    public static void PaintGrip(Graphics graphics) {
        // Exactly the same 17x17, three-stroke corner artwork in the main
        // activity panel and in the Journal's independent scroll junction.
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Color.FromArgb(18,20,23));
        using (Pen p = new Pen(Color.FromArgb(191,118,67),1.4f)) {
            graphics.DrawLine(p,10,15,15,10);
            graphics.DrawLine(p,6,15,15,6);
            graphics.DrawLine(p,2,15,15,2);
        }
    }
    protected override void OnPaint(PaintEventArgs e) {
        PaintGrip(e.Graphics);
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) {
            dragging = true;
            lastScreenY = Control.MousePosition.Y;
            pendingDelta = 0;
            VerticalDelta = 0;
            dragWatch.Restart();
            Capture = true;
            Invalidate();
        }
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        if (dragging) {
            int nowY = Control.MousePosition.Y;
            int delta = nowY - lastScreenY;
            if (delta != 0) {
                lastScreenY = nowY;
                pendingDelta += delta;
                if (dragWatch.ElapsedMilliseconds >= 16) {
                    VerticalDelta = pendingDelta;
                    pendingDelta = 0;
                    if (DragDelta != null) DragDelta(this, EventArgs.Empty);
                    dragWatch.Restart();
                }
            }
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        if (dragging) {
            if (pendingDelta != 0) {
                VerticalDelta = pendingDelta;
                pendingDelta = 0;
                if (DragDelta != null) DragDelta(this, EventArgs.Empty);
            }
            dragging = false;
            dragWatch.Stop();
            Capture = false;
            VerticalDelta = 0;
            Invalidate();
        }
        base.OnMouseUp(e);
    }

    protected override void OnMouseCaptureChanged(EventArgs e) {
        if (!Capture && dragging) {
            if (pendingDelta != 0) {
                VerticalDelta = pendingDelta;
                pendingDelta = 0;
                if (DragDelta != null) DragDelta(this, EventArgs.Empty);
            }
            dragging = false;
            dragWatch.Stop();
            VerticalDelta = 0;
            Invalidate();
        }
        base.OnMouseCaptureChanged(e);
    }
}

// The Journal's 17px scroll junction is also the resize handle for the
// *whole* modal Form, not the activity-pane height splitter. Use global
// pointer coordinates relative to MouseDown so layout changes never feed
// back into the drag delta when the junction moves during a resize.
public sealed class RdcJournalScrollGrip : Control {
    private Form resizeForm;
    private Point startScreen;
    private Size startFormSize;
    private bool resizing;
    public bool IsResizing { get { return resizing; } }

    public RdcJournalScrollGrip() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque,true);
        Cursor=Cursors.SizeNWSE;
        TabStop=false;
        AccessibleRole=AccessibleRole.Grip;
    }
    protected override void OnPaint(PaintEventArgs e) {
        RdcScrollCorner.PaintGrip(e.Graphics);
    }
    private void ResizeFromScreenPoint(Point screen) {
        if (!resizing || resizeForm==null || resizeForm.IsDisposed) return;
        int width=Math.Max(1,startFormSize.Width + screen.X - startScreen.X);
        int height=Math.Max(1,startFormSize.Height + screen.Y - startScreen.Y);
        // WinForms applies its normal OS constraints; no journal-pane limit.
        Size next=new Size(width,height);
        if (resizeForm.Size != next) resizeForm.Size=next;
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button==MouseButtons.Left) {
            Form form=FindForm();
            if (form!=null && !form.IsDisposed && form.WindowState==FormWindowState.Normal) {
                resizeForm=form;
                startScreen=Control.MousePosition;
                startFormSize=form.Size;
                resizing=true;
                Capture=true;
            }
        }
        base.OnMouseDown(e);
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        if (resizing) ResizeFromScreenPoint(Control.MousePosition);
        base.OnMouseMove(e);
    }
    private void EndResize() {
        if (!resizing) return;
        resizing=false;
        resizeForm=null;
        Capture=false;
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        if (e.Button==MouseButtons.Left) EndResize();
        base.OnMouseUp(e);
    }
    protected override void OnMouseCaptureChanged(EventArgs e) {
        if (!Capture && resizing) EndResize();
        base.OnMouseCaptureChanged(e);
    }
    protected override void Dispose(bool disposing) {
        if (disposing) EndResize();
        base.Dispose(disposing);
    }
}

public class RdcOverlayScrollBar : Control {
    // Shared normal scrollbar track color. Reused for the Owner-only
    // decorative rail so the experiment matches the track pixel-for-pixel.
    public static readonly Color TrackBackground = Color.FromArgb(50,52,56);
    [StructLayout(LayoutKind.Sequential)]
    private struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, ref POINT lParam);

    private const uint EM_GETSCROLLPOS = 0x04DD;
    private const uint EM_SETSCROLLPOS = 0x04DE;
    private const uint EM_GETLINECOUNT = 0x00BA;
    private const uint EM_GETFIRSTVISIBLELINE = 0x00CE;
    private const uint EM_LINESCROLL = 0x00B6;
    private const int SB_LINEUP = 0;
    private const int SB_LINEDOWN = 1;
    private const int SB_PAGEUP = 2;
    private const int SB_PAGEDOWN = 3;
    private const int SB_THUMBPOSITION = 4;
    private const int SB_THUMBTRACK = 5;
    private const int SB_TOP = 6;
    private const int SB_BOTTOM = 7;
    private const int SB_ENDSCROLL = 8;

    private bool dragging;
    private bool hoverThumb;
    private int dragOffset;
    private int dragVisualOffset = -1;
    private int dragLogicalPos = -1;
    private readonly System.Diagnostics.Stopwatch dragWatch =
        new System.Diagnostics.Stopwatch();
    public Control Target { get; set; }
    public bool Vertical { get; set; }
    // Opt-in for the compact lower Owner activity pane ONLY. The orange
    // capsule fills the entire track, irrespective of live text line count.
    // Keep the control/bitmap for the divider animation; it is not a scrollbar.
    public bool DecorativeFullTrack { get; set; }
    public bool IsDragging { get { return dragging; } }

    public bool IsAtEnd {
        get {
            if (Vertical) {
                int totalLines, visibleLines, firstVisible, maxFirst;
                ReadVerticalMetrics(out totalLines,out visibleLines,out firstVisible,out maxFirst);
                return (maxFirst - firstVisible) <= 1;
            }
            int currentOffset,maxOffset,viewportWidth;
            ReadHorizontalMetrics(out currentOffset,out maxOffset,out viewportWidth);
            return (maxOffset-currentOffset) <= 3;
        }
    }

    public void ScrollToEnd() {
        if (Target == null || !Target.IsHandleCreated || !Vertical) return;
        int totalLines,visibleLines,firstVisible,maxFirst;
        ReadVerticalMetrics(out totalLines,out visibleLines,out firstVisible,out maxFirst);
        SetVerticalLinePosition(maxFirst);
        Invalidate();
    }

    public RdcOverlayScrollBar() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque, true);
        Cursor = Cursors.Default;
    }

    private void ReadHorizontalMetrics(out int currentOffset,out int maxOffset,out int viewportWidth) {
        currentOffset = 0;
        maxOffset = 0;
        viewportWidth = Target == null ? 1 : Math.Max(1,Target.ClientSize.Width);
        if (Target == null || !Target.IsHandleCreated) return;

        POINT pt = new POINT();
        SendMessage(Target.Handle,EM_GETSCROLLPOS,IntPtr.Zero,ref pt);
        currentOffset = Math.Max(0,pt.X);

        RdcLogBox log = Target as RdcLogBox;
        if (log != null)
            maxOffset = Math.Max(0,log.GetHorizontalMaximum());
        else
            maxOffset = currentOffset;

        currentOffset = Math.Min(maxOffset,currentOffset);
    }

    private void ReadVerticalMetrics(out int totalLines,out int visibleLines,out int firstVisible,out int maxFirst) {
        totalLines = 1;
        visibleLines = 1;
        firstVisible = 0;
        maxFirst = 0;
        if (Target == null || !Target.IsHandleCreated) return;

        totalLines = Math.Max(1,(int)SendMessage(Target.Handle,EM_GETLINECOUNT,IntPtr.Zero,IntPtr.Zero));
        firstVisible = Math.Max(0,(int)SendMessage(Target.Handle,EM_GETFIRSTVISIBLELINE,IntPtr.Zero,IntPtr.Zero));

        int lineHeight = Math.Max(1,TextRenderer.MeasureText(
            "Ag",
            Target.Font,
            new Size(Math.Max(1,Target.ClientSize.Width),int.MaxValue),
            TextFormatFlags.NoPadding | TextFormatFlags.SingleLine
        ).Height);
        visibleLines = Math.Max(1,Target.ClientSize.Height / lineHeight);
        visibleLines = Math.Min(totalLines,visibleLines);
        maxFirst = Math.Max(0,totalLines-visibleLines);
        firstVisible = Math.Max(0,Math.Min(maxFirst,firstVisible));
    }

    private void Geometry(out Rectangle dec, out Rectangle inc, out Rectangle track, out Rectangle thumb) {
        int arrow = 16;
        if (Vertical) {
            dec = new Rectangle(0,0,Width,arrow);
            inc = new Rectangle(0,Math.Max(0,Height-arrow),Width,arrow);
            track = new Rectangle(2,arrow,Math.Max(1,Width-4),Math.Max(1,Height-arrow*2));
        } else {
            dec = new Rectangle(0,0,arrow,Height);
            inc = new Rectangle(Math.Max(0,Width-arrow),0,arrow,Height);
            track = new Rectangle(arrow,2,Math.Max(1,Width-arrow*2),Math.Max(1,Height-4));
        }

        // A display-only activity rail never gets shorter at specific text
        // offsets or after automatic compact-journal row recalculation.
        if (Vertical && DecorativeFullTrack) {
            thumb = track;
            return;
        }
        int trackLen = Vertical ? track.Height : track.Width;
        int thumbLen;
        int travel;
        int offset;

        if (Vertical) {
            int totalLines, visibleLines, firstVisible, maxFirst;
            ReadVerticalMetrics(out totalLines,out visibleLines,out firstVisible,out maxFirst);
            thumbLen = maxFirst <= 0
                ? trackLen
                : Math.Max(26,(int)Math.Round(trackLen * Math.Min(1.0,(double)visibleLines/totalLines)));
            thumbLen = Math.Min(trackLen,thumbLen);
            travel = Math.Max(0,trackLen-thumbLen);
            offset = (travel == 0 || maxFirst <= 0)
                ? 0
                : (int)Math.Round(firstVisible * (double)travel / maxFirst);
        } else {
            int currentOffset,maxOffset,viewportWidth;
            ReadHorizontalMetrics(out currentOffset,out maxOffset,out viewportWidth);
            long contentWidth = Math.Max((long)viewportWidth,(long)viewportWidth+maxOffset);
            thumbLen = maxOffset <= 0
                ? trackLen
                : Math.Max(26,(int)Math.Round(trackLen*Math.Min(1.0,(double)viewportWidth/contentWidth)));
            thumbLen = Math.Min(trackLen,thumbLen);
            travel = Math.Max(0,trackLen-thumbLen);
            offset = (travel == 0 || maxOffset <= 0)
                ? 0
                : (int)Math.Round(currentOffset*(double)travel/maxOffset);
        }

        if (dragging && dragVisualOffset >= 0)
            offset = Math.Max(0,Math.Min(travel,dragVisualOffset));

        if (Vertical)
            thumb = new Rectangle(track.X, track.Y + offset, track.Width, thumbLen);
        else
            thumb = new Rectangle(track.X + offset, track.Y, thumbLen, track.Height);
    }

    private GraphicsPath Rounded(Rectangle r, int radius) {
        GraphicsPath p = new GraphicsPath();
        int d = radius * 2;
        if (d <= 0 || r.Width <= d || r.Height <= d) { p.AddRectangle(r); return p; }
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Color.FromArgb(18,20,23));
        Rectangle dec,inc,track,thumb;
        Geometry(out dec,out inc,out track,out thumb);

        using (GraphicsPath tp = Rounded(track, Math.Min(6, Math.Min(track.Width,track.Height)/2)))
        using (SolidBrush tb = new SolidBrush(TrackBackground))
            e.Graphics.FillPath(tb,tp);

        // In the compact Owner pane the full-height pseudo-thumb should
        // look like the background track of a real scrollbar. The actual
        // scrollbars keep their normal orange normal/hover/drag colors.
        Color thumbColor = DecorativeFullTrack ? TrackBackground : dragging
            ? Color.FromArgb(166,98,55)
            : hoverThumb
                ? Color.FromArgb(207,132,75)
                : Color.FromArgb(191,118,67);
        using (GraphicsPath hp = Rounded(thumb, Math.Min(7, Math.Min(thumb.Width,thumb.Height)/2)))
        using (SolidBrush hb = new SolidBrush(thumbColor))
            e.Graphics.FillPath(hb,hp);

        // Darker arrows match the inert lower rail; live scrollbars keep
        // their usual brighter gray navigation glyphs and behavior.
        Color arrowColor = DecorativeFullTrack
            ? TrackBackground : Color.FromArgb(112,115,120);
        using (SolidBrush ab = new SolidBrush(arrowColor)) {
            if (Vertical) {
                Point[] up = { new Point(Width/2,5), new Point(Width/2-4,10), new Point(Width/2+4,10) };
                Point[] dn = { new Point(Width/2,Height-5), new Point(Width/2-4,Height-10), new Point(Width/2+4,Height-10) };
                e.Graphics.FillPolygon(ab,up); e.Graphics.FillPolygon(ab,dn);
            } else {
                Point[] lt = { new Point(5,Height/2), new Point(10,Height/2-4), new Point(10,Height/2+4) };
                Point[] rt = { new Point(Width-5,Height/2), new Point(Width-10,Height/2-4), new Point(Width-10,Height/2+4) };
                e.Graphics.FillPolygon(ab,lt); e.Graphics.FillPolygon(ab,rt);
            }
        }
    }

    private void SetHorizontalPosition(int pos) {
        if (Target == null || !Target.IsHandleCreated) return;
        POINT pt = new POINT();
        SendMessage(Target.Handle, EM_GETSCROLLPOS, IntPtr.Zero, ref pt);
        pt.X = Math.Max(0,pos);
        SendMessage(Target.Handle, EM_SETSCROLLPOS, IntPtr.Zero, ref pt);
        Invalidate();
    }

    private void SetVerticalLinePosition(int targetLine) {
        if (Target == null || !Target.IsHandleCreated) return;
        int totalLines,visibleLines,firstVisible,maxFirst;
        ReadVerticalMetrics(out totalLines,out visibleLines,out firstVisible,out maxFirst);
        targetLine = Math.Max(0,Math.Min(maxFirst,targetLine));
        int delta = targetLine-firstVisible;
        if (delta != 0)
            SendMessage(Target.Handle,EM_LINESCROLL,IntPtr.Zero,new IntPtr(delta));
        Invalidate();
    }

    private void SendScroll(int code, int pos) {
        if (Target == null || !Target.IsHandleCreated) return;

        if (Vertical) {
            int totalLines,visibleLines,firstVisible,maxFirst;
            ReadVerticalMetrics(out totalLines,out visibleLines,out firstVisible,out maxFirst);

            if (code == SB_THUMBTRACK || code == SB_THUMBPOSITION)
                SetVerticalLinePosition(pos);
            else if (code == SB_LINEUP)
                SetVerticalLinePosition(firstVisible-1);
            else if (code == SB_LINEDOWN)
                SetVerticalLinePosition(firstVisible+1);
            else if (code == SB_PAGEUP)
                SetVerticalLinePosition(firstVisible-visibleLines);
            else if (code == SB_PAGEDOWN)
                SetVerticalLinePosition(firstVisible+visibleLines);
            else if (code == SB_TOP)
                SetVerticalLinePosition(0);
            else if (code == SB_BOTTOM)
                SetVerticalLinePosition(maxFirst);
            return;
        }

        int currentOffset,maxOffset,viewportWidth;
        ReadHorizontalMetrics(out currentOffset,out maxOffset,out viewportWidth);
        int lineStep = 40;
        int pageStep = Math.Max(lineStep,viewportWidth-40);

        if (code == SB_THUMBTRACK || code == SB_THUMBPOSITION)
            SetHorizontalPosition(pos);
        else if (code == SB_LINEUP)
            SetHorizontalPosition(currentOffset-lineStep);
        else if (code == SB_LINEDOWN)
            SetHorizontalPosition(currentOffset+lineStep);
        else if (code == SB_PAGEUP)
            SetHorizontalPosition(currentOffset-pageStep);
        else if (code == SB_PAGEDOWN)
            SetHorizontalPosition(currentOffset+pageStep);
        else if (code == SB_TOP)
            SetHorizontalPosition(0);
        else if (code == SB_BOTTOM)
            SetHorizontalPosition(maxOffset);
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        // No click/page/thumb navigation in the compact activity indicator.
        // IsAtEnd and the RichEdit keep their original smart-follow contract.
        if (DecorativeFullTrack) { base.OnMouseDown(e); return; }
        Rectangle dec,inc,track,thumb; Geometry(out dec,out inc,out track,out thumb);
        Point p=e.Location;
        if (dec.Contains(p)) SendScroll(SB_LINEUP,0);
        else if (inc.Contains(p)) SendScroll(SB_LINEDOWN,0);
        else if (thumb.Contains(p)) {
            dragging=true;
            dragVisualOffset = Vertical ? (thumb.Y-track.Y) : (thumb.X-track.X);
            dragOffset=(Vertical ? p.Y-thumb.Y : p.X-thumb.X);
            dragLogicalPos=-1;
            dragWatch.Restart();
            Capture=true;
        } else if ((Vertical ? p.Y : p.X) < (Vertical ? thumb.Y : thumb.X))
            SendScroll(SB_PAGEUP,0);
        else
            SendScroll(SB_PAGEDOWN,0);
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        if (DecorativeFullTrack) { base.OnMouseMove(e); return; }
        Rectangle dec,inc,track,thumb; Geometry(out dec,out inc,out track,out thumb);
        hoverThumb=thumb.Contains(e.Location);
        if (dragging) {
            int trackStart=Vertical ? track.Y : track.X;
            int trackLen=Vertical ? track.Height : track.Width;
            int thumbLen=Vertical ? thumb.Height : thumb.Width;
            int travel=Math.Max(0,trackLen-thumbLen);
            int raw=(Vertical ? e.Y : e.X)-dragOffset-trackStart;
            raw=Math.Max(0,Math.Min(travel,raw));
            dragVisualOffset = raw;

            if (travel > 0) {
                int pos;
                if (Vertical) {
                    int totalLines,visibleLines,firstVisible,maxFirst;
                    ReadVerticalMetrics(out totalLines,out visibleLines,out firstVisible,out maxFirst);
                    pos=(int)Math.Round(raw*(double)Math.Max(1,maxFirst)/travel);
                } else {
                    int currentOffset,maxOffset,viewportWidth;
                    ReadHorizontalMetrics(out currentOffset,out maxOffset,out viewportWidth);
                    pos=(int)Math.Round(raw*(double)Math.Max(1,maxOffset)/travel);
                }
                dragLogicalPos = pos;
                if (dragWatch.ElapsedMilliseconds >= 16) {
                    SendScroll(SB_THUMBTRACK,pos);
                    dragWatch.Restart();
                }
            }
        }
        Invalidate();
        base.OnMouseMove(e);
    }

    protected override void OnMouseLeave(EventArgs e) {
        if (!dragging) { hoverThumb=false; Invalidate(); }
        base.OnMouseLeave(e);
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        if (DecorativeFullTrack) { base.OnMouseUp(e); return; }
        if (dragging) {
            int finalPos = dragLogicalPos;
            dragging=false;
            dragWatch.Stop();
            Capture=false;
            dragVisualOffset = -1;
            dragLogicalPos = -1;
            if (finalPos >= 0)
                SendScroll(SB_THUMBPOSITION,finalPos);
            SendScroll(SB_ENDSCROLL,0);
        }
        Invalidate();
        base.OnMouseUp(e);
    }

    protected override void OnMouseCaptureChanged(EventArgs e) {
        if (!Capture && dragging) {
            dragging=false;
            dragWatch.Stop();
            dragVisualOffset=-1;
            dragLogicalPos=-1;
            Invalidate();
        }
        base.OnMouseCaptureChanged(e);
    }
}
'@ -ReferencedAssemblies @('System.Drawing','System.Windows.Forms')

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,WindowsFormsIntegration,System.Xaml
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Forms.Integration;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Controls.Primitives;

public sealed class RdcDividerGlowEffect : ShaderEffect {
    public static readonly DependencyProperty InputProperty =
        RegisterPixelShaderSamplerProperty("Input", typeof(RdcDividerGlowEffect), 0);
    public static readonly DependencyProperty TimeProperty =
        DependencyProperty.Register("Time", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(0)));
    public static readonly DependencyProperty ViewportWidthProperty =
        DependencyProperty.Register("ViewportWidth", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(1000.0, PixelShaderConstantCallback(1)));
    public static readonly DependencyProperty IntensityProperty =
        DependencyProperty.Register("Intensity", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(1.0, PixelShaderConstantCallback(2)));
    public static readonly DependencyProperty ActivityProperty =
        DependencyProperty.Register("Activity", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(3)));
    public static readonly DependencyProperty FaultProperty =
        DependencyProperty.Register("Fault", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(4)));
    public static readonly DependencyProperty RecoveryProperty =
        DependencyProperty.Register("Recovery", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(5)));
    public static readonly DependencyProperty StartupProperty =
        DependencyProperty.Register("Startup", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(6)));
    public static readonly DependencyProperty PassIndexProperty =
        DependencyProperty.Register("PassIndex", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(7)));

    public Brush Input { get { return (Brush)GetValue(InputProperty); } set { SetValue(InputProperty,value); } }
    public double Time { get { return (double)GetValue(TimeProperty); } set { SetValue(TimeProperty,value); } }
    public double ViewportWidth { get { return (double)GetValue(ViewportWidthProperty); } set { SetValue(ViewportWidthProperty,value); } }
    public double Intensity { get { return (double)GetValue(IntensityProperty); } set { SetValue(IntensityProperty,value); } }
    public double Activity { get { return (double)GetValue(ActivityProperty); } set { SetValue(ActivityProperty,value); } }
    public double Fault { get { return (double)GetValue(FaultProperty); } set { SetValue(FaultProperty,value); } }
    public double Recovery { get { return (double)GetValue(RecoveryProperty); } set { SetValue(RecoveryProperty,value); } }
    public double Startup { get { return (double)GetValue(StartupProperty); } set { SetValue(StartupProperty,value); } }
    public double PassIndex { get { return (double)GetValue(PassIndexProperty); } set { SetValue(PassIndexProperty,value); } }

    public RdcDividerGlowEffect(string shaderPath) {
        PixelShader ps = new PixelShader();
        ps.UriSource = new Uri(shaderPath,UriKind.Absolute);
        PixelShader = ps;
        UpdateShaderValue(InputProperty);
        UpdateShaderValue(TimeProperty);
        UpdateShaderValue(ViewportWidthProperty);
        UpdateShaderValue(IntensityProperty);
        UpdateShaderValue(ActivityProperty);
        UpdateShaderValue(FaultProperty);
        UpdateShaderValue(RecoveryProperty);
        UpdateShaderValue(StartupProperty);
        UpdateShaderValue(PassIndexProperty);
    }
}

public sealed class RdcGpuDividerHost : ElementHost {
    private readonly Stopwatch watch;
    private readonly System.Windows.Forms.Timer animationTimer;
    private readonly System.Windows.Forms.Timer visibilityTimer;
    private readonly RdcDividerGlowEffect causticEffect;
    private readonly RdcDividerGlowEffect popupCausticEffect;
    private readonly RdcDividerGlowEffect detailCausticEffect;
    private readonly RdcDividerGlowEffect particleEffect;
    private readonly RdcDividerGlowEffect particleEffectB;
    private readonly RdcDividerGlowEffect particleEffectC;
    private readonly RdcDividerGlowEffect particleEffectD;
    private readonly RdcDividerGlowEffect coreEffect;
    private readonly RdcDividerGlowEffect coreEffectB;
    private readonly RdcDividerGlowEffect coreEffectC;
    private readonly RdcDividerGlowEffect coreEffectD;
    private readonly Popup particlePopup;
    private readonly Rectangle particleSurface;
    private readonly System.Windows.Controls.Grid particleLayer;
    private readonly System.Windows.Controls.Grid popupRoot;
    private readonly System.Windows.Controls.Grid root;
    private readonly SolidColorBrush stateRailBrush;
    private double activity;
    private double targetActivity;
    private double lastFrameSeconds;
    private double animationTime;
    private double faultBlend;
    private double startupBlend;
    private double recoveryBlend;
    private double recoveryAge;
    private bool recoveryActive;
    private bool interactiveMove;
    private bool renderPaused;
    private bool faultMode;
    private bool startupMode;
    private bool stoppedMode;
    private IntPtr particlePopupHwnd = IntPtr.Zero;
    private int lastPopupX = Int32.MinValue;
    private int lastPopupY = Int32.MinValue;
    private int lastPopupW = -1;
    private int lastPopupH = -1;
    private System.Windows.Forms.Form ownerForm;
    // WinForms modal loops can leave a small owner area visible. The WPF
    // particle popup is a separate owned HWND; mere occlusion/opacity checks
    // cannot guarantee it stays below nested Help/Journal windows.
    private int modalLoopDepth;
    private bool modalHooksAttached;

    const int GWL_EXSTYLE = -20;
    const int GWLP_HWNDPARENT = -8;
    const int WS_EX_TOPMOST = 0x00000008;
    const int WS_EX_TRANSPARENT = 0x00000020;
    const int WS_EX_LAYERED = 0x00080000;
    const int WS_EX_NOACTIVATE = 0x08000000;
    const int WM_NCHITTEST = 0x0084;
    const int HTTRANSPARENT = -1;
    const uint GW_HWNDPREV = 3;
    const int DWMWA_CLOAKED = 14;

    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOZORDER = 0x0004;
    const uint SWP_NOACTIVATE = 0x0010;
    const uint SWP_SHOWWINDOW = 0x0040;
    static readonly IntPtr HWND_TOP = IntPtr.Zero;
    static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd,int nIndex);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd,int nIndex,int dwNewLong);
    [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hWnd,int nIndex,IntPtr dwNewLong);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd,IntPtr hWndInsertAfter,int X,int Y,int cx,int cy,uint flags);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd,uint uCmd);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd,out RECT rect);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd,int attr,out int value,int size);

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_NCHITTEST) {
            m.Result = new IntPtr(HTTRANSPARENT);
            return;
        }
        base.WndProc(ref m);
    }

    private IntPtr PopupWndProc(IntPtr hwnd,int msg,IntPtr wParam,IntPtr lParam,ref bool handled) {
        if (msg == WM_NCHITTEST) {
            handled = true;
            return new IntPtr(HTTRANSPARENT);
        }
        return IntPtr.Zero;
    }

    private static bool IsCloaked(IntPtr hwnd) {
        try {
            int value;
            return DwmGetWindowAttribute(
                hwnd,
                DWMWA_CLOAKED,
                out value,
                sizeof(int)) == 0 && value != 0;
        } catch {
            return false;
        }
    }

    // A layered/transparent window's rectangular bounds are not proof
    // of opaque pixel coverage. Overlay utilities and the compositor can
    // leave the owner visible under a full-size transparent rectangle.
    // When opacity is uncertain, continue rendering; true modal/minimize
    // guards and ordinary opaque-window coverage are unchanged.
    private static bool CanProveOpaqueCoverage(IntPtr hwnd) {
        return (GetWindowLong(hwnd,GWL_EXSTYLE)&(WS_EX_TRANSPARENT|WS_EX_LAYERED))==0;
    }

    private bool IsFullyOccluded(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero || !IsWindowVisible(hwnd) || IsIconic(hwnd))
            return true;

        RECT rr;
        if (!GetWindowRect(hwnd,out rr))
            return false;

        System.Drawing.Rectangle target =
            System.Drawing.Rectangle.FromLTRB(
                rr.Left,
                rr.Top,
                rr.Right,
                rr.Bottom);

        if (target.Width <= 0 || target.Height <= 0)
            return true;

        using (System.Drawing.Region remaining =
            new System.Drawing.Region(target))
        using (System.Drawing.Drawing2D.Matrix matrix =
            new System.Drawing.Drawing2D.Matrix()) {

            IntPtr above = GetWindow(hwnd,GW_HWNDPREV);
            int guard = 0;

            while (above != IntPtr.Zero && guard++ < 512) {
                if (above != particlePopupHwnd &&
                    IsWindowVisible(above) &&
                    !IsIconic(above) &&
                    !IsCloaked(above) &&
                    CanProveOpaqueCoverage(above)) {

                    RECT ar;
                    if (GetWindowRect(above,out ar)) {
                        System.Drawing.Rectangle cover =
                            System.Drawing.Rectangle.Intersect(
                                target,
                                System.Drawing.Rectangle.FromLTRB(
                                    ar.Left,
                                    ar.Top,
                                    ar.Right,
                                    ar.Bottom));

                        if (cover.Width > 0 && cover.Height > 0) {
                            remaining.Exclude(cover);
                            if (remaining.GetRegionScans(matrix).Length == 0)
                                return true;
                        }
                    }
                }

                above = GetWindow(above,GW_HWNDPREV);
            }

            return remaining.GetRegionScans(matrix).Length == 0;
        }
    }

    private bool OwnerHasModalDialog() {
        if (modalLoopDepth > 0) return true;
        if (ownerForm == null || ownerForm.IsDisposed) return false;
        // Safety net for a modal that was shown before a visibility probe, or
        // while the dispatcher is transitioning between nested modal loops.
        foreach (System.Windows.Forms.Form dialog in
                 System.Windows.Forms.Application.OpenForms) {
            if (dialog == null || dialog.IsDisposed || !dialog.Modal ||
                !dialog.Visible || dialog == ownerForm) continue;
            System.Windows.Forms.Form parent = dialog.Owner;
            for (int depth=0; parent!=null && depth<16; depth++) {
                if (parent == ownerForm) return true;
                parent = parent.Owner;
            }
        }
        return false;
    }

    private void ThreadModalEntered(object sender,EventArgs e) {
        modalLoopDepth++;
        // Physically close the independent popup HWND. Hiding its WPF root
        // via Opacity alone can leave one DWM-composited frame above a modal.
        SetRenderingPaused(true);
        ClosePopup();
    }

    private void ThreadModalLeft(object sender,EventArgs e) {
        if (modalLoopDepth > 0) modalLoopDepth--;
        // An outer Help dialog may remain open after Journal/Save closes.
        // OwnerHasModalDialog prevents resuming until the entire nest exits.
        UpdateRenderingVisibility();
    }

    private bool ShouldPauseRendering() {
        if (OwnerHasModalDialog()) return true;
        if (ownerForm == null ||
            ownerForm.IsDisposed ||
            ownerForm.Handle == IntPtr.Zero)
            return false;

        if (!ownerForm.Visible ||
            ownerForm.WindowState == FormWindowState.Minimized)
            return true;

        return IsFullyOccluded(ownerForm.Handle);
    }

    private static System.Windows.Media.Color BlendColor(
        System.Windows.Media.Color a,
        System.Windows.Media.Color b,
        double amount
    ) {
        float t=(float)Math.Min(1.0,Math.Max(0.0,amount));
        return System.Windows.Media.Color.FromScRgb(
            1.0f,
            a.ScR+(b.ScR-a.ScR)*t,
            a.ScG+(b.ScG-a.ScG)*t,
            a.ScB+(b.ScB-a.ScB)*t
        );
    }

    private void ApplyCurrentFrame() {
        causticEffect.Time = animationTime;
        popupCausticEffect.Time = animationTime;
        detailCausticEffect.Time = animationTime;
        particleEffect.Time = animationTime;
        particleEffectB.Time = animationTime + 11.37;
        particleEffectC.Time = animationTime + 23.71;
        particleEffectD.Time = animationTime + 35.08;
        coreEffect.Time = animationTime;
        coreEffectB.Time = animationTime + 11.37;
        coreEffectC.Time = animationTime + 23.71;
        coreEffectD.Time = animationTime + 35.08;

        causticEffect.Fault = faultBlend;
        popupCausticEffect.Fault = faultBlend;
        detailCausticEffect.Fault = faultBlend;
        causticEffect.Recovery = recoveryBlend;
        popupCausticEffect.Recovery = recoveryBlend;
        detailCausticEffect.Recovery = recoveryBlend;
        causticEffect.Startup = startupBlend;
        popupCausticEffect.Startup = startupBlend;
        detailCausticEffect.Startup = startupBlend;

        particleEffect.Activity = activity;
        particleEffectB.Activity = activity;
        particleEffectC.Activity = activity;
        particleEffectD.Activity = activity;
        coreEffect.Activity = activity;
        coreEffectB.Activity = activity;
        coreEffectC.Activity = activity;
        coreEffectD.Activity = activity;

        particleEffect.Fault = faultBlend;
        particleEffectB.Fault = faultBlend;
        particleEffectC.Fault = faultBlend;
        particleEffectD.Fault = faultBlend;
        coreEffect.Fault = faultBlend;
        coreEffectB.Fault = faultBlend;
        coreEffectC.Fault = faultBlend;
        coreEffectD.Fault = faultBlend;

        particleEffect.Recovery = recoveryBlend;
        particleEffectB.Recovery = recoveryBlend;
        particleEffectC.Recovery = recoveryBlend;
        particleEffectD.Recovery = recoveryBlend;
        coreEffect.Recovery = recoveryBlend;
        coreEffectB.Recovery = recoveryBlend;
        coreEffectC.Recovery = recoveryBlend;
        coreEffectD.Recovery = recoveryBlend;

        particleEffect.Startup = startupBlend;
        particleEffectB.Startup = startupBlend;
        particleEffectC.Startup = startupBlend;
        particleEffectD.Startup = startupBlend;
        coreEffect.Startup = startupBlend;
        coreEffectB.Startup = startupBlend;
        coreEffectC.Startup = startupBlend;
        coreEffectD.Startup = startupBlend;

        System.Windows.Media.Color rail = BlendColor(
            System.Windows.Media.Color.FromRgb(123,95,162),
            System.Windows.Media.Color.FromRgb(255,199,41),
            startupBlend
        );
        rail = BlendColor(
            rail,
            System.Windows.Media.Color.FromRgb(242,36,51),
            faultBlend
        );
        rail = BlendColor(
            rail,
            System.Windows.Media.Color.FromRgb(46,235,89),
            recoveryBlend
        );
        if (stoppedMode) {
            rail = System.Windows.Media.Color.FromRgb(112,115,120);
        }
        stateRailBrush.Color=rail;

        if (renderPaused || interactiveMove || stoppedMode) {
            popupRoot.Opacity = 0.0;
            return;
        }

        double effectiveTarget = (startupMode || faultMode || recoveryActive || recoveryBlend > 0.002)
            ? 1.0
            : targetActivity;
        popupRoot.Opacity =
            (effectiveTarget > 0.0 || activity > 0.002)
            ? Math.Min(1.0,Math.Max(0.0,activity*1.15))
            : 0.0;
    }

    private void SetRenderingPaused(bool paused) {
        bool modalOpen = OwnerHasModalDialog();
        // A restore, geometry event, or test hook must never force the
        // independent WPF window open while a modal is still on screen.
        if (modalOpen) paused = true;
        if (paused && modalOpen) {
            popupRoot.Opacity = 0.0;
            ClosePopup();
        }
        if (renderPaused == paused)
            return;

        renderPaused = paused;

        if (paused) {
            animationTimer.Stop();
            popupRoot.Opacity = 0.0;
            return;
        }

        // A recovery pulse confirms a live transition. If the window was
        // minimized/occluded mid-pulse, do not replay its frozen green frames
        // when the user restores the window. Real health state is retained.
        recoveryActive = false;
        recoveryBlend = 0.0;
        recoveryAge = 0.0;

        // Do not replay a stale fade after the window was hidden for a while.
        // Resume the frozen animation phase, but snap activity to the current
        // requested state.
        activity = (startupMode || faultMode || recoveryActive || recoveryBlend > 0.002)
            ? 1.0
            : targetActivity;
        lastFrameSeconds = watch.Elapsed.TotalSeconds;

        if (!interactiveMove) {
            EnsurePopupOpen();
            PositionPopup();
        }

        ApplyCurrentFrame();

        if (!animationTimer.Enabled)
            animationTimer.Start();
    }

    private void UpdateRenderingVisibility() {
        SetRenderingPaused(ShouldPauseRendering());
    }

    private void VisibilityTimer_Tick(object sender,EventArgs e) {
        // Repair sandwich ownership/order only while RDC Relay is the active
        // application. Never raise the popups while another app owns focus.
        if (ownerForm != null &&
            !ownerForm.IsDisposed &&
            System.Windows.Forms.Form.ActiveForm == ownerForm) {
            NormalizePopupZOrder();
        }
        UpdateRenderingVisibility();
    }

    private void NormalizePopupWindow(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return;

        if (ownerForm != null &&
            !ownerForm.IsDisposed &&
            ownerForm.Handle != IntPtr.Zero) {
            SetWindowLongPtr(hwnd,GWLP_HWNDPARENT,ownerForm.Handle);
        }

        int exStyle = GetWindowLong(hwnd,GWL_EXSTYLE);
        if ((exStyle & WS_EX_TOPMOST) != 0) {
            SetWindowLong(hwnd,GWL_EXSTYLE,exStyle & ~WS_EX_TOPMOST);
            SetWindowPos(
                hwnd,
                HWND_NOTOPMOST,
                0,0,0,0,
                SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
        }
    }

    private void NormalizePopupZOrder() {
        if (particlePopupHwnd == IntPtr.Zero) return;

        NormalizePopupWindow(particlePopupHwnd);

        if (ownerForm == null ||
            ownerForm.IsDisposed ||
            ownerForm.Handle == IntPtr.Zero)
            return;

        // One owned non-topmost HWND contains the whole sandwich. This avoids
        // cross-popup ShaderEffect failures while keeping the popup above the
        // RDC Relay owner and below unrelated applications.
        SetWindowPos(
            particlePopupHwnd,
            HWND_TOP,
            0,0,0,0,
            SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_SHOWWINDOW);
    }

    private void PositionPopup() {
        if (particlePopup==null || !particlePopup.IsOpen || particlePopupHwnd == IntPtr.Zero || !IsHandleCreated) return;

        RECT rect,popup;
        if (!GetWindowRect(Handle,out rect) ||
            !GetWindowRect(particlePopupHwnd,out popup)) return;
        int w = Math.Max(1,rect.Right-rect.Left);
        // WPF owns the logical 33-DIP popup height. Use the actual native
        // height in the SAME caller coordinate space as the anchor HWND.
        // Never mix a DIP constant with screen coordinates.
        int h = popup.Bottom-popup.Top;
        if(h<=0)return;
        int x = rect.Left;
        int y = rect.Top + (rect.Bottom-rect.Top-h)/2;
        // WPF may reposition its popup after layout/DPI changes. Compare the
        // actual HWND, not just the previously requested rectangle.
        if (popup.Left==x && popup.Top==y && popup.Right-popup.Left==w) return;
        if(SetWindowPos(
            particlePopupHwnd,
            IntPtr.Zero,
            x,y,w,h,
            SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW)){
            lastPopupX=x; lastPopupY=y; lastPopupW=w; lastPopupH=h;
        }
    }

    private void EnsurePopupOpen() {
        // Never re-create a top-level decorative HWND inside a nested modal
        // loop (or while any owned Form.Modal is still visible).
        if (OwnerHasModalDialog()) {
            popupRoot.Opacity=0.0;
            ClosePopup();
            return;
        }
        particlePopup.Width=Math.Max(1.0,root.ActualWidth);

        if (!particlePopup.IsOpen)
            particlePopup.IsOpen=true;

        NormalizePopupZOrder();
        lastPopupX=Int32.MinValue;
        PositionPopup();
    }

    private void ClosePopup() {
        if (particlePopup.IsOpen) particlePopup.IsOpen=false;
        particlePopupHwnd=IntPtr.Zero;

        lastPopupX=Int32.MinValue; lastPopupY=Int32.MinValue;
        lastPopupW=-1; lastPopupH=-1;
    }

    private void OwnerGeometryChanged(object sender,EventArgs e) {
        lastPopupX=Int32.MinValue; lastPopupY=Int32.MinValue;

        if (ownerForm != null &&
            ownerForm.WindowState == FormWindowState.Minimized) {
            UpdateRenderingVisibility();
            return;
        }

        PositionPopup();
    }

    private void OwnerVisibilityChanged(object sender,EventArgs e) {
        UpdateRenderingVisibility();
        if (!renderPaused)
            PositionPopup();
    }

    private void OwnerActivated(object sender,EventArgs e) {
        NormalizePopupZOrder();
        UpdateRenderingVisibility();
        if (!renderPaused)
            PositionPopup();
    }

    private void OwnerDeactivated(object sender,EventArgs e) {
        // Do not raise the popup while another application is taking focus.
        // Native ownership keeps it above RDC Relay inside the owner's Z group;
        // the 1 Hz visibility probe handles genuine occlusion independently.
    }

    private void Animate(object sender,EventArgs e) {
        if (renderPaused)
            return;

        double realNow = watch.Elapsed.TotalSeconds;
        double dt = Math.Max(
            0.0,
            Math.Min(0.12,realNow-lastFrameSeconds));
        lastFrameSeconds = realNow;
        animationTime += dt;

        double effectiveTarget = (startupMode || faultMode || recoveryActive || recoveryBlend > 0.002)
            ? 1.0
            : targetActivity;
        double rate = effectiveTarget > activity ? 5.6 : 3.3;
        double blend = 1.0 - Math.Exp(-rate*dt);
        activity += (effectiveTarget-activity)*blend;
        if (activity < 0.001 && effectiveTarget <= 0.0) activity=0.0;
        if (activity > 0.999 && effectiveTarget >= 1.0) activity=1.0;

        // Startup uses the same smooth palette language as the other states.
        double startupTarget = startupMode ? 1.0 : 0.0;
        double startupRate = startupTarget > startupBlend ? 4.4 : 3.0;
        double startupMix = 1.0 - Math.Exp(-startupRate*dt);
        startupBlend += (startupTarget-startupBlend)*startupMix;
        if (startupBlend < 0.001 && startupTarget <= 0.0) startupBlend=0.0;
        if (startupBlend > 0.999 && startupTarget >= 1.0) startupBlend=1.0;

        // Palette transitions are intentionally softer than activity changes:
        // fault enters and clears as a visible crossfade instead of a hard snap.
        double faultTarget = faultMode ? 1.0 : 0.0;
        double faultRate = faultTarget > faultBlend ? 5.0 : 3.6;
        double faultMix = 1.0 - Math.Exp(-faultRate*dt);
        faultBlend += (faultTarget-faultBlend)*faultMix;
        if (faultBlend < 0.001 && faultTarget <= 0.0) faultBlend=0.0;
        if (faultBlend > 0.999 && faultTarget >= 1.0) faultBlend=1.0;

        // One strong recovery flash: fast recognition, then a deliberately
        // gentle return to the normal palette. No repeated blinking.
        if (recoveryActive) {
            recoveryAge += dt;
            if (recoveryAge < 0.16) {
                double t = recoveryAge / 0.16;
                recoveryBlend = t*t*(3.0-2.0*t);
            } else if (recoveryAge < 0.36) {
                recoveryBlend = 1.0;
            } else if (recoveryAge < 2.76) {
                double t = (recoveryAge-0.36) / 2.40;
                double smooth = t*t*t*(t*(t*6.0-15.0)+10.0);
                recoveryBlend = 1.0-smooth;
            } else {
                recoveryBlend = 0.0;
                recoveryActive = false;
            }
        } else if (recoveryBlend > 0.0) {
            double recoveryMix = 1.0-Math.Exp(-7.0*dt);
            recoveryBlend += (0.0-recoveryBlend)*recoveryMix;
            if (recoveryBlend < 0.001) recoveryBlend=0.0;
        }

        ApplyCurrentFrame();

        if (interactiveMove) {
            // A transparent layered WPF Popup does not track WinForms layout
            // synchronously while the splitter is dragged. Keeping it closed
            // during the gesture prevents compositor trails and visible lag.
            return;
        }

        if (startupMode || startupBlend > 0.002 ||
            faultMode || recoveryActive || recoveryBlend > 0.002 ||
            targetActivity > 0.0 || activity > 0.002) {
            if (!particlePopup.IsOpen)
                EnsurePopupOpen();
            PositionPopup();
        }
    }

    public RdcGpuDividerHost(
        string causticShaderPath,
        string particleShaderPath,
        string causticDetailShaderPath,
        string particleCoreShaderPath
    ) {
        BackColor = System.Drawing.Color.FromArgb(18,20,23);
        TabStop = false;

        causticEffect = new RdcDividerGlowEffect(causticShaderPath);
        causticEffect.Intensity=1.0;

        popupCausticEffect = new RdcDividerGlowEffect(causticShaderPath);
        popupCausticEffect.Intensity=1.0;

        detailCausticEffect = new RdcDividerGlowEffect(causticDetailShaderPath);
        detailCausticEffect.Intensity=1.0;

        particleEffect = new RdcDividerGlowEffect(particleShaderPath);
        particleEffect.Intensity=0.58;
        particleEffect.PassIndex=0.0;

        particleEffectB = new RdcDividerGlowEffect(particleShaderPath);
        particleEffectB.Intensity=0.58;
        particleEffectB.PassIndex=1.0;

        // A second A/B pair doubles visible particle density without making the
        // ps_3_0 bytecode heavier. Time offsets keep the trajectories independent.
        particleEffectC = new RdcDividerGlowEffect(particleShaderPath);
        particleEffectC.Intensity=0.58;
        particleEffectC.PassIndex=1.0;

        particleEffectD = new RdcDividerGlowEffect(particleShaderPath);
        particleEffectD.Intensity=0.58;
        particleEffectD.PassIndex=1.0;

        coreEffect = new RdcDividerGlowEffect(particleCoreShaderPath);
        coreEffect.Intensity=0.58;
        coreEffect.Activity=1.0;
        coreEffect.PassIndex=0.0;

        coreEffectB = new RdcDividerGlowEffect(particleCoreShaderPath);
        coreEffectB.Intensity=0.58;
        coreEffectB.Activity=1.0;
        coreEffectB.PassIndex=1.0;

        coreEffectC = new RdcDividerGlowEffect(particleCoreShaderPath);
        coreEffectC.Intensity=0.58;
        coreEffectC.Activity=1.0;
        coreEffectC.PassIndex=1.0;

        coreEffectD = new RdcDividerGlowEffect(particleCoreShaderPath);
        coreEffectD.Intensity=0.58;
        coreEffectD.Activity=1.0;
        coreEffectD.PassIndex=1.0;

        root = new System.Windows.Controls.Grid();
        root.Background = new SolidColorBrush(System.Windows.Media.Color.FromRgb(18,20,23));
        root.IsHitTestVisible=false;

        stateRailBrush = new SolidColorBrush(System.Windows.Media.Color.FromRgb(123,95,162));
        root.SnapsToDevicePixels=true;
        root.UseLayoutRounding=true;

        Rectangle causticSurface = new Rectangle();
        causticSurface.Fill=Brushes.White;
        causticSurface.Stretch=Stretch.Fill;
        causticSurface.Effect=causticEffect;
        causticSurface.IsHitTestVisible=false;
        root.Children.Add(causticSurface);

        Rectangle topRail = new Rectangle();
        topRail.Height=1.0;
        topRail.VerticalAlignment=VerticalAlignment.Top;
        topRail.Fill=stateRailBrush;
        topRail.IsHitTestVisible=false;
        root.Children.Add(topRail);

        Rectangle bottomRail = new Rectangle();
        bottomRail.Height=1.0;
        bottomRail.VerticalAlignment=VerticalAlignment.Bottom;
        bottomRail.Fill=stateRailBrush;
        bottomRail.IsHitTestVisible=false;
        root.Children.Add(bottomRail);

        System.Windows.Controls.Grid particleSource = new System.Windows.Controls.Grid();
        particleSource.Background=Brushes.Transparent;
        particleSource.IsHitTestVisible=false;

        System.Windows.Controls.Grid popupBand = new System.Windows.Controls.Grid();
        popupBand.Height=7.0;
        popupBand.VerticalAlignment=VerticalAlignment.Center;
        popupBand.Background=Brushes.Transparent;
        popupBand.IsHitTestVisible=false;

        particleSurface = new Rectangle();
        particleSurface.Fill=Brushes.White;
        particleSurface.Stretch=Stretch.Fill;
        particleSurface.Effect=popupCausticEffect;
        particleSurface.IsHitTestVisible=false;
        popupBand.Children.Add(particleSurface);
        particleSource.Children.Add(popupBand);

        // The halo must sit above the static rails but below the caustic-detail
        // and white-core layers. Do not put rails inside the particle shader
        // input: that was one source of the grey-film look.
        particleSource.Effect=particleEffect;

        particleLayer = new System.Windows.Controls.Grid();
        particleLayer.Background=Brushes.Transparent;
        particleLayer.IsHitTestVisible=false;
        particleLayer.Children.Add(particleSource);
        particleLayer.Effect=particleEffectB;

        System.Windows.Controls.Grid particleLayerC = new System.Windows.Controls.Grid();
        particleLayerC.Background=Brushes.Transparent;
        particleLayerC.IsHitTestVisible=false;
        particleLayerC.Children.Add(particleLayer);
        particleLayerC.Effect=particleEffectC;

        System.Windows.Controls.Grid particleLayerD = new System.Windows.Controls.Grid();
        particleLayerD.Background=Brushes.Transparent;
        particleLayerD.IsHitTestVisible=false;
        particleLayerD.Children.Add(particleLayerC);
        particleLayerD.Effect=particleEffectD;

        popupRoot = new System.Windows.Controls.Grid();
        popupRoot.Background=Brushes.Transparent;
        popupRoot.IsHitTestVisible=false;
        popupRoot.Opacity=0.0;
        popupRoot.Children.Add(particleLayerD);

        // Same visual sandwich as the selected lab variant, but all three
        // layers live inside one native popup HWND:
        // halo -> transparent caustic detail -> white soft core.
        System.Windows.Controls.Grid detailBand = new System.Windows.Controls.Grid();
        detailBand.Height=7.0;
        detailBand.VerticalAlignment=VerticalAlignment.Center;
        detailBand.Background=Brushes.Transparent;
        detailBand.IsHitTestVisible=false;

        Rectangle detailSurface = new Rectangle();
        detailSurface.Fill=Brushes.White;
        detailSurface.Stretch=Stretch.Fill;
        detailSurface.Effect=detailCausticEffect;
        detailSurface.IsHitTestVisible=false;
        detailBand.Children.Add(detailSurface);
        popupRoot.Children.Add(detailBand);

        Rectangle coreSeed = new Rectangle();
        coreSeed.Fill=Brushes.White;
        coreSeed.Stretch=Stretch.Fill;
        coreSeed.Effect=coreEffect;
        coreSeed.IsHitTestVisible=false;

        System.Windows.Controls.Grid coreLayer = new System.Windows.Controls.Grid();
        coreLayer.Background=Brushes.Transparent;
        coreLayer.IsHitTestVisible=false;
        coreLayer.Children.Add(coreSeed);
        coreLayer.Effect=coreEffectB;

        System.Windows.Controls.Grid coreLayerC = new System.Windows.Controls.Grid();
        coreLayerC.Background=Brushes.Transparent;
        coreLayerC.IsHitTestVisible=false;
        coreLayerC.Children.Add(coreLayer);
        coreLayerC.Effect=coreEffectC;

        System.Windows.Controls.Grid coreLayerD = new System.Windows.Controls.Grid();
        coreLayerD.Background=Brushes.Transparent;
        coreLayerD.IsHitTestVisible=false;
        coreLayerD.Children.Add(coreLayerC);
        coreLayerD.Effect=coreEffectD;
        popupRoot.Children.Add(coreLayerD);

        particlePopup = new Popup();
        particlePopup.AllowsTransparency=true;
        particlePopup.StaysOpen=true;
        particlePopup.PopupAnimation=PopupAnimation.None;
        particlePopup.PlacementTarget=null;
        particlePopup.Placement=PlacementMode.AbsolutePoint;
        particlePopup.Height=33.0;
        particlePopup.Child=popupRoot;
        particlePopup.IsHitTestVisible=false;
        particlePopup.Focusable=false;

        particlePopup.Opened += delegate(object sender,EventArgs e) {
            HwndSource source = PresentationSource.FromVisual(particleSurface) as HwndSource;
            if (source != null) {
                particlePopupHwnd=source.Handle;
                source.AddHook(PopupWndProc);
                int exStyle=GetWindowLong(particlePopupHwnd,GWL_EXSTYLE);
                exStyle=(exStyle|WS_EX_TRANSPARENT|WS_EX_NOACTIVATE)&~WS_EX_TOPMOST;
                SetWindowLong(particlePopupHwnd,GWL_EXSTYLE,exStyle);
                lastPopupX=Int32.MinValue; lastPopupY=Int32.MinValue;
                NormalizePopupZOrder();
                PositionPopup();
            }
        };
        particlePopup.Closed += delegate(object sender,EventArgs e) {
            particlePopupHwnd=IntPtr.Zero;
        };

        root.Loaded += delegate(object sender,RoutedEventArgs e) {
            ownerForm=FindForm();
            if (ownerForm!=null) {
                ownerForm.LocationChanged+=OwnerGeometryChanged;
                ownerForm.SizeChanged+=OwnerGeometryChanged;
                ownerForm.Resize+=OwnerVisibilityChanged;
                ownerForm.VisibleChanged+=OwnerVisibilityChanged;
                ownerForm.Activated+=OwnerActivated;
                ownerForm.Deactivate+=OwnerDeactivated;
            }

            // WinForms modal-loop notifications fire even when a native
            // SaveFileDialog is nested inside the Journal Form. Subscribe
            // once while the ElementHost is loaded; Dispose unsubscribes.
            if (!modalHooksAttached) {
                System.Windows.Forms.Application.EnterThreadModal+=ThreadModalEntered;
                System.Windows.Forms.Application.LeaveThreadModal+=ThreadModalLeft;
                modalHooksAttached=true;
            }
            // Create the popup once during normal UI startup, then keep the
            // HWND alive for the lifetime of the window. Activity only changes
            // opacity/shader constants and therefore cannot steal foreground.
            EnsurePopupOpen();
            NormalizePopupZOrder();
            PositionPopup();
            visibilityTimer.Start();
            UpdateRenderingVisibility();
        };

        root.SizeChanged += delegate(object sender,SizeChangedEventArgs e) {
            SynchronizeLogicalViewport();
            PositionPopup();
        };

        Child=root;
        activity=0.0;
        targetActivity=0.0;
        lastFrameSeconds=0.0;
        animationTime=0.0;
        faultBlend=0.0;
        startupBlend=0.0;
        recoveryBlend=0.0;
        recoveryAge=0.0;
        recoveryActive=false;
        interactiveMove=false;
        renderPaused=false;
        faultMode=false;
        startupMode=false;

        watch=Stopwatch.StartNew();

        animationTimer=new System.Windows.Forms.Timer();
        animationTimer.Interval=33;
        animationTimer.Tick+=Animate;
        animationTimer.Start();

        visibilityTimer=new System.Windows.Forms.Timer();
        visibilityTimer.Interval=1000;
        visibilityTimer.Tick+=VisibilityTimer_Tick;
    }

    // Deterministic visibility regression hook; never changes Remote MCP state.
    public void SimulateVisibilityPauseForTest(bool paused) { SetRenderingPaused(paused); }
    public int RenderTier { get { return RenderCapability.Tier; } }
    public double ActivityLevel { get { return activity; } }
    public bool ActivityRequested { get { return targetActivity > 0.5; } }
    public bool StoppedVisualActive { get { return stoppedMode && popupRoot.Opacity < 0.001; } }
    public bool FaultRequested { get { return faultMode; } }
    public double FaultBlend { get { return faultBlend; } }
    public bool StartupRequested { get { return startupMode; } }
    public double StartupBlend { get { return startupBlend; } }
    public double RecoveryBlend { get { return recoveryBlend; } }
    public bool RecoveryActive { get { return recoveryActive; } }
    public bool RenderingPaused { get { return renderPaused; } }
    // Read-only visual test hooks: never affect RPC/Remote state or focus.
    public bool ParticlePopupOpenForTest { get { return particlePopup.IsOpen; } }
    public int ModalDepthForTest { get { return modalLoopDepth; } }
    public bool PassConfigurationValid {
        get {
            return
                particleEffect.PassIndex < 0.5 &&
                particleEffectB.PassIndex > 0.5 &&
                particleEffectC.PassIndex > 0.5 &&
                particleEffectD.PassIndex > 0.5 &&
                coreEffect.PassIndex < 0.5 &&
                coreEffectB.PassIndex > 0.5 &&
                coreEffectC.PassIndex > 0.5 &&
                coreEffectD.PassIndex > 0.5 &&
                Math.Abs(particleEffect.Intensity-particleEffectB.Intensity) < 0.000001 &&
                Math.Abs(particleEffect.Intensity-particleEffectC.Intensity) < 0.000001 &&
                Math.Abs(particleEffect.Intensity-particleEffectD.Intensity) < 0.000001 &&
                Math.Abs(coreEffect.Intensity-coreEffectB.Intensity) < 0.000001 &&
                Math.Abs(coreEffect.Intensity-coreEffectC.Intensity) < 0.000001 &&
                Math.Abs(coreEffect.Intensity-coreEffectD.Intensity) < 0.000001;
        }
    }

    public string RunVisualSelfTest() {
        const int width=640;
        const int height=33;

        // ShaderEffect rendering needs a real PresentationSource. Keep the
        // transparent popup alive off-screen during the probe so WPF executes
        // the same layered-window shader path used by the live divider.
        particlePopup.Width=width;
        particlePopup.Height=height;
        particlePopup.HorizontalOffset=-10000.0;
        particlePopup.VerticalOffset=-10000.0;
        if (!particlePopup.IsOpen)
            particlePopup.IsOpen=true;

        activity=1.0;
        targetActivity=1.0;
        animationTime=7.25;
        startupMode=false;
        startupBlend=0.0;
        faultMode=false;
        faultBlend=0.0;
        recoveryActive=false;
        recoveryBlend=0.0;
        renderPaused=false;
        interactiveMove=false;
        ApplyCurrentFrame();

        popupRoot.Width=width;
        popupRoot.Height=height;
        popupRoot.Measure(new System.Windows.Size(width,height));
        popupRoot.Arrange(new System.Windows.Rect(0,0,width,height));
        popupRoot.UpdateLayout();
        System.Windows.Threading.Dispatcher.CurrentDispatcher.Invoke(
            System.Windows.Threading.DispatcherPriority.Render,
            new Action(delegate { }));

        System.Windows.Media.Imaging.RenderTargetBitmap bitmap =
            new System.Windows.Media.Imaging.RenderTargetBitmap(
                width,height,96.0,96.0,
                System.Windows.Media.PixelFormats.Pbgra32);
        bitmap.Render(popupRoot);

        int stride=width*4;
        byte[] pixels=new byte[stride*height];
        bitmap.CopyPixels(pixels,stride,0);

        int transparent=0;
        int visible=0;
        int chromatic=0;
        long alphaSum=0;
        long edgeAlphaSum=0;
        int edgePixels=0;

        for (int y=0;y<height;y++) {
            for (int x=0;x<width;x++) {
                int i=y*stride+x*4;
                int b=pixels[i+0];
                int g=pixels[i+1];
                int r=pixels[i+2];
                int a=pixels[i+3];
                alphaSum+=a;

                if (a<=8) transparent++;
                if (a>=24) visible++;

                int hi=Math.Max(r,Math.Max(g,b));
                int lo=Math.Min(r,Math.Min(g,b));
                if (a>=32 && (hi-lo)>=8) chromatic++;

                if (y<4 || y>=height-4) {
                    edgeAlphaSum+=a;
                    edgePixels++;
                }
            }
        }

        int total=width*height;
        double transparentRatio=(double)transparent/total;
        double visibleRatio=(double)visible/total;
        double chromaticRatio=(double)chromatic/total;
        double meanAlpha=(double)alphaSum/total;
        double edgeMeanAlpha=edgePixels>0 ? (double)edgeAlphaSum/edgePixels : 255.0;

        string metrics=String.Format(
            System.Globalization.CultureInfo.InvariantCulture,
            "transparent={0:F3}; visible={1:F3}; chromatic={2:F3}; meanAlpha={3:F1}; edgeMeanAlpha={4:F1}",
            transparentRatio,visibleRatio,chromaticRatio,meanAlpha,edgeMeanAlpha);

        bool softwareFallback =
            transparentRatio<0.001 &&
            visibleRatio>0.999 &&
            chromaticRatio<0.001 &&
            meanAlpha>254.0 &&
            edgeMeanAlpha>254.0;

        if (!softwareFallback) {
            if (visibleRatio<0.005)
                throw new InvalidOperationException("GPU divider rendered no visible particle/detail energy: "+metrics);
            if (transparentRatio<0.05)
                throw new InvalidOperationException("GPU divider lost transparent background (grey-film risk): "+metrics);
            if (chromaticRatio<0.001)
                throw new InvalidOperationException("GPU divider lost chromatic particle output: "+metrics);
            if (edgeMeanAlpha>96.0)
                throw new InvalidOperationException("GPU divider edge alpha is too high (grey-film risk): "+metrics);
        }

        particlePopup.IsOpen=false;
        particlePopupHwnd=IntPtr.Zero;
        particlePopup.HorizontalOffset=0.0;
        particlePopup.VerticalOffset=0.0;
        return (softwareFallback ? "offscreen-software-fallback; " : "gpu-rendered; ")+metrics;
    }

    public void SetActivity(bool active) {
        targetActivity=active ? 1.0 : 0.0;
    }

    public void SetStopped(bool active) {
        stoppedMode=active;
        if (active) {
            startupMode=false;
            faultMode=false;
            recoveryActive=false;
            recoveryBlend=0.0;
            targetActivity=0.0;
            activity=0.0;
        }
        if (!renderPaused) {
            EnsurePopupOpen();
            PositionPopup();
            ApplyCurrentFrame();
        }
    }

    public void SetStartup(bool active) {
        if (active) stoppedMode=false;
        if (startupMode == active) return;
        startupMode=active;

        if (active) {
            activity=Math.Max(activity,0.74);
        }

        if (!renderPaused) {
            EnsurePopupOpen();
            PositionPopup();
            ApplyCurrentFrame();
        }
    }

    public void SetFault(bool active) {
        if (active) { startupMode=false; stoppedMode=false; }
        if (faultMode == active) return;
        faultMode=active;

        if (active) {
            activity=Math.Max(activity,0.72);
        }

        if (!renderPaused) {
            EnsurePopupOpen();
            PositionPopup();
            ApplyCurrentFrame();
        }
    }

    public void BeginRecoveryFlash() {
        stoppedMode=false;
        startupMode=false;
        faultMode=false;
        recoveryActive=true;
        recoveryAge=0.0;
        activity=Math.Max(activity,0.88);

        if (!renderPaused) {
            EnsurePopupOpen();
            PositionPopup();
            ApplyCurrentFrame();
        }
    }

    public void SetInteractiveMove(bool active) {
        if (interactiveMove == active) return;
        interactiveMove=active;

        if (active) {
            // Destroy the overflow HWND once at drag start. The inline 7 px
            // divider remains visible and moves with normal WinForms layout.
            ClosePopup();
        } else if (!renderPaused) {
            EnsurePopupOpen();
            PositionPopup();
            ApplyCurrentFrame();
        } else {
            popupRoot.Opacity=0.0;
        }
    }

    private void SynchronizeLogicalViewport() {
        if(root==null||particlePopup==null||root.ActualWidth<=0)return;
        double w=root.ActualWidth;
        causticEffect.ViewportWidth=w;
        popupCausticEffect.ViewportWidth=w;
        detailCausticEffect.ViewportWidth=w;
        particleEffect.ViewportWidth=w;
        particleEffectB.ViewportWidth=w;
        particleEffectC.ViewportWidth=w;
        particleEffectD.ViewportWidth=w;
        coreEffect.ViewportWidth=w;
        coreEffectB.ViewportWidth=w;
        coreEffectC.ViewportWidth=w;
        coreEffectD.ViewportWidth=w;
        if (particlePopup.IsOpen && Math.Abs(particlePopup.Width-w)>0.01) particlePopup.Width=w;
    }

    protected override void OnResize(EventArgs e) {
        base.OnResize(e);
        SynchronizeLogicalViewport();
        PositionPopup();
    }

    protected override void Dispose(bool disposing) {
        if (disposing) {
            animationTimer.Stop();
            animationTimer.Tick-=Animate;
            visibilityTimer.Stop();
            visibilityTimer.Tick-=VisibilityTimer_Tick;
            if (modalHooksAttached) {
                System.Windows.Forms.Application.EnterThreadModal-=ThreadModalEntered;
                System.Windows.Forms.Application.LeaveThreadModal-=ThreadModalLeft;
                modalHooksAttached=false;
            }
            if (ownerForm!=null) {
                ownerForm.LocationChanged-=OwnerGeometryChanged;
                ownerForm.SizeChanged-=OwnerGeometryChanged;
                ownerForm.Resize-=OwnerVisibilityChanged;
                ownerForm.VisibleChanged-=OwnerVisibilityChanged;
                ownerForm.Activated-=OwnerActivated;
                ownerForm.Deactivate-=OwnerDeactivated;
                ownerForm=null;
            }
            ClosePopup();
            if (watch!=null) watch.Stop();
        }
        base.Dispose(disposing);
    }
}
'@ -ReferencedAssemblies @(
    'System','System.Core','System.Drawing','System.Windows.Forms',
    'WindowsBase','PresentationCore','PresentationFramework','WindowsFormsIntegration','System.Xaml'
)
$causticShaderPath = Join-Path $root 'divider-caustic.ps'
$causticDetailShaderPath = Join-Path $root 'divider-caustic-detail.ps'
$particleShaderPath = Join-Path $root 'divider-particles.ps'
$particleCoreShaderPath = Join-Path $root 'divider-particles-core.ps'
$gpuDividerAvailable =
    (Test-Path -LiteralPath $causticShaderPath) -and
    (Test-Path -LiteralPath $causticDetailShaderPath) -and
    (Test-Path -LiteralPath $particleShaderPath) -and
    (Test-Path -LiteralPath $particleCoreShaderPath)
# Four WPF ShaderEffect passes use separate layered HWND surfaces. Render Tier
# 0/1 virtual desktops can paint an opaque white popup instead of alpha.
# Fail over to the in-form GDI divider on low-tier Owner displays only.
# This does not change Host, Remote, locale or the legacy 1.5.x renderer.
$script:ownerGpuDividerFallbackReason = ''
if($OwnerGui -and $gpuDividerAvailable){
    try {
        $tier=[int]([System.Windows.Media.RenderCapability]::Tier -shr 16)
        if($tier -lt 2){
            $gpuDividerAvailable=$false
            $script:ownerGpuDividerFallbackReason='WPF_TIER_'+[string]$tier
        }
    }catch{
        $gpuDividerAvailable=$false
        $script:ownerGpuDividerFallbackReason='WPF_TIER_UNAVAILABLE'
    }
}

[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'RDC Relay'
$baseWindowWidth = 1074
$baseWindowHeight = 900
$paneMinHeightPreferred = 125 # Legacy and activity baseline are unchanged.
# G98: keep fixed-width line art and text; only emoji spans use a fallback font.
# A future Help/Journal preference can toggle this Owner-only text preset.
$script:ownerTextFontFamily='Consolas'
$script:ownerEmojiFontFamily='Segoe UI Emoji'
$script:ownerEmojiEnabled=[bool]$OwnerGui
function Get-Rc1HeaderBannerMinimum {
    # The pinned Remote header's Desktop Commander banner occupies six
    # compact rows. Keep all six visible when the owner header is collapsed.
    # Include its 7px draggable divider and a tiny 2px bottom breathing room.
    $probe=New-Object Windows.Forms.RichTextBox
    $font=New-Object Drawing.Font($script:ownerTextFontFamily,9)
    try{
        $probe.Font=$font
        $probe.BorderStyle=[Windows.Forms.BorderStyle]::None
        $probe.WordWrap=$false
        $probe.Text="Ag`nAg"
        [void]$probe.Handle
        $linePitch=$probe.GetPositionFromCharIndex(3).Y -
                   $probe.GetPositionFromCharIndex(0).Y
        if($linePitch -lt 8 -or $linePitch -gt 50){throw 'RC1_INVALID_HEADER_LINE_PITCH'}
        return [Math]::Max(64,(6*$linePitch)+7+2)
    }finally{
        $probe.Dispose()
        $font.Dispose()
    }
}
$headerPaneMinHeightPreferred=if($OwnerGui){Get-Rc1HeaderBannerMinimum}else{$paneMinHeightPreferred}
function Get-Rc1ActivityRowReserve([int]$baselineHeight) {
    # Measure the actual compact RichEdit row pitch, not the unconstrained
    # Segoe Emoji font height. RdcLogBox.ApplyCompactLineSpacing() explicitly
    # fixes paragraph advance to the Consolas body font; isolated mixed-run
    # RichEdit tests confirm inline emoji still advance by the body pitch.
    # Owner reserves six events plus two blank rows and 17px for scrollbars.
    $probe=New-Object Windows.Forms.RichTextBox
    $font=New-Object Drawing.Font($script:ownerTextFontFamily,10)
    try {
        $probe.Font=$font
        $probe.BorderStyle=[Windows.Forms.BorderStyle]::None
        $probe.WordWrap=$false
        $probe.Text="Ag`nAg"
        [void]$probe.Handle
        $linePitch=$probe.GetPositionFromCharIndex(3).Y -
                   $probe.GetPositionFromCharIndex(0).Y
        if($linePitch -lt 8 -or $linePitch -gt 50){throw 'RC1_INVALID_LOG_LINE_PITCH'}
        # Both minimum-pane and journal-capacity calculations use the same
        # measured RichEdit line pitch.
        $existingSlack=([Math]::Max(1,$baselineHeight-17) % $linePitch)
        if($OwnerGui){
            $script:ownerJournalLinePitch=[int]$linePitch
            # Six visible events plus one empty row above and below.
            # Use exactly the body pitch also used by the live line formatter.
            return [Math]::Max(0,(8*$linePitch)+17-$baselineHeight)
        }
        return $(if($existingSlack -eq 0){$linePitch}else{$linePitch-$existingSlack})
    }finally{
        $probe.Dispose()
        $font.Dispose()
    }
}
$activityRowReserve=if($OwnerGui){Get-Rc1ActivityRowReserve $paneMinHeightPreferred}else{0}
$activityPaneMinHeightPreferred=$paneMinHeightPreferred+$activityRowReserve
$startupScreen = [Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position)
$startupWorkArea = $startupScreen.WorkingArea
$windowWidth = [Math]::Min($baseWindowWidth,$startupWorkArea.Width)
$windowHeight = [Math]::Min($baseWindowHeight,$startupWorkArea.Height)
$form.Size = New-Object Drawing.Size($windowWidth,$windowHeight)
$preferredMinimumHeight = 78 + 38 + $headerPaneMinHeightPreferred + $activityPaneMinHeightPreferred + 7 + 48
if($OwnerGui){
    # Stop bottom-edge resizing exactly where both text panes reach their
    # measured minima. Header minimum ALREADY contains the 7px divider;
    # account only for the actual Windows non-client frame (no extra row).
    $windowFrameHeight=[Math]::Max(0,$form.Height-$form.ClientSize.Height)
    $minimumWindowHeight=78+38+$headerPaneMinHeightPreferred+
        $activityPaneMinHeightPreferred+$windowFrameHeight
}else{
    $minimumWindowHeight=[Math]::Min($windowHeight,$preferredMinimumHeight)
}
$form.MinimumSize = New-Object Drawing.Size($windowWidth,$minimumWindowHeight)
$form.MaximumSize = New-Object Drawing.Size($windowWidth,10000)
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $false
$form.SizeGripStyle = [Windows.Forms.SizeGripStyle]::Hide
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point(
    ($startupWorkArea.Left + [Math]::Max(0,[int](($startupWorkArea.Width-$windowWidth)/2))),
    ($startupWorkArea.Top + [Math]::Max(0,[int](($startupWorkArea.Height-$windowHeight)/2)))
)
$form.BackColor = [Drawing.Color]::FromArgb(29,32,36)
$form.ForeColor = [Drawing.Color]::Gainsboro
$form.Font = New-Object Drawing.Font('Segoe UI',10)
if (Test-Path $iconPath) { $form.Icon = New-Object Drawing.Icon($iconPath) }
$top = New-Object Windows.Forms.TableLayoutPanel
$top.Dock = 'Top'
$top.Height = 78
# Owner final 1px alignment: the capsule and both rows move together
# right by 1px from G127 (painted X=14 -> X=15); their mutual 13px gap,
# right-side action positions and all vertical padding remain unchanged.
$top.Padding = if($OwnerGui){[Windows.Forms.Padding]::new(2,9,13,9)}else{
    [Windows.Forms.Padding]::new(16,9,16,9)
}
$top.Add_Paint({
    param($sender,$e)
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(123,95,162),1)
    try {
        $y = [Math]::Max(0,$sender.ClientSize.Height-1)
        $e.Graphics.DrawLine($pen,0,$y,$sender.ClientSize.Width,$y)
    } finally {
        $pen.Dispose()
    }
})
$top.ColumnCount = 3
$top.RowCount = 2
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,38)))
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,$(if($OwnerGui){307}else{304}))))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$statusDot = New-Object RdcStatusIndicator
$statusDot.Dock = 'Fill'
$statusDot.IndicatorColor = [Drawing.Color]::Gray
# RC1 Owner-only optical capsule; the stable/legacy status dot stays round.
$statusDot.OwnerCapsule = [bool]$OwnerGui
$title = New-Object Windows.Forms.Label
$title.Text = 'RDC Relay'
$title.Dock = 'None'
$title.AutoSize = $true
$title.Margin = [Windows.Forms.Padding]::new(0,3,8,0)
$title.TextAlign = 'MiddleLeft'
$title.Font = New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
# Keep the familiar Windows question glyph. In Owner RC1 the Help action
# belongs at the far right of the existing 38px footer, not in the title row.
$titleHost = New-Object Windows.Forms.FlowLayoutPanel
$titleHost.Name='rc1-title-help-row'
$titleHost.Dock=[Windows.Forms.DockStyle]::Fill
$titleHost.FlowDirection=[Windows.Forms.FlowDirection]::LeftToRight
$titleHost.WrapContents=$false
$titleHost.Margin=[Windows.Forms.Padding]::new(0)
$titleHost.Padding=[Windows.Forms.Padding]::new(0)
$statusDetail = New-Object Windows.Forms.Label
$statusDetail.Dock = 'Fill'
$statusDetail.TextAlign = 'MiddleLeft'
$statusDetail.ForeColor = [Drawing.Color]::Silver
$finish = New-Object RdcRoundedButton
$finish.BackColor = $form.BackColor
$finish.Text = 'Остановить'
$finish.Glyph = [RdcButtonGlyph]::Stop
$finish.Size = New-Object Drawing.Size(120,36)
$finish.Margin = New-Object Windows.Forms.Padding(16,0,0,0)
$finish.AmbientShadowRadius = if($OwnerGui){3}else{0}


$accountButton = New-Object RdcRoundedButton
$accountButton.BackColor = $form.BackColor
$accountButton.Text = 'Аккаунт'
$accountButton.ShowMenuChevron = $true
$accountButton.AccessibleName = 'Аккаунт, открыть меню'
$accountButton.Tone = [RdcButtonTone]::Neutral
$accountButton.Size = New-Object Drawing.Size(120,36)
$accountButton.Margin = New-Object Windows.Forms.Padding(0)
$accountButton.AmbientShadowRadius = if($OwnerGui){3}else{0}

$helpButton = New-Object Windows.Forms.Button
$helpButton.Name='rc1-help-open'
$helpButton.BackColor=$form.BackColor
$helpButton.ForeColor=$form.ForeColor
$helpButton.Text=''
$helpButton.Image=([Drawing.SystemIcons]::Question).ToBitmap()
if($OwnerGui){
    # Keep footer and click target unchanged. A 22x24 transparent bitmap
    # vertically centers 22px of icon art exactly 1px above the prior
    # 22x22 centered bitmap, with no clipping or TableLayout movement.
    $helpImageSource=$helpButton.Image
    $helpImage=New-Object Drawing.Bitmap(22,24)
    $helpGraphics=[Drawing.Graphics]::FromImage($helpImage)
    try {
        $helpGraphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $helpGraphics.DrawImage($helpImageSource,0,0,22,22)
    }finally{$helpGraphics.Dispose();$helpImageSource.Dispose()}
    $helpButton.Image=$helpImage
}
$helpButton.ImageAlign=[Drawing.ContentAlignment]::MiddleCenter
$helpButton.Size=if($OwnerGui){[Drawing.Size]::new(24,24)}else{[Drawing.Size]::new(32,32)}
# Owner: preserve the 24px click target; the transparent 22x24 image
# shifts only the icon artwork 1px upward while keeping native centering.
$helpButton.Margin=if($OwnerGui){[Windows.Forms.Padding]::new(1,0,0,0)}else{[Windows.Forms.Padding]::new(0)}
$helpButton.Padding=[Windows.Forms.Padding]::new(0)
$helpButton.FlatStyle=[Windows.Forms.FlatStyle]::Flat
$helpButton.FlatAppearance.BorderSize=0
$helpButton.FlatAppearance.MouseOverBackColor=$helpButton.BackColor
$helpButton.FlatAppearance.MouseDownBackColor=$helpButton.BackColor
$helpButton.UseVisualStyleBackColor=$false
$helpButton.Cursor=[Windows.Forms.Cursors]::Hand
$helpButton.AccessibleRole=[Windows.Forms.AccessibleRole]::PushButton
$helpButton.AccessibleName='Справка / О программе'
$finish.TabIndex = 0
$accountButton.TabIndex = 1
$helpButton.TabIndex = 2
[void]$titleHost.Controls.Add($title)
if(-not $OwnerGui){[void]$titleHost.Controls.Add($helpButton)}

$actions = if($OwnerGui){New-Object RdcHeaderActionPanel}else{New-Object Windows.Forms.FlowLayoutPanel}
$actions.Dock = 'Fill'
$actions.BackColor = $form.BackColor
$actions.FlowDirection = 'RightToLeft'
$actions.WrapContents = $false
$actions.Margin = New-Object Windows.Forms.Padding(0)
$actions.Padding = if($OwnerGui){[Windows.Forms.Padding]::new(0,12,3,12)}else{[Windows.Forms.Padding]::new(0,12,0,12)}
$actions.Controls.Add($finish)
$actions.Controls.Add($accountButton)

$tip = New-Object Windows.Forms.ToolTip
$tip.SetToolTip($accountButton,'Действия с аккаунтом')
$tip.SetToolTip($helpButton,'Справка / О программе')

$menuColors = New-Object RdcMenuColorTable
$menuRenderer = New-Object Windows.Forms.ToolStripProfessionalRenderer -ArgumentList $menuColors

$accountMenu = if($OwnerGui){New-Object RdcOwnerPaddedContextMenuStrip}else{New-Object Windows.Forms.ContextMenuStrip}
$accountMenu.BackColor = [Drawing.Color]::FromArgb(38,41,46)
$accountMenu.ForeColor = [Drawing.Color]::Gainsboro
$accountMenu.Renderer = if($OwnerGui){New-Object RdcOwnerAccountMenuRenderer -ArgumentList $menuColors}else{$menuRenderer}
if($OwnerGui){[RdcOwnerAccountMenuRenderer]::ConfigureOwnerMenu($accountMenu)}
$switchAccountItem = New-Object Windows.Forms.ToolStripMenuItem
$switchAccountItem.Text = 'Сменить аккаунт…'
$reconnectItem = New-Object Windows.Forms.ToolStripMenuItem
$reconnectItem.Text = 'Переподключить'
$devicesItem = New-Object Windows.Forms.ToolStripMenuItem
$devicesItem.Text = 'Управление устройствами…'
$verifyDeviceItem = New-Object Windows.Forms.ToolStripMenuItem
$verifyDeviceItem.Text = 'Подтвердить новое устройство…'
[void]$accountMenu.Items.Add($switchAccountItem)
[void]$accountMenu.Items.Add($reconnectItem)
$autoConnectAuthItem=New-Object Windows.Forms.ToolStripMenuItem
$autoConnectAuthItem.Name='rc1-auto-connect-toggle'
$autoConnectAuthItem.Text='Автоподключение'
$autoConnectAuthItem.CheckOnClick=$true
$autoConnectAuthItem.Enabled=$false
if($OwnerGui){[void]$accountMenu.Items.Add($autoConnectAuthItem)}
[void]$accountMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void]$accountMenu.Items.Add($devicesItem)
if(-not $OwnerGui){[void]$accountMenu.Items.Add($verifyDeviceItem)}
$quotaAuthItem=New-Object Windows.Forms.ToolStripMenuItem
$quotaAuthItem.Text='Выводить остаток вызовов'
$quotaAuthItem.Name='rc1-quota-display-toggle'
$quotaAuthItem.AccessibleDescription='Флажок: включить или выключить автоматическое отображение остатка вызовов.'
$quotaAuthItem.CheckOnClick=[bool]$OwnerGui
$quotaAuthItem.Visible=[bool]$OwnerGui
$quotaAuthItem.Enabled=$false
if($OwnerGui){[void]$accountMenu.Items.Add($quotaAuthItem)}
# Program settings (language, auto-update) belong exclusively to the tray.
# Account menu contains only account, connection, devices and quota controls.

$top.Controls.Add($statusDot,0,0)
$top.SetRowSpan($statusDot,2)
$top.Controls.Add($titleHost,1,0)
$top.Controls.Add($statusDetail,1,1)
$top.Controls.Add($actions,2,0)
$top.SetRowSpan($actions,2)
$bottom = New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock = 'Bottom'
$bottom.Height = 38
$bottom.BackColor = $form.BackColor
# Owner footer height and inset stay fixed; Help alone has a 1px
# upward optical alignment relative to the version and update notice.
$bottom.Padding = if($OwnerGui){[Windows.Forms.Padding]::new(12,7,7,6)}else{[Windows.Forms.Padding]::new(12,7,12,6)}
$bottom.ColumnCount = if($OwnerGui){3}else{2}
$bottom.RowCount = 1
if($OwnerGui){
    # The legacy implicit auto row can calculate as 100px and clip controls.
    # Fix ONLY the Owner inner row at 25px; outer footer remains 38px.
    [void]$bottom.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,25)))
}
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,$(if($OwnerGui){110}else{440}))))
if($OwnerGui){
    # Fixed 25px right cell: 1px gap + 24px Help button. Update animation
    # only expands the adjacent column, without shifting the Help button.
    [void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,25)))
}
$accentOrange = [Drawing.Color]::FromArgb(191,118,67)
$accentPurple = [Drawing.Color]::FromArgb(74,55,103)
$statusGreen = [Drawing.Color]::LightGreen
$accentWait = [Drawing.Color]::Khaki
$accentNetwork = [Drawing.Color]::LightSkyBlue
$accentStorage = [Drawing.Color]::LightSteelBlue
$accentPresence = [Drawing.Color]::Plum
# RC1 Owner: semantic emoji colors follow their actual message meaning.
# Keep legacy 1.5.18 highlight colors unchanged.
$accentSuccess=if($OwnerGui){$statusGreen}else{$accentPurple}
$accentStop=if($OwnerGui){[Drawing.Color]::LightCoral}else{$accentOrange}
$accentGreeting=if($OwnerGui){[Drawing.Color]::Gainsboro}else{$accentPresence}
$stateOnline = [Drawing.Color]::LimeGreen
$stateOffline = [Drawing.Color]::Tomato
$commandAccent = [Drawing.Color]::Gold
$headerValue = [Drawing.Color]::PaleTurquoise

$infoHost = New-Object Windows.Forms.FlowLayoutPanel
$infoHost.Dock = 'Fill'
$infoHost.BackColor = $form.BackColor
$infoHost.FlowDirection = 'LeftToRight'
$infoHost.WrapContents = $false
$infoHost.Margin = New-Object Windows.Forms.Padding(0)
$infoHost.Padding = New-Object Windows.Forms.Padding(0)

$accountInfo = New-Object Windows.Forms.Label
$accountInfo.AutoSize = $true
$accountInfo.Text = 'определяю…'
$accountInfo.ForeColor = [Drawing.Color]::Silver
$accountInfo.Margin = New-Object Windows.Forms.Padding(0,2,0,0)

$accountSep = New-Object Windows.Forms.Label
$accountSep.AutoSize = $true
$accountSep.Text = '|'
$accountSep.ForeColor = $accentOrange
$accountSep.Margin = New-Object Windows.Forms.Padding(6,2,6,0)

$runtimeLeft = New-Object Windows.Forms.Label
$runtimeLeft.AutoSize = $true
$runtimeLeft.ForeColor = [Drawing.Color]::Silver
$runtimeLeft.Margin = New-Object Windows.Forms.Padding(0,2,0,0)

$runtimeSep = New-Object Windows.Forms.Label
$runtimeSep.AutoSize = $true
$runtimeSep.Text = '|'
$runtimeSep.ForeColor = $accentOrange
$runtimeSep.Margin = New-Object Windows.Forms.Padding(6,2,6,0)

$runtimeRight = New-Object Windows.Forms.Label
$runtimeRight.AutoSize = $true
$runtimeRight.ForeColor = [Drawing.Color]::Silver
$runtimeRight.Margin = New-Object Windows.Forms.Padding(0,2,0,0)

# Owner-only account quota label: no change to the stable 1.5.18 footer.
$quotaLabel = New-Object Windows.Forms.Label
$quotaLabel.AutoSize = $true
$quotaLabel.Text = 'Остаток вызовов: --%'
$quotaLabel.ForeColor = [Drawing.Color]::Silver
$quotaLabel.Margin = New-Object Windows.Forms.Padding(0,2,0,0)
$quotaLabel.Visible = $OwnerGui

$infoHost.Controls.Add($accountInfo)
# Keep the stable 1.5.18 orange pipe separators between footer values,
# including Owner's account | quota | uptime layout (PID lives in About).
$infoHost.Controls.Add($accountSep)
if(-not $OwnerGui){$infoHost.Controls.Add($runtimeLeft)}
if($OwnerGui){$infoHost.Controls.Add($quotaLabel)}
$infoHost.Controls.Add($runtimeSep)
$infoHost.Controls.Add($runtimeRight)

$hintHost = New-Object Windows.Forms.FlowLayoutPanel
$hintHost.Dock = 'Fill'
$hintHost.FlowDirection = 'RightToLeft'
$hintHost.WrapContents = $false
$hintHost.Margin = New-Object Windows.Forms.Padding(0)
$hintHost.Padding = New-Object Windows.Forms.Padding(0)

$hint = New-Object Windows.Forms.Label
$hint.AutoSize = $true
$hint.Text = if($OwnerGui){''}else{'Крестик закрывает окно вместе с remote-процессом.'}
$hint.ForeColor = [Drawing.Color]::Gray
$hint.Margin = New-Object Windows.Forms.Padding(0,2,0,0)

$hintSep = New-Object Windows.Forms.Label
$hintSep.AutoSize = $true
$hintSep.Text = '•'
$hintSep.ForeColor = $accentOrange
$hintSep.Margin = New-Object Windows.Forms.Padding(0,2,6,0)

$hintVersion = New-Object Windows.Forms.Label
$hintVersion.AutoSize = $true
$hintVersion.Text = 'v' + $appVersion
$hintVersion.Font = if($OwnerGui){$form.Font}else{$hint.Font}
$hintVersion.ForeColor = if($OwnerGui){$accountInfo.ForeColor}else{[Drawing.Color]::Gray}
# Owner aligns the version with the account/quota/uptime text; the right
# column remains independently right-anchored across window widths.
$hintVersion.Margin = New-Object Windows.Forms.Padding(0,$(if($OwnerGui){2}else{6}),0,0)

if(-not $OwnerGui){
    $hintHost.Controls.Add($hint)
    $hintHost.Controls.Add($hintSep)
}
$hintHost.Controls.Add($hintVersion)
if($OwnerGui){$tip.SetToolTip($quotaLabel,'Последний подтверждённый остаток вызовов Remote Desktop Commander. Без нового ответа сервиса значение устаревает.')}

$bottom.Controls.Add($infoHost,0,0)
$bottom.Controls.Add($hintHost,1,0)
if($OwnerGui){
    $helpButton.Anchor=[Windows.Forms.AnchorStyles]::None
    $bottom.Controls.Add($helpButton,2,0)
}
# Owner-only subtle, non-layout animation of the version in the far corner.
# No motion in high-contrast mode. The stable updater footer is unaffected.
if($OwnerGui){
    $script:ownerVersionIntroTimer=New-Object Windows.Forms.Timer
    $script:ownerVersionIntroTimer.Interval=25
    $script:ownerVersionIntroFrame=0
    $hintVersion.ForeColor=$form.BackColor
    $script:ownerVersionIntroTimer.Add_Tick({
        $script:ownerVersionIntroFrame++
        $t=[Math]::Min(1.0,([double]$script:ownerVersionIntroFrame/7.0))
        $smooth=$t*$t*(3.0-2.0*$t)
        $from=$form.BackColor
        $to=$accountInfo.ForeColor
        $r=[int][Math]::Round($from.R+($to.R-$from.R)*$smooth)
        $g=[int][Math]::Round($from.G+($to.G-$from.G)*$smooth)
        $b=[int][Math]::Round($from.B+($to.B-$from.B)*$smooth)
        $hintVersion.ForeColor=[Drawing.Color]::FromArgb($r,$g,$b)
        if($t -ge 1.0){$script:ownerVersionIntroTimer.Stop()}
    })
    $form.Add_Shown({
        if([Windows.Forms.SystemInformation]::HighContrast){
            $hintVersion.ForeColor=$accountInfo.ForeColor
        }else{$script:ownerVersionIntroTimer.Start()}
    })
}
$tip.SetToolTip($accountInfo,'Аккаунт Desktop Commander, к которому привязан этот компьютер')

$contentHost = New-Object Windows.Forms.TableLayoutPanel
$contentHost.Dock = 'Fill'
$contentHost.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$contentHost.Margin = New-Object Windows.Forms.Padding(0)
$contentHost.Padding = New-Object Windows.Forms.Padding(0)
$contentHost.ColumnCount = 1
$contentHost.RowCount = 2
$activityDefaultHeight = $activityPaneMinHeightPreferred
[void]$contentHost.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$contentHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$contentHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$activityDefaultHeight)))

$headerHost = New-Object Windows.Forms.TableLayoutPanel
$headerHost.Dock = 'Fill'
$headerHost.Margin = New-Object Windows.Forms.Padding(0)
$headerHost.Padding = New-Object Windows.Forms.Padding(0)
$headerHost.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$headerHost.ColumnCount = 1
$headerHost.RowCount = 2
[void]$headerHost.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$headerHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$headerHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,7)))

$headerTextHost = New-Object Windows.Forms.TableLayoutPanel
$headerTextHost.Dock = 'Fill'
$headerTextHost.Margin = New-Object Windows.Forms.Padding(0)
$headerTextHost.Padding = New-Object Windows.Forms.Padding(0)
$headerTextHost.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$headerTextHost.ColumnCount = 2
$headerTextHost.RowCount = 1
[void]$headerTextHost.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$headerTextHost.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,17)))
[void]$headerTextHost.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))

$headerLog = New-Object RdcLogBox
$headerLog.Dock = 'Fill'
# Two physical pixels of breathing room above the Owner pseudographic art.
# Keep legacy RichEdit layout, the underlying pane and its scrollbar intact.
if($OwnerGui){$headerLog.Margin = [Windows.Forms.Padding]::new(3,5,3,3)}
$headerLog.OwnerBannerLeadingColumn = [bool]$OwnerGui
$headerLog.ReadOnly = $true
$headerLog.TabStop = $false
$headerLog.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$headerLog.ForeColor = [Drawing.Color]::Gainsboro
$headerLog.Font = New-Object Drawing.Font($script:ownerTextFontFamily,9)
$headerLog.WordWrap = $true
$headerLog.BorderStyle = 'None'
$headerLog.ScrollBars = [Windows.Forms.RichTextBoxScrollBars]::None
$headerLog.DetectUrls = $true
$headerLog.Add_LinkClicked({ try { Start-Process $_.LinkText } catch {} })

$headerVScroll = New-Object RdcOverlayScrollBar
$headerVScroll.Target = $headerLog
$headerVScroll.Vertical = $true
$headerVScroll.Dock = 'Fill'
$headerVScroll.Margin = New-Object Windows.Forms.Padding(0)

$headerDivider = New-Object Windows.Forms.Panel
$headerDivider.Dock = 'Fill'
$headerDivider.Margin = New-Object Windows.Forms.Padding(0)
$headerDivider.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$headerDivider.Cursor = [Windows.Forms.Cursors]::SizeNS
$headerDivider.Add_Paint({
    param($sender,$e)
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(123,95,162),1)
    try {
        $topY = 0
        $bottomY = [Math]::Max(0,$sender.ClientSize.Height-1)
        $e.Graphics.DrawLine($pen,0,$topY,$sender.ClientSize.Width,$topY)
        $e.Graphics.DrawLine($pen,0,$bottomY,$sender.ClientSize.Width,$bottomY)
        # No layered WPF popup on unsupported virtual GPUs. A native GDI
        # gradient keeps the 7px draggable rail visible, never opaque white.
        if($OwnerGui -and $null -eq $gpuDivider -and
           $sender.ClientSize.Width -gt 2 -and $sender.ClientSize.Height -gt 3){
            $w=[int]$sender.ClientSize.Width
            $h=[int]$sender.ClientSize.Height
            $softRect=[Drawing.Rectangle]::new(0,1,$w,[Math]::Max(1,$h-2))
            $lineRect=[Drawing.Rectangle]::new(0,[Math]::Max(1,[int][Math]::Floor($h/2)-1),$w,2)
            $soft=[Drawing.Drawing2D.LinearGradientBrush]::new(
                $softRect,[Drawing.Color]::FromArgb(55,255,199,41),
                [Drawing.Color]::FromArgb(55,123,95,162),
                [Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $bright=[Drawing.Drawing2D.LinearGradientBrush]::new(
                $lineRect,[Drawing.Color]::FromArgb(255,255,199,41),
                [Drawing.Color]::FromArgb(255,123,95,162),
                [Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try {
                $e.Graphics.FillRectangle($soft,$softRect)
                $e.Graphics.FillRectangle($bright,$lineRect)
            }finally{$bright.Dispose();$soft.Dispose()}
        }
    } finally {
        $pen.Dispose()
    }
})

# GPU is decorative only. If shader bytecode or WPF shader initialization is
# unavailable, the normal painted divider remains fully functional. Initialization
# failures are recorded instead of being silently swallowed.
$gpuDivider = $null
$script:gpuDividerInitError = ''
if ($gpuDividerAvailable) {
    try {
        $gpuDivider = New-Object RdcGpuDividerHost -ArgumentList @(
            $causticShaderPath,
            $particleShaderPath,
            $causticDetailShaderPath,
            $particleCoreShaderPath
        )
        $gpuDivider.Dock = 'Fill'
        $gpuDivider.Margin = New-Object Windows.Forms.Padding(0)
        $gpuDivider.TabStop = $false
        $gpuDivider.Enabled = $false
        $headerDivider.Controls.Add($gpuDivider)
        $gpuDivider.BringToFront()
    } catch {
        $script:gpuDividerInitError = $_.Exception.ToString()
        # A partially attached ElementHost must not retain a white layered
        # popup after the safe in-form gradient has taken over painting.
        if($gpuDivider){
            try { $headerDivider.Controls.Remove($gpuDivider);$gpuDivider.Dispose() }catch{}
        }
        $gpuDivider = $null
        $headerDivider.Invalidate()
        if ($SelfTest) { throw }
        try {
            $gpuErrorPath = Join-Path $root 'rdc-relay-ui-errors.log'
            $gpuEntry =
                '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') +
                '] GPU divider initialization failed: ' +
                $script:gpuDividerInitError + $nl
            [IO.File]::AppendAllText(
                $gpuErrorPath,
                $gpuEntry,
                (New-Object Text.UTF8Encoding($false))
            )
        } catch {}
    }
}

# During splitter drag, show a lightweight bitmap preview of both panes.
# Real RichEdit controls keep stable geometry until MouseUp.
$dividerDragPreview = New-Object RdcDividerDragPreview
$dividerDragPreview.Visible = $false
$dividerDragPreview.Add_FadeOutCompleted({
    $dividerDragPreview.Visible = $false
    $dividerDragPreview.EndPreview()
})

$headerLog.Add_ScrollActivity({ $headerVScroll.Invalidate() })
$headerLog.Add_MouseWheel({
    try { [void]$headerLog.BeginInvoke([Windows.Forms.MethodInvoker]{ $headerVScroll.Invalidate() }) } catch {}
})
$headerLog.Add_KeyUp({
    try { [void]$headerLog.BeginInvoke([Windows.Forms.MethodInvoker]{ $headerVScroll.Invalidate() }) } catch {}
})

# The Owner banner is a fixed graphic in the header, independent of RichEdit.
# Keep the existing scroll target and the divider layout for ordinary text.
$ownerWordmark=$null
if($OwnerGui){
    $ownerWordmark=New-Object RdcOwnerWordmark
    $ownerWordmark.BackColor=$headerTextHost.BackColor
    $ownerWordmark.Dock='Fill'
    $ownerWordmark.Margin=[Windows.Forms.Padding]::new(0)
    $headerTextHost.RowCount=2
    $headerTextHost.RowStyles.Clear()
    [void]$headerTextHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,0))
    [void]$headerTextHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $headerTextHost.Controls.Add($ownerWordmark,0,0)
    $headerTextHost.Controls.Add($headerLog,0,1)
    $headerTextHost.Controls.Add($headerVScroll,1,1)
    $headerTextHost.Add_Layout({
        if($ownerWordmark -and -not $ownerWordmark.IsDisposed){
            $width=[Math]::Max(1,$headerTextHost.GetColumnWidths()[0])
            $height=$ownerWordmark.RowHeight($width,$headerTextHost.ClientSize.Height)
            if([Math]::Abs($headerTextHost.RowStyles[0].Height-$height) -gt 0.1){
                $headerTextHost.RowStyles[0].Height=$height
            }
            $ownerWordmark.Invalidate()
        }
    })
}else{
    $headerTextHost.Controls.Add($headerLog,0,0)
    $headerTextHost.Controls.Add($headerVScroll,1,0)
}
$headerHost.Controls.Add($headerTextHost,0,0)
$headerHost.Controls.Add($headerDivider,0,1)

$logHost = New-Object RdcBufferedPanel
$logHost.Dock = 'Fill'
$logHost.Margin = New-Object Windows.Forms.Padding(0)
$logHost.Padding = New-Object Windows.Forms.Padding(0)
$logHost.BackColor = [Drawing.Color]::FromArgb(18,20,23)

$log = New-Object RdcLogBox
$log.Dock = 'None'
$log.Margin = New-Object Windows.Forms.Padding(0)
$log.ReadOnly = $true
$log.TabStop = $false
$log.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$log.ForeColor = [Drawing.Color]::Gainsboro
$log.Font = New-Object Drawing.Font($script:ownerTextFontFamily,10)
$log.WordWrap = $false
$log.BorderStyle = 'None'
$log.ScrollBars = [Windows.Forms.RichTextBoxScrollBars]::None
$log.DetectUrls = $true
$log.Add_LinkClicked({ try { Start-Process $_.LinkText } catch {} })

$vScroll = New-Object RdcOverlayScrollBar
$vScroll.Target = $log
$vScroll.Vertical = $true
# Compact lower panel: full-length orange status rail, not an interactive
# navigation scrollbar. The object remains for all existing preview effects.
if($OwnerGui){$vScroll.DecorativeFullTrack = $true}
$vScroll.Dock = 'None'
$vScroll.Margin = New-Object Windows.Forms.Padding(0)

$hScroll = New-Object RdcOverlayScrollBar
$hScroll.Target = $log
$hScroll.Vertical = $false
$hScroll.Dock = 'None'
$hScroll.Margin = New-Object Windows.Forms.Padding(0)

$scrollCorner = New-Object RdcScrollCorner
$scrollCorner.Dock = 'None'
$scrollCorner.Margin = New-Object Windows.Forms.Padding(0)

$log.Add_ScrollActivity({
    $vScroll.Invalidate()
    $hScroll.Invalidate()
})
$hScroll.Add_MouseUp({
    try { $script:userHorizontalX = [Math]::Max(0,$log.GetViewPosition().X) } catch {}
})
$vScroll.Add_MouseUp({
    try { $script:smartFollow = $vScroll.IsAtEnd } catch { $script:smartFollow = $false }
})
$log.Add_MouseWheel({
    try {
        [void]$log.BeginInvoke([Windows.Forms.MethodInvoker]{
            try { $script:smartFollow = $vScroll.IsAtEnd } catch { $script:smartFollow = $false }
        })
    } catch {}
})
$log.Add_KeyUp({
    try {
        [void]$log.BeginInvoke([Windows.Forms.MethodInvoker]{
            try { $script:smartFollow = $vScroll.IsAtEnd } catch { $script:smartFollow = $false }
        })
    } catch {}
})

$script:logRedrawFrozen = $false
function Layout-LogScrollbars {
    $w = [Math]::Max(17,$logHost.ClientSize.Width)
    $h = [Math]::Max(17,$logHost.ClientSize.Height)
    $contentW = [Math]::Max(0,$w - 17)
    $contentH = [Math]::Max(0,$h - 17)

    $logHost.SuspendLayout()
    try {
        $log.SetBounds(0,0,$contentW,$contentH)
        $vScroll.SetBounds($contentW,0,17,$contentH)
        $hScroll.SetBounds(0,$contentH,$contentW,17)
        $scrollCorner.SetBounds($contentW,$contentH,17,17)
    } finally {
        $logHost.ResumeLayout($false)
    }

    $vScroll.Invalidate()
    $hScroll.Invalidate()
    $scrollCorner.Invalidate()
}

function Start-LogResizeInteraction {
    if (-not $script:logRedrawFrozen) {
        try {
            $log.BeginUpdate()
            $script:logRedrawFrozen = $true
        } catch {}
    }
}

function Stop-LogResizeInteraction {
    if ($script:logRedrawFrozen) {
        try { $log.EndUpdate() } catch {}
        $script:logRedrawFrozen = $false
    }
    $logHost.Invalidate($true)
    try { $log.RefreshViewport() } catch {}
}
function Get-EffectivePaneMinHeight {
    $available=[Math]::Max(1,$contentHost.ClientSize.Height)
    # Keep the six-line Owner logo (or legacy 125px header) visible.
    # On constrained displays allow both panes to degrade symmetrically.
    $headerReserve=[Math]::Min($headerPaneMinHeightPreferred,
        [Math]::Max(48,[int][Math]::Floor($available/2)))
    return [Math]::Min($activityPaneMinHeightPreferred,
        [Math]::Max(48,$available-$headerReserve))
}
function Get-ClampedActivityPaneHeight([double]$requestedHeight) {
    $paneMinHeight=Get-EffectivePaneMinHeight
    $headerMinHeight=[Math]::Min($headerPaneMinHeightPreferred,
        [Math]::Max(48,$contentHost.ClientSize.Height-$paneMinHeight))
    $maxHeight=[Math]::Max($paneMinHeight,
        ($contentHost.ClientSize.Height-$headerMinHeight))
    return [Math]::Max($paneMinHeight,[Math]::Min($maxHeight,$requestedHeight))
}
function Set-ActivityPaneHeight([double]$requestedHeight) {
    $nextHeight = Get-ClampedActivityPaneHeight $requestedHeight
    if ([Math]::Abs($contentHost.RowStyles[1].Height - $nextHeight) -gt 0.1) {
        $contentHost.SuspendLayout()
        try {
            $contentHost.RowStyles[1].Height = $nextHeight
        } finally {
            $contentHost.ResumeLayout($true)
        }
        $headerVScroll.Invalidate()
    }
}
function Get-DividerPreviewY([double]$paneHeight) {
    $clamped = Get-ClampedActivityPaneHeight $paneHeight
    return $contentHost.ClientSize.Height - [int][Math]::Round($clamped) - 7
}
function Position-DividerDragPreview([double]$paneHeight) {
    $origin = $form.PointToClient($contentHost.PointToScreen((New-Object Drawing.Point(0,0))))
    $dividerDragPreview.SetBounds(
        $origin.X,
        $origin.Y,
        $contentHost.ClientSize.Width,
        $contentHost.ClientSize.Height
    )
    $dividerDragPreview.UpdateDivider((Get-DividerPreviewY $paneHeight))
}
$logHost.Add_Resize({
    Layout-LogScrollbars
    if($script:ownerCompactJournal){Refresh-Rc1JournalOnResize}
})
$contentHost.Add_Resize({
    Set-ActivityPaneHeight $contentHost.RowStyles[1].Height
})
$scrollCorner.Add_MouseDown({
    $script:uiInteracting = $true
    Start-LogResizeInteraction
})
$scrollCorner.Add_DragDelta({
    $delta = [int]$scrollCorner.VerticalDelta
    if ($delta -ne 0) {
        Set-ActivityPaneHeight ($contentHost.RowStyles[1].Height - $delta)
    }
})
$scrollCorner.Add_MouseUp({
    $script:uiInteracting = $false
    Layout-LogScrollbars
    Stop-LogResizeInteraction
    if($script:ownerCompactJournal){Refresh-Rc1JournalOnResize}
})
$scrollCorner.Add_MouseCaptureChanged({
    if (-not $scrollCorner.Capture) {
        $script:uiInteracting = $false
        Layout-LogScrollbars
        Stop-LogResizeInteraction
        if($script:ownerCompactJournal){Refresh-Rc1JournalOnResize}
    }
})

$script:dividerDragging = $false
$script:dividerStartScreenY = 0
$script:dividerStartPaneHeight = 0.0
$script:dividerPendingHeight = 0.0

function Complete-DividerDrag {
    if (-not $script:dividerDragging) { return }

    $script:dividerDragging = $false
    $script:uiInteracting = $false

    # Keep the preview fully covering the panes while the real controls commit
    # their final layout underneath it.
    Position-DividerDragPreview $script:dividerPendingHeight
    Start-LogResizeInteraction
    try {
        Set-ActivityPaneHeight $script:dividerPendingHeight
        Layout-LogScrollbars
    } finally {
        Stop-LogResizeInteraction
    }
    if($script:ownerCompactJournal){Refresh-Rc1JournalOnResize}

    try { $gpuDivider.SetInteractiveMove($false) } catch {}

    $headerVScroll.Invalidate()
    $vScroll.Invalidate()
    $contentHost.Invalidate($true)
    $contentHost.Update()

    # DrawToBitmap works even while the preview covers the controls, so the
    # fade can morph the temporary ruler into the freshly laid out real bars.
    $dividerDragPreview.CaptureFinalScrollbars($headerVScroll,$vScroll)

    # Give the underlying controls roughly three frames to settle, then fade
    # the temporary ruler out over a short, non-blocking transition.
    $dividerDragPreview.FadeOut(50,180)
}

$headerDivider.Add_MouseDown({
    param($sender,$e)
    if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) {
        $script:dividerDragging = $true
        $script:dividerStartScreenY = [Windows.Forms.Control]::MousePosition.Y
        $script:dividerStartPaneHeight = [double]$contentHost.RowStyles[1].Height
        $script:dividerPendingHeight = $script:dividerStartPaneHeight
        $script:uiInteracting = $true

        try { $gpuDivider.SetInteractiveMove($true) } catch {}

        Position-DividerDragPreview $script:dividerPendingHeight
        $dividerDragPreview.BeginPreview(
            $headerTextHost,
            $log,
            $headerVScroll,
            $vScroll,
            $hScroll,
            $scrollCorner,
            (Get-DividerPreviewY $script:dividerPendingHeight)
        )

        # Keep mouse capture on the real divider. The preview is disabled, so
        # it is purely visual and never participates in input/capture.
        $headerDivider.Capture = $true
        $dividerDragPreview.Visible = $true
        $dividerDragPreview.BringToFront()
        $dividerDragPreview.FadeIn(120)
    }
})
$headerDivider.Add_MouseMove({
    if ($script:dividerDragging) {
        $nowY = [Windows.Forms.Control]::MousePosition.Y
        $delta = $nowY - $script:dividerStartScreenY
        $script:dividerPendingHeight =
            Get-ClampedActivityPaneHeight ($script:dividerStartPaneHeight - $delta)

        # Only the bitmap preview follows the pointer. RichEdit and both
        # custom scrollbars keep stable geometry until the drag is committed.
        Position-DividerDragPreview $script:dividerPendingHeight
    }
})
$headerDivider.Add_MouseUp({
    if ($script:dividerDragging) {
        $nowY = [Windows.Forms.Control]::MousePosition.Y
        $delta = $nowY - $script:dividerStartScreenY
        $script:dividerPendingHeight =
            Get-ClampedActivityPaneHeight ($script:dividerStartPaneHeight - $delta)

        $headerDivider.Capture = $false
        Complete-DividerDrag
    }
})
$headerDivider.Add_MouseCaptureChanged({
    if (-not $headerDivider.Capture -and $script:dividerDragging) {
        Complete-DividerDrag
    }
})

[void]$logHost.Controls.Add($log)
[void]$logHost.Controls.Add($vScroll)
[void]$logHost.Controls.Add($hScroll)
[void]$logHost.Controls.Add($scrollCorner)
Layout-LogScrollbars

$contentHost.Controls.Add($headerHost,0,0)
$contentHost.Controls.Add($logHost,0,1)

$form.Controls.Add($contentHost)
$form.Controls.Add($bottom)
$form.Controls.Add($top)
$form.Controls.Add($dividerDragPreview)
$form.PerformLayout()
Set-ActivityPaneHeight (Get-EffectivePaneMinHeight)
$dividerDragPreview.BringToFront()

function Get-TabStopControls {
    param([Windows.Forms.Control]$Root)
    $result = @()
    foreach ($child in @($Root.Controls)) {
        if ($child.TabStop) { $result += $child }
        $result += @(Get-TabStopControls $child)
    }
    return $result
}

function Set-PrimaryActionTabTraversal {
    param([Windows.Forms.Control]$Root)

    function Disable-TabStopRecursive {
        param([Windows.Forms.Control]$Control)
        foreach ($child in @($Control.Controls)) {
            $child.TabStop = $false
            Disable-TabStopRecursive $child
        }
    }

    Disable-TabStopRecursive $Root

    $finish.TabStop = $true
    $accountButton.TabStop = $true
    $helpButton.TabStop = $true

    $finish.TabIndex = 0
    $accountButton.TabIndex = 1
    $helpButton.TabIndex = 2
}

Set-PrimaryActionTabTraversal $form
$script:proc = $null
$script:reader = $null
$script:bannerStyled = $false
$script:startTime = $null
$script:stopping = $false
$script:manualStopRequested = $false
$script:exitHandled = $false
$script:accountEmail = $null
$script:lastFrameDark = $null
$script:lastControlDark = $null
$script:uiInteracting = $false
$script:userHorizontalX = 0
$script:smartFollow = $true
$script:freezeViewport = $false
$script:frozenViewX = 0
$script:frozenViewY = 0
$script:lastRenderedHeader = $null
$script:lastRenderedText = $null
$script:startupBlock = ''
$script:eventBlocks = New-Object System.Collections.ArrayList
$script:currentEvent = ''
$script:currentEventTruncated = $false
$script:remoteLineBuffer = ''
$script:seenFirstRemoteEvent = $false
$script:tailNeedsMarker = $false
$script:startupComplete = $false
$script:activeToolCalls = 0
$script:lastToolCompletedAt = $null
$script:lastToolMarkerAt = $null
$activityMinHoldSeconds = 10.0
$activityMaxHoldSeconds = 30.0
$activityInterruptedTimeoutSeconds = 60.0
$remoteConnectGraceSeconds = 30.0
$remoteReconnectDelaysSeconds = @(2.0,5.0,10.0)
$script:activityHoldUntil = $null
$script:activityGapEwmaSeconds = 3.0
$script:activityHoldSeconds = $activityMinHoldSeconds
$script:remoteReady = $false
$script:remoteFaultLatched = $false
$script:remoteFaultKind = ''
$script:remoteFaultReason = ''
$script:remoteFaultAt = $null
$script:remoteConnectDeadline = $null
$script:remoteInteractiveAuth = $false
$script:autoReconnectAttempt = 0
$script:autoReconnectAt = $null
$script:npxMissingPackageRepairAttempted = $false
$script:supervisorRestarting = $false
$script:preserveFaultOnStop = $false
$uiStartupMaxChars = 30000
$uiEventMaxChars = 8000
$uiLogInitialTailBytes = 524288
$uiLogCatchupThresholdBytes = 524288
$uiLogCatchupTailBytes = 524288
$uiDivider = ('╶' + ('┄' * 92) + '╴')
$nl = [Environment]::NewLine
function Hide-LegacyRemoteTerminal {
    try {
        Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -eq 'RDC Relay'
        } | ForEach-Object {
            [void][RdcNativeWindow]::ShowWindow($_.MainWindowHandle,0)
        }
    } catch {}
}
function Get-SystemDarkMode {
    try {
        $theme = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        return ([int]$theme.AppsUseLightTheme -eq 0)
    } catch {
        return $false
    }
}
function Apply-SystemFrameTheme {
    try {
        $dark = Get-SystemDarkMode
        if ($script:lastFrameDark -ne $dark -and $form.Handle -ne [IntPtr]::Zero) {
            [int]$value = if ($dark) { 1 } else { 0 }
            [void][RdcNativeWindow]::DwmSetWindowAttribute(
                $form.Handle,
                20,
                [ref]$value,
                4
            )
            $script:lastFrameDark = $dark
        }
    } catch {}
}
function Set-State([string]$name,[string]$message,[Drawing.Color]$color) {
    $statusDot.IndicatorColor = $color
    $title.Text = 'RDC Relay  —  ' + $name
    $statusDetail.Text = $message
}
function Set-FinishButtonMode([bool]$running) {
    if ($running) {
        $finish.Text = 'Остановить'
        $finish.Glyph = [RdcButtonGlyph]::Stop
    } else {
        $finish.Text = 'Запустить'
        $finish.Glyph = [RdcButtonGlyph]::Play
    }
    $finish.Enabled = -not ($script:remoteOperation -or $script:initializing)
}
function Set-RuntimeDisplay([string]$left,[string]$right = '',[bool]$showSeparator = $false) {
    $runtimeLeft.Text = $left
    $runtimeRight.Text = $right
    $runtimeRight.Visible = -not [string]::IsNullOrWhiteSpace($right)
    # Owner uses the same separator for quota | uptime as legacy uses for
    # PID | runtime. Hide it only when there is no right-hand value.
    $runtimeSep.Visible = ($showSeparator -and $runtimeRight.Visible)
}
function Set-AccountDisplay([string]$email) {
    if ([string]::IsNullOrWhiteSpace($email)) {
        $script:accountEmail = $null
        $accountInfo.Text = if($OwnerGui -and (Get-Command Get-RdcOwnerUiText -CommandType Function -ErrorAction SilentlyContinue)){
            Get-RdcOwnerUiText 'gui.account.unknown' 'не определён'
        }else{'не определён'}
    } else {
        $script:accountEmail = $email.Trim()
        $accountInfo.Text = $script:accountEmail
    }
}
function Update-AccountFromLog([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $matches = [Regex]::Matches($text,'(?im)^\s*-\s*User:\s*([^\s]+@[^\s]+)\s*$')
    if ($matches.Count -gt 0) {
        $email = $matches[$matches.Count - 1].Groups[1].Value
        if ($email -and $email -ne $script:accountEmail) { Set-AccountDisplay $email }
    }
}
function Convert-ToCleanLogText([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    $esc = [Regex]::Escape([string][char]27)
    $clean = $text -replace ($esc + '\[[0-?]*[ -/]*[@-~]'),''
    $clean = $clean -replace "`r(?!`n)","`r`n"
    return $clean
}
function Limit-UiEvent([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $clean = $text.TrimEnd()
    if ($clean.Length -le $uiEventMaxChars) { return $clean }
    $note = $nl + '… [полный вывод — в журнале]'
    $headLen = [Math]::Max(0,$uiEventMaxChars - $note.Length)
    return $clean.Substring(0,$headLen) + $note
}
function Set-DividerWorkState([bool]$working) {
    if ($gpuDivider -and -not $gpuDivider.IsDisposed) {
        $gpuDivider.SetActivity($working)
    }
}
function Set-DividerStartupState([bool]$startup) {
    if ($gpuDivider -and -not $gpuDivider.IsDisposed) {
        $gpuDivider.SetStartup($startup)
    }
}
function Set-DividerStoppedState([bool]$stopped) {
    if ($gpuDivider -and -not $gpuDivider.IsDisposed) {
        $gpuDivider.SetStopped($stopped)
    }
}
function Set-DividerFaultState([bool]$fault) {
    if ($gpuDivider -and -not $gpuDivider.IsDisposed) {
        $gpuDivider.SetFault($fault)
    }
}
function Start-DividerRecoveryFlash {
    if ($gpuDivider -and -not $gpuDivider.IsDisposed) {
        $gpuDivider.BeginRecoveryFlash()
    }
}
function Schedule-AutoReconnect([string]$reason) {
    if ($SelfTest -or $Preview -or $script:supervisorRestarting) { return }
    if ($script:autoReconnectAt) { return }

    $maxAttempts = $remoteReconnectDelaysSeconds.Count
    if ($script:autoReconnectAttempt -ge $maxAttempts) {
        $script:remoteFaultReason =
            'Автовосстановление не удалось после ' + $maxAttempts +
            ' попыток. Используйте «Переподключить».'
        return
    }

    $delay = [double]$remoteReconnectDelaysSeconds[$script:autoReconnectAttempt]
    $script:autoReconnectAt = (Get-Date).AddSeconds($delay)
    Add-Log (
        '[' + (Get-Date -Format 'HH:mm:ss') +
        '] Автовосстановление: повтор через ' +
        $delay.ToString('0.#',[Globalization.CultureInfo]::InvariantCulture) +
        ' с. Причина: ' + $reason + $nl
    )
}
function Set-RemoteFault(
    [string]$kind,
    [string]$reason,
    [bool]$scheduleRestart = $false
) {
    if ($script:manualStopRequested -or $script:stopping) { return }
    $changed =
        (-not $script:remoteFaultLatched) -or
        ($script:remoteFaultKind -ne $kind) -or
        ($script:remoteFaultReason -ne $reason)

    $script:remoteFaultLatched = $true
    $script:remoteFaultKind = $kind
    $script:remoteFaultReason = $reason
    if (-not $script:remoteFaultAt) { $script:remoteFaultAt = Get-Date }

    if ($kind -ne 'tool-timeout') {
        $script:remoteReady = $false
    }

    Set-DividerFaultState $true

    if ($changed) {
        Add-Log (
            '[' + (Get-Date -Format 'HH:mm:ss') +
            '] ПРОБЛЕМА: ' + $reason + $nl
        )
    }

    if ($scheduleRestart) {
        Schedule-AutoReconnect $reason
    }
}
function Clear-RemoteFault {
    $script:remoteFaultLatched = $false
    $script:remoteFaultKind = ''
    $script:remoteFaultReason = ''
    $script:remoteFaultAt = $null
    $script:autoReconnectAt = $null
    Set-DividerFaultState $false
}
function Mark-RemoteReady([string]$marker = '') {
    if ($script:manualStopRequested -or $script:stopping) { return }
    $wasReady = $script:remoteReady
    $wasFault = $script:remoteFaultLatched
    $preserveToolFault =
        $script:remoteFaultLatched -and
        $script:remoteFaultKind -in @('tool-failed','tool-timeout')

    $script:remoteReady = $true
    $script:remoteInteractiveAuth = $false
    $script:remoteConnectDeadline = $null
    $script:npxMissingPackageRepairAttempted = $false
    $script:autoReconnectAttempt = 0
    $script:autoReconnectAt = $null

    # Presence/realtime readiness proves transport health, not successful tool
    # execution. Keep an explicit tool failure latched red until a later tool
    # call succeeds; transport/session faults may clear on verified readiness.
    if (-not $preserveToolFault) {
        Clear-RemoteFault
    }

    # Green is confirmation of a real Remote MCP ready transition, not merely
    # proof that cmd/npx is alive. Do not flash green over a still-latched tool
    # failure, and do not retrigger on duplicate ready markers.
    if (-not $wasReady -and -not $preserveToolFault) {
        Start-DividerRecoveryFlash
        Add-Log (
            '[' + (Get-Date -Format 'HH:mm:ss') +
            $(if ($wasFault) { '] Remote MCP восстановлен.' } else { '] Remote MCP подключен и готов.' }) +
            $nl
        )
    }
}
# PROG-004: pure classification of already-decoded, complete Remote log lines.
# The result describes *observations only*. The caller retains ordering and all
# state, logging, visual and retry effects. Substring matching, priority and
# unexpected payload matches are deliberately preserved for equivalence.
function Get-RemoteLineClassification([string]$line,[string]$faultKind = '') {
    $receivedPrefix = '🔧 '
    $completedPrefix = '✅ '
    $failedPrefix = '❌ '
    $toolKind = ''
    if (
        $line.StartsWith($receivedPrefix,[StringComparison]::Ordinal) -and
        $line.IndexOf('Received tool call ',[StringComparison]::Ordinal) -eq $receivedPrefix.Length
    ) {
        $toolKind = 'received'
    }
    elseif (
        $line.StartsWith($completedPrefix,[StringComparison]::Ordinal) -and
        $line.IndexOf('Tool call ',[StringComparison]::Ordinal) -eq $completedPrefix.Length -and
        $line.IndexOf(' completed:',[StringComparison]::Ordinal) -gt $completedPrefix.Length
    ) {
        $toolKind = 'completed'
    }
    elseif (
        $line.StartsWith($failedPrefix,[StringComparison]::Ordinal) -and
        $line.IndexOf('Tool call ',[StringComparison]::Ordinal) -eq $failedPrefix.Length -and
        $line.IndexOf(' failed:',[StringComparison]::Ordinal) -gt $failedPrefix.Length
    ) {
        $toolKind = 'failed'
    }

    $healthProbe = $line.TrimStart()
    $isSerializedToolPayload =
        $healthProbe.StartsWith('{',[StringComparison]::Ordinal) -or
        $healthProbe.StartsWith('[',[StringComparison]::Ordinal)

    # Match the original Update-RemoteHealthFromLine precedence exactly.
    $healthKind = ''
    if (-not [string]::IsNullOrWhiteSpace($line)) {
        if (
            $line.IndexOf('Desktop Commander Remote is connected',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Presence tracked (device ',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            (
                $faultKind -eq 'local-mcp' -and
                $line.IndexOf('Local Desktop Commander MCP restarted; device is online again',[StringComparison]::OrdinalIgnoreCase) -ge 0
            )
        ) {
            $healthKind = 'ready'
        }
        elseif (
            $line.IndexOf('Authenticating with Remote MCP server',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('waiting for authentication',[StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            $healthKind = 'auth'
        }
        elseif (
            $line.IndexOf('Remote session expired and could not be renewed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Restart the terminal running Desktop Commander to reconnect',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('This device is now offline for remote calls',[StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            $healthKind = 'session-lost'
        }
        elseif ($line.IndexOf('Device startup failed:',[StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $healthKind = 'startup-failed'
        }
        elseif (
            $line.IndexOf('Local Desktop Commander MCP went away (',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Could not restart local Desktop Commander MCP:',[StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            $healthKind = 'local-mcp'
        }
        elseif (
            $line.IndexOf('Channel error:',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Channel closed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Device marked as offline',[StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            $healthKind = 'transport-offline'
        }
        elseif (
            $line.IndexOf('Device registered, but NOT reachable',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Realtime channel is not open',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Channel subscription timed out',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Presence track remained unavailable',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Presence published but the device row could not be updated',[StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            $healthKind = 'remote-unreachable'
        }
    }
    return [pscustomobject]@{
        ToolKind = $toolKind
        HealthKind = $healthKind
        IsSerializedToolPayload = [bool]$isSerializedToolPayload
    }
}
function Update-RemoteHealthFromLine([string]$line) {
    if ($script:manualStopRequested -or $script:stopping) { return }
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    $kind = (Get-RemoteLineClassification $line $script:remoteFaultKind).HealthKind
    if ($kind -eq 'ready') {
        Mark-RemoteReady $line
        return
    }
    if ($kind -eq 'auth') {
        $script:remoteInteractiveAuth = $true
        $script:remoteConnectDeadline = $null
        return
    }
    if ($kind -eq 'session-lost') {
        Set-RemoteFault 'session-lost' 'Remote MCP потерял сессию и требует перезапуска.' $true
        return
    }
    if ($kind -eq 'startup-failed') {
        Set-RemoteFault 'startup-failed' 'Desktop Commander не смог завершить запуск Remote MCP.' $true
        return
    }
    if ($kind -eq 'local-mcp') {
        Set-RemoteFault 'local-mcp' 'Локальный Desktop Commander MCP потерял соединение; ожидаю встроенный перезапуск executor.' $false
        $script:remoteConnectDeadline = $null
        return
    }
    if ($kind -eq 'transport-offline') {
        Set-RemoteFault 'transport-offline' 'Сетевой канал Remote MCP потерян; ожидаю встроенное восстановление.' $false
        $script:remoteConnectDeadline = $null
        return
    }
    if ($kind -eq 'remote-unreachable') {
        Set-RemoteFault 'remote-unreachable' 'Remote MCP временно недоступен; ожидаю встроенное восстановление.' $false
        $script:remoteConnectDeadline = $null
        return
    }
}
function Refresh-DividerActivitySession {
    $now = Get-Date

    if ($script:activeToolCalls -gt 0 -and $script:lastToolMarkerAt) {
        $silentSeconds = ($now - $script:lastToolMarkerAt).TotalSeconds

        if ($silentSeconds -gt $activityInterruptedTimeoutSeconds) {
            # Silence is not a health failure. Completion markers may be delayed
            # or lost, and a genuinely long tool call can be healthy. Retire the
            # stale activity session back to idle without touching Remote health.
            $script:activeToolCalls = 0
            $script:lastToolMarkerAt = $null
            $script:activityHoldUntil = $null
        }
    }

    if ($script:activeToolCalls -gt 0) {
        Set-DividerWorkState $true
        return
    }

    if ($script:activityHoldUntil -and $now -lt $script:activityHoldUntil) {
        Set-DividerWorkState $true
        return
    }

    $script:activityHoldUntil = $null
    Set-DividerWorkState $false
}
function Reset-CompactLogSession {
    $script:activeToolCalls = 0
    $script:lastToolCompletedAt = $null
    $script:lastToolMarkerAt = $null
    $script:activityHoldUntil = $null
    $script:activityGapEwmaSeconds = 3.0
    $script:activityHoldSeconds = $activityMinHoldSeconds
    Set-DividerWorkState $false
    $script:smartFollow = $true
    $script:freezeViewport = $false
    $script:lastRenderedHeader = $null
    $script:lastRenderedText = $null
    $script:startupBlock = ''
    $script:eventBlocks.Clear()
    $script:currentEvent = ''
    $script:currentEventTruncated = $false
    $script:remoteLineBuffer = ''
    $script:seenFirstRemoteEvent = $false
    $script:tailNeedsMarker = $false
    $script:startupComplete = $false
    $script:bannerStyled = $false
    Render-CompactLog
}
function Add-CompletedEvent([string]$text) {
    $item = Limit-UiEvent $text
    if ([string]::IsNullOrWhiteSpace($item)) { return }
    [void]$script:eventBlocks.Add($item)
    # Owner keeps bounded history independently from visible rows; resizing
    # can reveal older events without querying Host or discarding newer data.
    $retained=if($OwnerGui){64}else{6}
    while ($script:eventBlocks.Count -gt $retained) { $script:eventBlocks.RemoveAt(0) }
}
function Commit-CurrentEvent {
    if (-not [string]::IsNullOrWhiteSpace($script:currentEvent)) {
        Add-CompletedEvent $script:currentEvent
    }
    $script:currentEvent = ''
    $script:currentEventTruncated = $false
}
function Append-CurrentEvent([string]$text) {
    if ([string]::IsNullOrEmpty($text) -or $script:currentEventTruncated) { return }
    $note = $nl + '… [полный вывод — в журнале]'
    $remaining = $uiEventMaxChars - $script:currentEvent.Length
    if ($remaining -le $note.Length) {
        if (-not $script:currentEvent.EndsWith($note)) { $script:currentEvent += $note }
        $script:currentEventTruncated = $true
        return
    }
    if ($text.Length -le $remaining) {
        $script:currentEvent += $text
        return
    }
    $take = [Math]::Max(0,$remaining - $note.Length)
    if ($take -gt 0) { $script:currentEvent += $text.Substring(0,$take) }
    $script:currentEvent += $note
    $script:currentEventTruncated = $true
}
function Test-StartupBoundaryLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $false }
    return (
        $line.IndexOf(
            'Run these in a new Terminal, or after disconnecting.',
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0 -or
        $line.IndexOf(
            'Retrying in the background; commands start working once you see',
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0
    )
}
function Set-StartupFromProbe([string]$text) {
    $clean = Convert-ToCleanLogText $text
    if ([string]::IsNullOrWhiteSpace($clean)) { return }
    Update-AccountFromLog $clean

    $normalized = $clean.Replace("`r`n","`n").Replace("`r","`n")
    $lines = $normalized -split "`n",-1
    $headerLines = New-Object System.Collections.Generic.List[string]
    $boundaryFound = $false

    foreach ($line in $lines) {
        if ($line.IndexOf('Received tool call ',[StringComparison]::Ordinal) -ge 0) {
            $boundaryFound = $true
            break
        }

        [void]$headerLines.Add($line)
        if (Test-StartupBoundaryLine $line) {
            $boundaryFound = $true
            break
        }
    }

    $header = [string]::Join($nl,$headerLines)
    if ($header.Length -gt $uiStartupMaxChars) { $header = $header.Substring(0,$uiStartupMaxChars) }
    $script:startupBlock = $header.TrimEnd()
    if ($boundaryFound) { $script:startupComplete = $true }
}
function Color-LogToken([RdcLogBox]$target,[string]$token,[Drawing.Color]$color) {
    if (-not $target -or [string]::IsNullOrEmpty($token) -or $target.TextLength -eq 0) { return }
    $all = $target.Text
    $pos = 0
    while (($pos = $all.IndexOf($token,$pos,[StringComparison]::Ordinal)) -ge 0) {
        $target.Select($pos,$token.Length)
        $target.SelectionColor = $color
        $pos += $token.Length
    }
}
function Apply-OwnerEmojiFont([Windows.Forms.RichTextBox]$target) {
    # In WinForms RichEdit the font for every character can be chosen without
    # changing its value, color or the fixed-width surrounding paragraphs.
    # Do not format U+2500..U+259F line art: that keeps the six-row logo intact.
    if(-not $script:ownerEmojiEnabled -or -not $target -or $target.TextLength -eq 0){return}
    $all=$target.Text
    $emojiRuns=[Regex]::Matches($all,'(?:[\uD83C-\uDBFF][\uDC00-\uDFFF]|[\u2300-\u23FF\u2600-\u27BF])\uFE0F?')
    if($emojiRuns.Count -eq 0){return}
    $font=New-Object Drawing.Font($script:ownerEmojiFontFamily,$target.Font.Size)
    try {
        foreach($run in $emojiRuns){
            $target.Select($run.Index,$run.Length)
            $target.SelectionFont=$font
        }
    } finally { $font.Dispose() }
}
function Color-LogRegex([RdcLogBox]$target,[string]$pattern,[Drawing.Color]$color,[int]$limit=-1,[int]$group=0) {
    if (-not $target -or [string]::IsNullOrEmpty($pattern) -or $target.TextLength -eq 0) { return }
    $all = $target.Text
    $options = [Text.RegularExpressions.RegexOptions]::Multiline -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase
    foreach ($m in [Regex]::Matches($all,$pattern,$options)) {
        if ($group -ge $m.Groups.Count) { continue }
        $g = $m.Groups[$group]
        if (-not $g.Success -or $g.Length -le 0) { continue }
        if ($limit -ge 0 -and ($g.Index + $g.Length) -gt $limit) { continue }
        $target.Select($g.Index,$g.Length)
        $target.SelectionColor = $color
    }
}
function Color-HeaderSemantics([RdcLogBox]$target,[int]$headerLimit) {
    if (-not $target -or $headerLimit -le 0) { return }
    Color-LogRegex $target '\bOnline\b' $stateOnline $headerLimit 0
    Color-LogRegex $target '\bOffline\b' $stateOffline $headerLimit 0
    Color-LogRegex $target '^[\s│]*(?:Help:|Log out:)\s+(.+)$' $commandAccent $headerLimit 1
    Color-LogRegex $target '^\s*-\s*User:\s*(.+)$' $headerValue $headerLimit 1
    Color-LogRegex $target '^\s*-\s*Device ID:\s*(.+)$' $headerValue $headerLimit 1
    Color-LogRegex $target '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b' $headerValue $headerLimit 0
    Color-LogRegex $target '^\s*-\s*Device Name:\s*(.+)$' $headerValue $headerLimit 1
    Color-LogRegex $target '^\s*Device:\s*(.+)$' $headerValue $headerLimit 1
}
function Get-Rc1JournalVisibleRowCapacity {
    if(-not $OwnerGui -or -not $script:ownerCompactJournal){return 6}
    if(-not $log -or $log.IsDisposed){return 6}
    $linePitch=[Math]::Max(1,[int]$script:ownerJournalLinePitch)
    if($linePitch -le 1){return 6}
    # The RichEdit viewport excludes the separate 17px horizontal scrollbar.
    # Reserve one blank line above the first entry and one below the last.
    $wholeLines=[int][Math]::Floor([Math]::Max(0,$log.ClientSize.Height)/$linePitch)
    return [Math]::Max(1,[Math]::Min(64,$wholeLines-2))
}
function Refresh-Rc1JournalOnResize {
    if(-not $OwnerGui -or -not $script:ownerCompactJournal -or
       $script:uiInteracting -or $script:logRedrawFrozen -or
       -not $script:eventBlocks){return}
    $capacity=Get-Rc1JournalVisibleRowCapacity
    if($capacity -ne $script:ownerLastJournalCapacity){Render-CompactLog}
}
# Insert exactly two blank characters before each of the original six
# Unicode-art lines in the Owner render copy only. Host snapshots and source
# logs retain their exact bytes, including line endings. Missing/partial
# artwork fails closed (no changes). Reverse insertion preserves offsets.
function Add-Rc1OwnerBannerLeadingColumn([string]$text) {
    if(-not $OwnerGui -or [string]::IsNullOrEmpty($text)){return $text}
    $marker=$text.IndexOf('Remote Connection',[StringComparison]::OrdinalIgnoreCase)
    if($marker -lt 0){return $text}
    $markerLineStart=$text.LastIndexOf("`n",$marker)+1
    if($markerLineStart -le 0){return $text}
    $before=$text.Substring(0,$markerLineStart)
    $rows=$before.Split([char]10)
    $positions=New-Object 'System.Collections.Generic.List[int]'
    $starts=New-Object 'System.Collections.Generic.List[int]'
    $offset=0
    foreach($row in $rows){
        $starts.Add($offset)
        $offset += $row.Length+1
    }
    for($i=$rows.Length-1;$i -ge 0 -and $positions.Count -lt 6;$i--){
        $row=$rows[$i].TrimEnd([char]13)
        if([string]::IsNullOrWhiteSpace($row)){continue}
        if($row -cnotmatch '\A[ \t\u00A0\u2500-\u259F/\\_|.]+\z' -or
           $row -cnotmatch '[\u2500-\u259F]'){return $text}
        $positions.Add($starts[$i])
    }
    if($positions.Count -ne 6){return $text}
    $result=New-Object Text.StringBuilder($text)
    foreach($position in $positions){[void]$result.Insert($position,'  ')}
    return $result.ToString()
}
# Suppress only the initial pseudographic rows in the render copy.
# The original Host header and all raw captured bytes remain untouched.
function Remove-Rc1OwnerWordmarkArt([string]$text) {
    if([string]::IsNullOrEmpty($text)){return $text}
    $rows=[regex]::Split($text,'\r\n|\n|\r')
    $first=0
    while($first -lt $rows.Length -and [string]::IsNullOrWhiteSpace($rows[$first])){$first++}
    $end=$first
    while($end -lt $rows.Length -and $end-$first -lt 7){
        $row=$rows[$end]
        if($row -cnotmatch '\A[ \t\u00A0\u2500-\u259F/\\_|.]+\z' -or
           $row -cnotmatch '[\u2500-\u259F]'){break}
        $end++
    }
    if($end -eq $first){return $text}
    while($end -lt $rows.Length -and [string]::IsNullOrWhiteSpace($rows[$end])){$end++}
    if($end -ge $rows.Length){return ''}
    return [string]::Join([Environment]::NewLine,$rows[$end..($rows.Length-1)])
}
function Render-CompactLog {
    if (-not $log -or $log.IsDisposed -or -not $headerLog -or $headerLog.IsDisposed) { return }

    $headerDisplay = if ([string]::IsNullOrWhiteSpace($script:startupBlock)) { '' } else { $script:startupBlock.TrimEnd() }
    # Present desktop-GUI instructions, not upstream terminal-only shortcuts.
    # Transform only the render copy; the original Host startup text is intact.
    if($OwnerGui -and $headerDisplay){
        $headerDisplay=Convert-Rc1OwnerStartupInstructions $headerDisplay
        $headerDisplay=Remove-Rc1OwnerWordmarkArt $headerDisplay
    }
    $headerLayoutKey=if($OwnerGui -and $headerDisplay){$headerLog.BannerLayoutKey}else{''}
    if ($script:lastRenderedHeader -cne $headerDisplay -or $script:lastHeaderLayoutKey -cne $headerLayoutKey) {
        $headerView = $null
        try { $headerView = $headerLog.GetViewPosition() } catch {}
        $headerSelectionStart = $headerLog.SelectionStart
        $headerSelectionLength = $headerLog.SelectionLength
        $headerHadSelection = ($headerLog.Focused -and $headerSelectionLength -gt 0)
        $headerX = if ($script:lastRenderedHeader -eq $null -or -not $headerView) { 0 } else { $headerView.X }
        $headerY = if ($script:lastRenderedHeader -eq $null -or -not $headerView) { 0 } else { $headerView.Y }

        try { $headerLog.SetSelectionHidden($true) } catch {}
        $headerLog.BeginUpdate()
        try {
            $headerLog.Text = $headerDisplay
            if ($headerLog.TextLength -gt 0) {
                $headerLog.Select(0,$headerLog.TextLength)
                if($OwnerGui){$headerLog.SelectionFont=$headerLog.Font}
                $headerLog.SelectionColor = [Drawing.Color]::Gainsboro
            }
            if (-not $OwnerGui -and $headerDisplay -like '*Remote Connection*') {
                # DESKTOP = orange (left artwork); COMMANDER = purple (right).
                [void]$headerLog.StyleStartupBanner(
                    $accentOrange,
                    [Drawing.Color]::FromArgb(123,95,162)
                )
            }
            # RC1: preserve compact banner and box borders but never compress
            # ordinary paragraphs or green Unicode connection/status glyphs.
            # The legacy 1.5.18 view keeps its original whole-header layout.
            if($OwnerGui){$headerLog.ApplyCompactHeaderLineArtSpacing()}
            else{$headerLog.ApplyCompactLineSpacing()}
            Color-HeaderSemantics $headerLog $headerLog.TextLength
            Color-LogToken $headerLog '🔧' $accentOrange
            Color-LogToken $headerLog '🚀' $accentOrange
            if($OwnerGui){Color-LogToken $headerLog '⏹' $accentStop}
            Color-LogToken $headerLog '✅' $accentSuccess
            Color-LogToken $headerLog '🔌' $statusGreen
            Color-LogToken $headerLog '⏳' $accentWait
            Color-LogToken $headerLog '🌐' $accentNetwork
            Color-LogToken $headerLog '💾' $accentStorage
            Color-LogToken $headerLog '👋' $accentGreeting
            if($OwnerGui){Apply-OwnerEmojiFont $headerLog}

            if ($headerHadSelection) {
                $restoreHeaderStart = [Math]::Min($headerSelectionStart,$headerLog.TextLength)
                $restoreHeaderLength = [Math]::Min($headerSelectionLength,[Math]::Max(0,($headerLog.TextLength-$restoreHeaderStart)))
                $headerLog.Select($restoreHeaderStart,$restoreHeaderLength)
            } else {
                $headerLog.Select(0,0)
                $headerLog.SelectionColor = $headerLog.ForeColor
            }

            try { $headerLog.SetViewPosition($headerX,$headerY) } catch {}
            $script:lastRenderedHeader = $headerDisplay
            $script:lastHeaderLayoutKey = $headerLayoutKey
        } finally {
            $headerLog.EndUpdate()
            try { $headerLog.SetSelectionHidden($false) } catch {}
        }
        try { $headerLog.SetViewPosition($headerX,$headerY) } catch {}
        $headerVScroll.Invalidate()
    }

    $view = $null
    try { $view = $log.GetViewPosition() } catch {}

    $visible = @()
    foreach ($item in $script:eventBlocks) { $visible += [string]$item }
    if (-not [string]::IsNullOrWhiteSpace($script:currentEvent)) { $visible += [string]$script:currentEvent }
    $visibleLimit=Get-Rc1JournalVisibleRowCapacity
    $script:ownerLastJournalCapacity=$visibleLimit
    if ($visible.Count -gt $visibleLimit) {
        $visible = $visible[($visible.Count-$visibleLimit)..($visible.Count-1)]
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $visible) {
        if (-not [string]::IsNullOrWhiteSpace($item)) { [void]$parts.Add($item.TrimEnd()) }
    }
    # Owner RC1 journal uses a continuous aligned number/bar column.
    # Keep original double-separated event layout in legacy 1.5.18 mode.
    $eventSeparator = if($script:ownerCompactJournal){$nl}else{$nl+$nl}
    $display = [string]::Join($eventSeparator,$parts)
    # Owner RC1 only: keep one blank line above the activity text.
    # No geometry changes to RichEdit, overlay scrollbars or splitter.
    # Reconstructed from event blocks on every render, so it cannot accumulate.
    if($script:ownerCompactJournal -and $display.Length -gt 0){$display=$nl+$display}
    if ($script:lastRenderedText -ceq $display) {
        # RichEdit can defer repaint/reflow after a hidden/redraw-frozen update.
        # Keep the viewport visually honest even when the logical text did not
        # change between two render requests.
        try { $log.RefreshViewport() } catch {}
        $vScroll.Invalidate()
        $hScroll.Invalidate()
        return
    }

    $shouldFollow = (
        $script:smartFollow -and
        -not $script:freezeViewport -and
        -not ($script:uiInteracting -or $vScroll.IsDragging -or $hScroll.IsDragging)
    )
    $finalX = if ($script:freezeViewport) { $script:frozenViewX } else { $script:userHorizontalX }
    $finalY = if ($script:freezeViewport) {
        $script:frozenViewY
    } elseif ($view) {
        $view.Y
    } else {
        0
    }

    $oldSelectionStart = $log.SelectionStart
    $oldSelectionLength = $log.SelectionLength
    $hadUserSelection = ($log.Focused -and $oldSelectionLength -gt 0)

    try { $log.SetSelectionHidden($true) } catch {}
    $log.BeginUpdate()
    try {
        $log.Text = $display
        if ($log.TextLength -gt 0) {
            $log.Select(0,$log.TextLength)
            $log.SelectionColor = [Drawing.Color]::Gainsboro
        }
        # Keep line-art glyphs visually joined in every RdcLogBox, not only the
        # startup banner.
        $log.ApplyCompactLineSpacing()
        if($script:ownerCompactJournal){
            # Consistent monospaced six-digit gutter and a connected Unicode │.
            # Event sequence is neutral body text, not highlighted metadata.
            Color-LogRegex $log '^(\d{6,18})\s+│' $log.ForeColor -1 1
            Color-LogRegex $log '^\d{6,18}\s+(│)' ([Drawing.Color]::Gainsboro) -1 1
        }
        Color-LogToken $log '🔧' $accentOrange
        Color-LogToken $log '🚀' $accentOrange
        Color-LogToken $log '✅' $accentSuccess
        Color-LogToken $log '❌' ([Drawing.Color]::LightCoral)
        Color-LogToken $log '🔌' $statusGreen
        Color-LogToken $log '⏳' $accentWait
        Color-LogToken $log '🌐' $accentNetwork
        Color-LogToken $log '💾' $accentStorage
        Color-LogToken $log '👋' $accentGreeting
        if($OwnerGui){Apply-OwnerEmojiFont $log}

        if ($hadUserSelection) {
            $restoreStart = [Math]::Min($oldSelectionStart,$log.TextLength)
            $restoreLength = [Math]::Min($oldSelectionLength,[Math]::Max(0,($log.TextLength-$restoreStart)))
            $log.Select($restoreStart,$restoreLength)
        } else {
            $log.Select(0,0)
            $log.SelectionColor = $log.ForeColor
        }

        $script:lastRenderedText = $display
    } finally {
        $log.EndUpdate()
        try { $log.SetSelectionHidden($false) } catch {}
    }

    # Scroll only after redraw is re-enabled. RichEdit may not have completed
    # line layout while WM_SETREDRAW is disabled, which can leave a one-line
    # stale viewport until the user touches the scrollbar.
    if ($shouldFollow) {
        try {
            $vScroll.ScrollToEnd()
            $finalY = $log.GetViewPosition().Y
        } catch {}
    }
    try { $log.SetViewPosition($finalX,$finalY) } catch {}
    try { $log.RefreshViewport() } catch {}
    $vScroll.Invalidate()
    $hScroll.Invalidate()
}
function Add-Log([string]$text) {
    $clean = Convert-ToCleanLogText $text
    if ([string]::IsNullOrWhiteSpace($clean)) { return }
    Update-AccountFromLog $clean
    Add-CompletedEvent $clean
    Render-CompactLog
}
function Process-RemoteLine([string]$line) {
    $text = $line.TrimEnd([char]13) + $nl

    # Desktop Commander emits stable Unicode transport markers:
    #   🔧 start, ✅ success, ❌ failure.
    # Use the marker as the primary classifier; validate the adjacent text so
    # marker-looking content inside JSON/tool output cannot trigger activity.
    # The classifier is pure; existing event/activity/health effects stay here.
    $classification = Get-RemoteLineClassification $line $script:remoteFaultKind
    $isReceived = $classification.ToolKind -eq 'received'
    $isCompleted = $classification.ToolKind -eq 'completed'
    $isFailed = $classification.ToolKind -eq 'failed'
    $isMarker = $isReceived -or $isCompleted -or $isFailed

    # Keep the original payload guard at the dispatch boundary: calling
    # Update-RemoteHealthFromLine directly still inspects its input as before.
    if (-not $isMarker -and -not $classification.IsSerializedToolPayload) {
        Update-RemoteHealthFromLine $line
    }

    $receivedPrefix = '🔧 '
    $completedPrefix = '✅ '
    $failedPrefix = '❌ '
    if ($isReceived) {
        $now = Get-Date
        if ($script:activeToolCalls -le 0 -and $script:lastToolCompletedAt) {
            $gapSeconds = ($now - $script:lastToolCompletedAt).TotalSeconds
            if ($gapSeconds -ge 0.05 -and $gapSeconds -le 24.0) {
                $script:activityGapEwmaSeconds =
                    (0.75 * [double]$script:activityGapEwmaSeconds) +
                    (0.25 * $gapSeconds)
                $script:activityHoldSeconds = [Math]::Min(
                    $activityMaxHoldSeconds,
                    [Math]::Max(
                        $activityMinHoldSeconds,
                        1.8 + 2.7 * [double]$script:activityGapEwmaSeconds
                    )
                )
            }
        }
        $script:activeToolCalls = [Math]::Max(0,[int]$script:activeToolCalls) + 1
        $script:lastToolMarkerAt = $now
        $script:activityHoldUntil = $null
        Set-DividerWorkState $true
    } elseif ($isCompleted) {
        $now = Get-Date
        $script:activeToolCalls = [Math]::Max(0,([int]$script:activeToolCalls - 1))
        $script:lastToolMarkerAt = $now
        if ($script:activeToolCalls -gt 0) {
            Set-DividerWorkState $true
        } else {
            $script:lastToolCompletedAt = $now
            $script:activityHoldUntil = $now.AddSeconds([double]$script:activityHoldSeconds)
            if ($script:remoteFaultLatched -and $script:remoteFaultKind -in @('tool-timeout','tool-failed')) {
                $recoveredKind = $script:remoteFaultKind
                Clear-RemoteFault
                $script:remoteReady = $true
                Start-DividerRecoveryFlash
                Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Успешный вызов подтвердил восстановление после ' + $recoveredKind + '.' + $nl)
            }
            elseif ($script:remoteFaultLatched -and $script:remoteFaultKind -in @(
                'transport-offline',
                'remote-unreachable',
                'connection-timeout',
                'local-mcp'
            )) {
                # A completed remote tool call is an end-to-end reachability
                # proof even if Presence recovery was not emitted again.
                Mark-RemoteReady ('successful tool call after ' + $script:remoteFaultKind)
            }
            elseif (-not $script:remoteReady -and -not $script:remoteFaultLatched) {
                # The shell can restart while an already-running Remote MCP has
                # published Presence in the past. A successful call proves that
                # adopted session is ready even without replaying old markers.
                Mark-RemoteReady 'successful tool call'
            }
            Set-DividerWorkState $true
        }
    } elseif ($isFailed) {
        $now = Get-Date
        $script:activeToolCalls = [Math]::Max(0,([int]$script:activeToolCalls - 1))
        $script:lastToolMarkerAt = $now
        $script:activityHoldUntil = $null
        Set-RemoteFault 'tool-failed' 'Вызов инструмента завершился ошибкой. Красный режим сохранится до следующего успешного вызова или восстановления Remote MCP.' $false
        Set-DividerWorkState ($script:activeToolCalls -gt 0)
    }

    if ($isMarker) {
        if ($script:tailNeedsMarker) { $script:tailNeedsMarker = $false }
        if (-not [string]::IsNullOrWhiteSpace($script:currentEvent)) { Commit-CurrentEvent }
        $script:startupComplete = $true
        $script:seenFirstRemoteEvent = $true
        $script:currentEvent = ''
        $script:currentEventTruncated = $false
        Append-CurrentEvent $text
        return
    }

    # The upper pane is startup/reference information. Freeze it once upstream
    # prints the Commands footer (or the equivalent initial-unreachable footer).
    # Everything after that is live operational output and belongs below.
    if (-not $script:startupComplete) {
        if ($script:startupBlock.Length -lt $uiStartupMaxChars) {
            $remaining = $uiStartupMaxChars - $script:startupBlock.Length
            if ($text.Length -le $remaining) { $script:startupBlock += $text }
            elseif ($remaining -gt 0) { $script:startupBlock += $text.Substring(0,$remaining) }
        }
        if (Test-StartupBoundaryLine $line) {
            $script:startupComplete = $true
        }
        return
    }

    # Once startup is complete, do not wait for a tool marker before surfacing
    # network/session lifecycle messages. This is what keeps Channel error /
    # reconnect / online / presence transitions in the lower activity pane.
    if ($script:tailNeedsMarker) { $script:tailNeedsMarker = $false }
    $script:seenFirstRemoteEvent = $true

    $runtimeEpisodeStart = (
        $line.IndexOf('Channel error:',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Channel closed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Device marked as offline',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Recreating channel...',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Local Desktop Commander MCP went away (',[StringComparison]::OrdinalIgnoreCase) -ge 0
    )
    if ($runtimeEpisodeStart -and -not [string]::IsNullOrWhiteSpace($script:currentEvent)) {
        $trimmedEvent = $script:currentEvent.TrimStart()
        if (
            $trimmedEvent.StartsWith($receivedPrefix,[StringComparison]::Ordinal) -or
            $trimmedEvent.StartsWith($completedPrefix,[StringComparison]::Ordinal) -or
            $trimmedEvent.StartsWith($failedPrefix,[StringComparison]::Ordinal)
        ) {
            Commit-CurrentEvent
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($line)) {
        Append-CurrentEvent $text
    } elseif (-not [string]::IsNullOrWhiteSpace($script:currentEvent)) {
        Append-CurrentEvent $text
    }

    $runtimeEpisodeEnd = (
        $line.IndexOf('Presence tracked (device ',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Local Desktop Commander MCP restarted; device is online again',[StringComparison]::OrdinalIgnoreCase) -ge 0
    )
    if ($runtimeEpisodeEnd -and -not [string]::IsNullOrWhiteSpace($script:currentEvent)) {
        Commit-CurrentEvent
    }
}
function Add-RemoteChunk([string]$text) {
    $clean = Convert-ToCleanLogText $text
    if ([string]::IsNullOrEmpty($clean)) { return }
    Update-AccountFromLog $clean
    $script:remoteLineBuffer += $clean

    $parts = $script:remoteLineBuffer -split "`n"
    if ($parts.Count -le 1) { return }
    $script:remoteLineBuffer = $parts[$parts.Count-1]

    for ($i=0; $i -lt ($parts.Count-1); $i++) {
        Process-RemoteLine $parts[$i]
    }
    Render-CompactLog
}
function Open-Reader {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    if ($script:reader -or -not (Test-Path $logPath)) { return }
    try {
        $stream = New-Object IO.FileStream(
            $logPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        )

        $length = [int64]$stream.Length
        $probeText = ''
        if ($length -gt 0) {
            $probeLen = [int][Math]::Min(131072,$length)
            $probe = New-Object byte[] $probeLen
            [void]$stream.Seek(0,[IO.SeekOrigin]::Begin)
            $probeRead = $stream.Read($probe,0,$probeLen)
            if ($probeRead -gt 0) {
                $probeText = [Text.Encoding]::UTF8.GetString($probe,0,$probeRead)
                Update-AccountFromLog $probeText
            }

            $script:eventBlocks.Clear()
            $script:currentEvent = ''
            $script:currentEventTruncated = $false
            $script:remoteLineBuffer = ''
            $script:startupComplete = $false

            if ($length -le $uiLogInitialTailBytes) {
                $script:startupBlock = ''
                $script:seenFirstRemoteEvent = $false
                $script:tailNeedsMarker = $false
                $snapshotLen = [int]$length
                $snapshot = New-Object byte[] $snapshotLen
                [void]$stream.Seek(0,[IO.SeekOrigin]::Begin)
                $snapshotRead = $stream.Read($snapshot,0,$snapshotLen)
                if ($snapshotRead -gt 0) {
                    Add-RemoteChunk ([Text.Encoding]::UTF8.GetString($snapshot,0,$snapshotRead))
                }
            } else {
                Set-StartupFromProbe $probeText
                $script:seenFirstRemoteEvent = $script:startupComplete
                $script:tailNeedsMarker = -not $script:startupComplete
                $tailLen = [int][Math]::Min($uiLogInitialTailBytes,$length)
                $target = $length - $tailLen
                $tail = New-Object byte[] $tailLen
                [void]$stream.Seek($target,[IO.SeekOrigin]::Begin)
                $tailRead = $stream.Read($tail,0,$tailLen)
                if ($tailRead -gt 0) {
                    $firstLf = -1
                    for ($i=0; $i -lt $tailRead; $i++) {
                        if ($tail[$i] -eq 10) { $firstLf = $i; break }
                    }
                    if ($firstLf -ge 0 -and ($firstLf + 1) -lt $tailRead) {
                        Add-RemoteChunk ([Text.Encoding]::UTF8.GetString($tail,$firstLf+1,$tailRead-$firstLf-1))
                    }
                }
            }
        }

        [void]$stream.Seek($length,[IO.SeekOrigin]::Begin)
        $script:reader = New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$false,4096)
        Render-CompactLog
    } catch {}
}
$logReadChunkChars = 24576
function Move-ReaderToRecentTailIfBehind {
    if (-not $script:reader) { return }
    try {
        $stream = $script:reader.BaseStream
        $length = [int64]$stream.Length
        $remaining = [int64]($length - $stream.Position)
        if ($remaining -le $uiLogCatchupThresholdBytes) { return }

        $tailLen = [int][Math]::Min($uiLogCatchupTailBytes,$length)
        $target = $length - $tailLen
        $tail = New-Object byte[] $tailLen

        $script:reader.DiscardBufferedData()
        [void]$stream.Seek($target,[IO.SeekOrigin]::Begin)
        $tailRead = $stream.Read($tail,0,$tailLen)

        $script:eventBlocks.Clear()
        $script:currentEvent = ''
        $script:currentEventTruncated = $false
        $script:remoteLineBuffer = ''
        $script:seenFirstRemoteEvent = $script:startupComplete
        $script:tailNeedsMarker = -not $script:startupComplete

        if ($tailRead -gt 0) {
            $firstLf = -1
            for ($i=0; $i -lt $tailRead; $i++) {
                if ($tail[$i] -eq 10) { $firstLf = $i; break }
            }
            if ($firstLf -ge 0 -and ($firstLf + 1) -lt $tailRead) {
                Add-RemoteChunk ([Text.Encoding]::UTF8.GetString($tail,$firstLf+1,$tailRead-$firstLf-1))
            }
        }

        $script:reader.DiscardBufferedData()
        [void]$stream.Seek($length,[IO.SeekOrigin]::Begin)
        Render-CompactLog
    } catch {}
}
function Read-LiveLog {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    Open-Reader
    if ($script:reader) {
        Move-ReaderToRecentTailIfBehind
        $chunk = [RdcLogBox]::ReadChunk($script:reader,$logReadChunkChars)
        if ($chunk) { Add-RemoteChunk $chunk }
    }
}
function Find-ExistingRemote {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    try {
        # Only attach to a launcher that writes to this installation's own log.
        # Do not adopt an arbitrary desktop-commander process started manually
        # by the user or by another RDC installation.
        $candidate = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -eq 'cmd.exe' -and
            $_.CommandLine -and
            $_.CommandLine.IndexOf('desktop-commander',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.CommandLine.IndexOf(' remote',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.CommandLine.IndexOf($logPath,[StringComparison]::OrdinalIgnoreCase) -ge 0
        } | Select-Object -First 1
        if (-not $candidate) { return $null }
        return Get-Process -Id $candidate.ProcessId -ErrorAction Stop
    } catch { return $null }
}
function Repair-DesktopCommanderNpxCache {
    $cacheRoot = $null
    if ($env:LOCALAPPDATA) { $cacheRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\\_npx' }
    if (-not $cacheRoot -or -not (Test-Path -LiteralPath $cacheRoot)) { return 0 }
    $removed = 0
    try {
        $packageDirs = Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'node_modules\\@wonderwhy-er\\desktop-commander' } |
            Where-Object { Test-Path -LiteralPath $_ }
        foreach ($packageDir in $packageDirs) {
            $entryPoint = Join-Path $packageDir 'dist\\index.js'
            if (Test-Path -LiteralPath $entryPoint) { continue }
            try {
                $cacheEntry = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $packageDir))
                Remove-Item -LiteralPath $cacheEntry -Recurse -Force -ErrorAction Stop
                $removed++
                Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Восстановление Desktop Commander: удалён неполный npx-кэш ' + $cacheEntry + $nl)
            } catch { Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Не удалось удалить повреждённый npx-кэш Desktop Commander: ' + $_.Exception.Message + $nl) }
        }
    } catch {}
    return $removed
}
function Test-DesktopCommanderBootstrapFailure {
    if (-not (Test-Path -LiteralPath $logPath)) { return $false }
    try {
        $tail = Get-Content -LiteralPath $logPath -Raw -ErrorAction Stop
        return ($tail -match '(?i)Cannot find module.*[\\/]@wonderwhy-er[\\/]desktop-commander[\\/]dist[\\/]index\.js')
    } catch { return $false }
}
# Recover npm ENOENT caused by an incomplete npx cache entry, without
# clearing unrelated packages or requiring npm.ps1 / ExecutionPolicy changes.
# The failing package.json path must come from THIS launch's npm log and point
# to an immediate, hex-named child of this user's npm-cache\\_npx directory.
function Repair-DesktopCommanderMissingNpxPackageJson {
    if ($SelfTest -or $Preview -or $script:npxMissingPackageRepairAttempted) { return $false }
    if (-not $env:LOCALAPPDATA -or -not (Test-Path -LiteralPath $logPath)) { return $false }
    try {
        $enoent = $false
        $candidate = $null
        foreach ($line in @(Get-Content -LiteralPath $logPath -Tail 160 -ErrorAction Stop)) {
            if ($line -match '(?i)^\s*npm\s+(?:error|ERR!)\s+code\s+ENOENT\s*$') {
                $enoent = $true
            }
            if ($line -match '(?i)^\s*npm\s+(?:error|ERR!)\s+path\s+(.+?)\s*$') {
                $candidate = $Matches[1].Trim().Trim([char]34,[char]39)
            }
        }
        if (-not $enoent -or -not $candidate) { return $false }

        $npxRoot = [IO.Path]::GetFullPath(
            (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx')
        ).TrimEnd([char]92)
        $reportedFile = [IO.Path]::GetFullPath($candidate)
        if ([IO.Path]::GetFileName($reportedFile) -cne 'package.json') { return $false }
        $entry = [IO.Path]::GetDirectoryName($reportedFile)
        $parent = [IO.Path]::GetDirectoryName($entry)
        $hash = [IO.Path]::GetFileName($entry)
        if (-not [string]::Equals($parent,$npxRoot,[StringComparison]::OrdinalIgnoreCase)) { return $false }
        if ($hash -notmatch '^[0-9a-fA-F]{8,64}$') { return $false }
        if (Test-Path -LiteralPath $reportedFile) { return $false }
        if (-not (Test-Path -LiteralPath $entry -PathType Container)) { return $false }

        # Never traverse junctions, symlinks or other directory reparse points.
        foreach ($dir in @($npxRoot,$entry)) {
            $info = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
            if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }

        # One deletion per startup episode. A later startup must not loop.
        $script:npxMissingPackageRepairAttempted = $true
        Remove-Item -LiteralPath $entry -Recurse -Force -ErrorAction Stop
        Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') +
            '] Восстановление npm: удалена только повреждённая папка npx-кэша ' +
            $hash + '; пакет будет загружен заново.' + $nl)
        return $true
    } catch {
        Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') +
            '] Восстановление npm не удалось: ' + $_.Exception.Message + $nl)
        return $false
    }
}
function Start-NoWindowCmd([string]$commandLine) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/d /s /c ' + $commandLine
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    return [Diagnostics.Process]::Start($psi)
}
function Start-Remote {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    try {
        if ($script:proc -and -not $script:proc.HasExited) { return }
        $script:manualStopRequested = $false
        Set-DividerStoppedState $false
        if (-not $script:supervisorRestarting) {
            $script:autoReconnectAttempt = 0
            $script:autoReconnectAt = $null
        }
        $existing = Find-ExistingRemote
        if ($existing) {
            Reset-CompactLogSession
            $script:proc = $existing
            $script:startTime = $existing.StartTime
            $script:stopping = $false
            $script:exitHandled = $false
            $script:remoteReady = $false
            $script:remoteInteractiveAuth = $false
            $script:remoteConnectDeadline = (Get-Date).AddSeconds($remoteConnectGraceSeconds)
            if (-not $script:remoteFaultLatched) {
                Set-DividerStartupState $true
            }
            Set-FinishButtonMode $true
            Set-State 'Проверка связи…' 'Подхвачен существующий remote-процесс; проверяю Remote MCP.' ([Drawing.Color]::Khaki)
            Set-RuntimeDisplay ('PID ' + $existing.Id) 'Проверяю существующий процесс' $true
            Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Найден уже работающий remote-процесс. Проверяю его Remote MCP-сессию.' + $nl)
            return
        }
        $npxPath = Resolve-NpxPath
        if (-not $SelfTest -and -not $Preview) { [void](Repair-DesktopCommanderNpxCache) }
        if ($script:reader) { $script:reader.Dispose(); $script:reader = $null }
        Reset-CompactLogSession
        if (Test-Path $logPath) {
            try {
                $previousLogPath = Join-Path $root 'remote-session.previous.log'
                Copy-Item -LiteralPath $logPath -Destination $previousLogPath -Force -ErrorAction Stop
            } catch {}
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
        $script:stopping = $false
        $script:exitHandled = $false
        Set-DividerStoppedState $false
        $script:remoteReady = $false
        $script:remoteInteractiveAuth = $false
        $script:remoteConnectDeadline = (Get-Date).AddSeconds($remoteConnectGraceSeconds)
        $script:startTime = Get-Date
        if (-not $script:remoteFaultLatched) {
            Set-DividerStartupState $true
        }
        Set-FinishButtonMode $true
        Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Запуск remote-процесса...' + $nl)
        Set-State 'Запускается…' ('Запускаю npx ' + $desktopCommanderPackage + ' remote') ([Drawing.Color]::Khaki)
        $cmd = '""' + $npxPath + '" --yes ' + $desktopCommanderPackage + ' remote > "' + $logPath + '" 2>&1"'
        $script:proc = Start-NoWindowCmd $cmd
        if (-not $script:proc) { throw 'Не удалось запустить remote-процесс без консольного окна.' }
        Set-RuntimeDisplay ('PID ' + $script:proc.Id)
    } catch {
        Set-State 'Ошибка запуска' $_.Exception.Message ([Drawing.Color]::LightCoral)
        Add-Log ('Ошибка запуска: ' + $_.Exception.Message + $nl)
        Set-FinishButtonMode $false
        $script:exitHandled = $true
        Set-RemoteFault 'startup-error' ('Ошибка запуска remote-процесса: ' + $_.Exception.Message) $true
    }
}
function Stop-Remote {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    if (-not $script:proc -or $script:proc.HasExited) { return }
    try {
        $freezePoint = $log.GetViewPosition()
        $script:frozenViewX = [Math]::Max(0,$freezePoint.X)
        $script:frozenViewY = [Math]::Max(0,$freezePoint.Y)
    } catch {
        $script:frozenViewX = $script:userHorizontalX
        $script:frozenViewY = 0
    }
    $script:smartFollow = $false
    $script:freezeViewport = $true
    $script:stopping = $true
    if (-not $script:preserveFaultOnStop) {
        Set-DividerStartupState $false
    }
    if (-not $script:supervisorRestarting -and -not $script:preserveFaultOnStop) {
        $script:remoteReady = $false
        $script:remoteConnectDeadline = $null
        $script:autoReconnectAttempt = 0
        $script:autoReconnectAt = $null
        Clear-RemoteFault
    }
    $finish.Enabled = $false
    if ($script:supervisorRestarting) {
        Set-State 'Переподключение…' 'Перезапускаю remote-процесс для восстановления связи.' ([Drawing.Color]::Khaki)
        Add-Log ($nl + '[' + (Get-Date -Format 'HH:mm:ss') + '] Автовосстановление: останавливаю старый remote-процесс…' + $nl)
    } else {
        Set-State 'Завершается…' 'Останавливаю remote-процесс и его дочерние процессы.' ([Drawing.Color]::Khaki)
        Add-Log ($nl + '[' + (Get-Date -Format 'HH:mm:ss') + '] Завершение по команде пользователя…' + $nl)
    }
    try {
        $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $killCmd = '""' + $taskkill + '" /PID ' + $script:proc.Id + ' /T /F"'
        $killer = Start-NoWindowCmd $killCmd
        if (-not $killer) { throw 'Не удалось запустить остановку remote-процесса.' }
        $script:remoteOperation.Process = $killer
    } catch { throw }
}
function Reset-RemoteHandle {
    if ($script:reader) {
        try { $script:reader.Dispose() } catch {}
        $script:reader = $null
    }
    if ($script:proc) {
        try { $script:proc.Dispose() } catch {}
        $script:proc = $null
    }
    $script:stopping = $false
    $script:exitHandled = $false
}
function Set-RemoteActionsEnabled([bool]$enabled) {
    $finish.Enabled = $enabled
    $accountButton.Enabled = $enabled
    $switchAccountItem.Enabled = $enabled
    $reconnectItem.Enabled = $enabled
}

function Begin-RemoteOperation([string]$action) {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    if ($script:remoteOperation -or $script:initializing) { return }
    $script:manualStopRequested = ($action -eq 'stop')
    $script:remoteOperation = [pscustomobject]@{
        Action = $action; Stage = 'stopping'; Process = $null
        Deadline = (Get-Date).AddSeconds(10); Failure = ''
    }
    Set-RemoteActionsEnabled $false
    try { Stop-Remote }
    catch { Complete-RemoteOperation $_.Exception.Message }
}

function Complete-RemoteOperation([string]$errorText = '') {
    $op = $script:remoteOperation
    if (-not $op) { return }
    if ($op.Process) { $op.Process.Dispose() }
    $script:remoteOperation = $null
    $script:supervisorRestarting = $false
    $script:preserveFaultOnStop = $false
    Set-RemoteActionsEnabled $true
    if ($errorText) {
        $script:closeRequested = $false
        $script:stopping = $false
        $script:manualStopRequested = $false
        $script:autoReconnectAt = $null
        Set-RemoteFault 'operation-failed' $errorText $false
        Set-State 'Действие не выполнено' $errorText ([Drawing.Color]::LightCoral)
        Add-Log ($errorText + $nl)
        return
    }
    if ($op.Action -eq 'close' -or $script:closeRequested) {
        $script:allowClose = $true
        $form.Close()
        return
    }
    if ($op.Action -eq 'stop') {
        $script:remoteReady = $false
        $script:remoteConnectDeadline = $null
        $script:autoReconnectAt = $null
        Clear-RemoteFault
        Set-DividerStoppedState $true
        Set-FinishButtonMode $false
        Set-State 'Остановлен' 'Remote-процесс остановлен.' ([Drawing.Color]::Silver)
    }
    elseif ($op.Action -in @('restart','logout','reconnect')) {
        $script:supervisorRestarting = $op.Action -eq 'reconnect'
        try { Start-Remote }
        finally { $script:supervisorRestarting = $false }
        if (-not $script:proc -or $script:proc.HasExited) {
            Schedule-AutoReconnect 'Новый remote-процесс не запустился.'
        }
    }
}

function Update-RemoteOperation {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    $op = $script:remoteOperation
    if (-not $op) { return }
    try {
        if ($op.Process -and -not $op.Process.HasExited) {
            if ((Get-Date) -lt $op.Deadline) { return }
            if ($op.Stage -eq 'logout') {
                $logoutPid = $op.Process.Id
                $op.Process.Dispose()
                $op.Process = $null
                $killCmd = '""' + (Join-Path $env:SystemRoot 'System32\taskkill.exe') + '" /PID ' + $logoutPid + ' /T /F"'
                $op.Process = Start-NoWindowCmd $killCmd
                $op.Stage = 'logout-timeout'
                $op.Deadline = (Get-Date).AddSeconds(10)
                $op.Failure = 'Выход из аккаунта не завершился за 30 секунд. Повторите действие.'
                return
            }
            throw 'Операция остановки не завершилась вовремя. Remote-процесс требует проверки.'
        }
        if ($op.Stage -eq 'logout-timeout') { throw $op.Failure }
        if ($op.Process -and $op.Process.ExitCode -ne 0) {
            throw ('Операция ' + $op.Stage + ' завершилась с кодом ' + $op.Process.ExitCode + '.')
        }
        if ($op.Process) { $op.Process.Dispose(); $op.Process = $null }
        if ($op.Stage -eq 'stopping') {
            if ($script:proc -and -not $script:proc.HasExited) {
                if ((Get-Date) -ge $op.Deadline) { throw 'Remote-процесс не остановлен.' }
                return
            }
            Read-LiveLog
            Reset-RemoteHandle
            if ($op.Action -eq 'logout' -and -not $script:closeRequested) {
                Set-State 'Выход из аккаунта…' 'Удаляю авторизацию; окно остаётся доступным.' ([Drawing.Color]::Khaki)
                $logoutFile = Join-Path $root 'logout-session.log'
                $logoutCmd = '""' + (Resolve-NpxPath) + '" --yes ' + $desktopCommanderPackage + ' remote --logout > "' + $logoutFile + '" 2>&1"'
                $op.Process = Start-NoWindowCmd $logoutCmd
                if (-not $op.Process) { throw 'Не удалось запустить выход из аккаунта.' }
                $op.Stage = 'logout'
                $op.Deadline = (Get-Date).AddSeconds(30)
                return
            }
        }
        elseif ($op.Stage -eq 'logout') {
            Set-AccountDisplay $null
            Add-Log ('Авторизация сброшена. Запускаю новый вход.' + $nl)
        }
        Complete-RemoteOperation
    } catch { Complete-RemoteOperation $_.Exception.Message }
}

function Invoke-AutoReconnect {
    if ($SelfTest -or $Preview -or $script:remoteOperation -or $script:supervisorRestarting) { return }
    if (-not $script:autoReconnectAt -or (Get-Date) -lt $script:autoReconnectAt) { return }
    $script:autoReconnectAt = $null
    if ($script:autoReconnectAttempt -ge $remoteReconnectDelaysSeconds.Count) { return }
    $script:autoReconnectAttempt++
    $script:supervisorRestarting = $true
    Add-Log ('Автовосстановление: попытка ' + $script:autoReconnectAttempt + '.' + $nl)
    Begin-RemoteOperation 'reconnect'
}

function Restart-Remote {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    $answer = [Windows.Forms.MessageBox]::Show(
        'RDC Relay будет кратковременно отключён и запущен снова под текущим аккаунтом.',
        'Переподключить RDC Relay', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $script:autoReconnectAttempt = 0
    $script:autoReconnectAt = $null
    $script:npxMissingPackageRepairAttempted = $false
    $script:preserveFaultOnStop = $script:remoteFaultLatched
    Begin-RemoteOperation 'restart'
}

function Switch-RemoteAccount {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    $message = 'Смена аккаунта разорвёт текущее удалённое соединение.' + $nl + $nl +
        'После выхода RDC Relay запустится снова и предложит авторизоваться в браузере.' + $nl + $nl +
        'Войдите в тот же аккаунт Desktop Commander, который подключён в ChatGPT.' + $nl + $nl + 'Продолжить?'
    $answer = [Windows.Forms.MessageBox]::Show($message,'Сменить аккаунт Desktop Commander',
        [Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    Begin-RemoteOperation 'logout'
}

function Start-RuntimeInitialization {
    if ($OwnerGui) { throw 'RC1_OWNER_GUI_ACTION_BLOCKED' }
    $script:initializing = $true
    Set-RemoteActionsEnabled $false
    $updaterPath = Join-Path $root 'update.ps1'
    # -SkipUpdate only suppresses the automatic startup check after an update.
    # An explicit click on the update notice must ALWAYS run the updater.
    if (($script:updateInstallRequested -or
         (-not $SkipUpdate -and (Test-RdcAutoUpdateEnabled $script:autoUpdatePreferencePath))) -and
        (Test-Path -LiteralPath $updaterPath)) {
        try {
            Set-State 'Проверка обновлений…' 'Проверяю установленную версию; окно остаётся доступным.' ([Drawing.Color]::Khaki)
            $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $updaterPath + '"'),'-InstallRoot',('"' + $root + '"'),'-CurrentVersion',$appVersion)
            if ($script:updateInstallRequested) { $args += '-Force' }
            $script:updateProc = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -PassThru
            return
        } catch { Add-Log ('Проверка обновления не запущена: ' + $_.Exception.Message + $nl) }
    }
    Complete-RuntimeInitialization
}

function Complete-RuntimeInitialization {
    if ($script:updateProc) {
        if (-not $script:updateProc.HasExited) { return }
        $code = $script:updateProc.ExitCode
        $script:updateProc.Dispose()
        $script:updateProc = $null
        if ($script:updateInstallRequested) {
            $script:updateInstallRequested = $false
            if ($script:enableUpdateNotice -and $code -ne 42) {
                Complete-RdcUpdateNoticeInstall $code
            }
        }
        if ($code -eq 42) {
            if ($windowMutex) {
                $windowMutex.ReleaseMutex(); $windowMutex.Dispose(); $script:windowMutex = $null
            }
            if (-not $script:closeRequested) {
                Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
                    '-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass',
                    '-File',('"' + (Join-Path $root 'remote-window.ps1') + '"'),'-SkipUpdate') -WindowStyle Hidden
            }
            $script:allowClose = $true
            $form.Close()
            return
        }
        if ($code -ne 0) { Add-Log ('Обновление не установлено. Подробности: update.log.' + $nl) }
    }
    if ($script:updateInstallRequested) {
        $script:updateInstallRequested = $false
        if ($script:enableUpdateNotice) { Complete-RdcUpdateNoticeInstall 1 }
    }
    $script:initializing = $false
    Set-RemoteActionsEnabled $true
    if ($script:closeRequested) { $script:allowClose = $true; $form.Close(); return }
    Hide-LegacyRemoteTerminal
    Start-Remote
}

# Owner-only modals reuse the Account Switch dialog's dark WinForms
# typography, surface colors, spacing and confirmation button geometry.
# They never change the Host or Remote lifecycle by themselves.
# Localize newly opened Owner dialogs only; the legacy 1.5 UI remains unchanged.
# DialogResult/AcceptButton/CancelButton and Host command routing never use these labels.
function Get-RdcOwnerDialogText([string]$key,[string]$fallback){
    if($OwnerGui -and (Get-Command Get-RdcOwnerUiText -CommandType Function -ErrorAction SilentlyContinue)){
        return Get-RdcOwnerUiText $key $fallback
    }
    return $fallback
}
function New-RdcOwnerStopDialog {
    $dialog=New-Object Windows.Forms.Form
    $dialog.Name='rc1-stop-remote-confirmation'
    $dialog.Text=(Get-RdcOwnerDialogText 'dialog.stop.title' 'Остановка Remote')
    $dialog.FormBorderStyle=[Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition=[Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ShowInTaskbar=$false
    $dialog.MaximizeBox=$false
    $dialog.MinimizeBox=$false
    $dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Font
    $dialog.Font=[Drawing.Font]::new('Segoe UI',10)
    $dialog.ClientSize=[Drawing.Size]::new(480,168)
    $dialog.BackColor=[Drawing.Color]::FromArgb(29,32,36)
    $dialog.ForeColor=[Drawing.Color]::Gainsboro

    $layout=New-Object Windows.Forms.TableLayoutPanel
    $layout.Name='rc1-stop-remote-layout'
    $layout.Dock=[Windows.Forms.DockStyle]::Fill
    $layout.Padding=[Windows.Forms.Padding]::new(24,20,24,16)
    $layout.ColumnCount=1
    $layout.RowCount=2
    [void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,52))

    $messageRow=New-Object Windows.Forms.TableLayoutPanel
    $messageRow.Name='rc1-stop-remote-warning-row'
    $messageRow.Dock=[Windows.Forms.DockStyle]::Top
    $messageRow.AutoSize=$true
    $messageRow.ColumnCount=2
    $messageRow.RowCount=1
    $messageRow.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
    [void]$messageRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,44))
    [void]$messageRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $warning=New-Object Windows.Forms.PictureBox
    $warning.Name='rc1-stop-remote-warning-icon'
    $warning.Image=([Drawing.SystemIcons]::Warning).ToBitmap()
    $warning.Size=[Drawing.Size]::new(32,32)
    $warning.SizeMode=[Windows.Forms.PictureBoxSizeMode]::CenterImage
    $warning.Margin=[Windows.Forms.Padding]::new(0,0,12,0)
    $warning.TabStop=$false
    $warning.AccessibleDescription=(Get-RdcOwnerDialogText 'dialog.accessibility.warningIcon' 'Стандартный значок предупреждения.')
    $message=New-Object Windows.Forms.Label
    $message.Name='rc1-stop-remote-question'
    $message.Text=(Get-RdcOwnerDialogText 'dialog.stop.question' 'Остановить Remote?')
    $message.Font=[Drawing.Font]::new($dialog.Font,[Drawing.FontStyle]::Bold)
    $message.AutoSize=$true
    $message.MaximumSize=[Drawing.Size]::new(385,0)
    $message.Dock=[Windows.Forms.DockStyle]::Top
    $message.Margin=[Windows.Forms.Padding]::new(0,3,0,0)
    $message.ForeColor=$dialog.ForeColor
    [void]$messageRow.Controls.Add($warning,0,0)
    [void]$messageRow.Controls.Add($message,1,0)
    [void]$layout.Controls.Add($messageRow,0,0)

    $buttons=New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Name='rc1-stop-remote-buttons'
    $buttons.Dock=[Windows.Forms.DockStyle]::Fill
    $buttons.FlowDirection=[Windows.Forms.FlowDirection]::RightToLeft
    $buttons.WrapContents=$false
    $buttons.Padding=[Windows.Forms.Padding]::new(0,8,0,0)
    $buttons.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
    $no=New-Object RdcModalButton
    $no.AmbientShadow=[bool]$OwnerGui
    $no.Name='rc1-stop-remote-no'
    $no.Text=(Get-RdcOwnerDialogText 'dialog.button.no' 'Нет')
    $no.Size=[Drawing.Size]::new(96,34)
    $no.DialogResult=[Windows.Forms.DialogResult]::No
    $no.Margin=[Windows.Forms.Padding]::new(8,0,0,0)
    $yes=New-Object RdcModalButton
    $yes.AmbientShadow=[bool]$OwnerGui
    $yes.Name='rc1-stop-remote-yes'
    $yes.Text=(Get-RdcOwnerDialogText 'dialog.button.yes' 'Да')
    $yes.Size=[Drawing.Size]::new(96,34)
    $yes.DialogResult=[Windows.Forms.DialogResult]::Yes
    $yes.Margin=[Windows.Forms.Padding]::new(8,0,0,0)
    [void]$buttons.Controls.Add($no)
    [void]$buttons.Controls.Add($yes)
    [void]$layout.Controls.Add($buttons,0,1)
    if($OwnerGui){
        # Extend the action row into the existing 24px horizontal gutter.
        # Compensate every other row's margins, retaining body geometry.
        $layout.Padding=[Windows.Forms.Padding]::new(21,20,21,16)
        foreach($child in $layout.Controls){
            if($child -ne $buttons){
                $m=$child.Margin
                $child.Margin=[Windows.Forms.Padding]::new($m.Left+3,$m.Top,$m.Right+3,$m.Bottom)
            }
        }
        $buttons.Padding=[Windows.Forms.Padding]::new(3,8,3,0)
    }
    $dialog.Controls.Add($layout)
    $dialog.AcceptButton=$no
    $dialog.CancelButton=$no
    $dialog.ActiveControl=$no
    return $dialog
}
function Show-RdcOwnerStopConfirmation {
    $confirmation=New-RdcOwnerStopDialog
    try { return $confirmation.ShowDialog($form) }
    finally { $confirmation.Dispose() }
}

$finish.Add_Click({
    if ($OwnerGui) {
        if (-not $script:ownerManagedMode) { return }
        if ($script:ownerCanStop) {
            $answer=Show-RdcOwnerStopConfirmation
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
            $script:ownerQueuedAction='STOP'
        } elseif ($script:ownerCanStart) { $script:ownerQueuedAction='START' }
        return
    }
    if ($script:remoteOperation -or $script:initializing) { return }
    if ($script:proc -and -not $script:proc.HasExited) {
        Begin-RemoteOperation 'stop'
        return
    }

    try {
        Reset-RemoteHandle
        Set-FinishButtonMode $true
        Start-Remote
        Refresh-Window
    } catch {
        Set-FinishButtonMode $false
    }
})
$quotaAuthItem.Add_Click({
    # Explicit user opt-in is durable and also gates the Tray Host's
    # automatic who_am_i requests. OAuth is independent of Remote credentials.
    if(-not $OwnerGui -or -not $script:ownerManagedMode){return}
    $enabled=[bool]$quotaAuthItem.Checked
    try{
        Set-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath $enabled
    }catch{
        $quotaAuthItem.Checked=[bool](Test-Rc1QuotaDisplayEnabled $script:ownerQuotaEnabledPath)
        [void][Windows.Forms.MessageBox]::Show((Get-RdcOwnerDialogText 'tray.notice.quotaSaveFailed' 'Не удалось сохранить настройку остатка вызовов.'),
            'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $script:ownerQuotaNextCheckUtc=[DateTime]::MinValue
    $script:ownerLastQuotaText=''
    $quotaLabel.Text=(Get-RdcOwnerDialogText 'gui.quota.unknown' 'Остаток вызовов: --%')
    $quotaLabel.ForeColor=[Drawing.Color]::Silver
    # The Tray Host retains its original automatic per-account OAuth and
    # 30-minute quota poll. Do not launch a second browser client from GUI:
    # on reenable the Host's next 15-second tick resumes that workflow.
})
# The tray owns the existing auto-update preference write route.
$accountButton.Add_Click({
    $accountMenu.Show($accountButton,(New-Object Drawing.Point(0,$accountButton.Height)))
})
# Owner-only confirmation: separate labels are required for one bold leading
# instruction. A stock MessageBox cannot style a single paragraph. The modal
# itself performs NO account/Remote action; only an explicit Yes enables the
# existing authenticated Host request.
function New-RdcOwnerAccountSwitchDialog {
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text=(Get-RdcOwnerDialogText 'dialog.switch.title' 'Смена аккаунта Desktop Commander')
    $dialog.Name='rc1-account-switch-confirmation'
    $dialog.FormBorderStyle=[Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition=[Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ShowInTaskbar=$false
    $dialog.MaximizeBox=$false
    $dialog.MinimizeBox=$false
    $dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Font
    $dialog.Font=[Drawing.Font]::new('Segoe UI',10)
    $dialog.ClientSize=[Drawing.Size]::new(600,325)
    $dialog.BackColor=[Drawing.Color]::FromArgb(29,32,36)
    $dialog.ForeColor=[Drawing.Color]::Gainsboro

    $layout=New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock=[Windows.Forms.DockStyle]::Fill
    $layout.Padding=[Windows.Forms.Padding]::new(24,20,24,16)
    $layout.ColumnCount=1
    $layout.RowCount=6
    [void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    for($i=0;$i -lt 4;$i++){
        [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    }
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,52))

    $paragraphs=@(
        (Get-RdcOwnerDialogText 'dialog.switch.intro' 'Сначала откройте сайт Desktop Commander и войдите в аккаунт, на который хотите переключиться.'),
        (Get-RdcOwnerDialogText 'dialog.switch.disconnection' 'Смена аккаунта разорвёт текущее соединение и отзовёт авторизацию этого устройства.'),
        (Get-RdcOwnerDialogText 'dialog.switch.reauthorization' 'После выхода из аккаунта RDC Relay запустит новый Remote и начнёт процедуру авторизации устройства.'),
        (Get-RdcOwnerDialogText 'dialog.switch.question' 'Продолжить смену аккаунта?')
    )
    for($i=0;$i -lt $paragraphs.Count;$i++){
        $label=New-Object Windows.Forms.Label
        $label.Name='rc1-account-switch-paragraph-'+[string]($i+1)
        $label.Text=$paragraphs[$i]
        $label.AutoSize=$true
        $label.MaximumSize=[Drawing.Size]::new($(if($i -eq 0){502}else{546}),0)
        $label.Dock=[Windows.Forms.DockStyle]::Top
        $label.ForeColor=$dialog.ForeColor
        $label.Margin=[Windows.Forms.Padding]::new(0,0,0,$(if($i -lt 3 -and $i -ne 0){14}else{0}))
        if($i -eq 0){
            $label.Font=[Drawing.Font]::new($dialog.Font,[Drawing.FontStyle]::Bold)
            # Only the bold opening instruction is indented. The other
            # paragraphs retain their exact original left coordinate.
            $lead=New-Object Windows.Forms.TableLayoutPanel
            $lead.Name='rc1-account-switch-warning-row'
            $lead.Dock=[Windows.Forms.DockStyle]::Top
            $lead.AutoSize=$true
            $lead.ColumnCount=2
            $lead.RowCount=1
            $lead.Margin=[Windows.Forms.Padding]::new(0,0,0,14)
            [void]$lead.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,44))
            [void]$lead.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
            $warning=New-Object Windows.Forms.PictureBox
            $warning.Name='rc1-account-switch-warning-icon'
            $warning.Image=([Drawing.SystemIcons]::Warning).ToBitmap()
            $warning.Size=[Drawing.Size]::new(32,32)
            $warning.SizeMode=[Windows.Forms.PictureBoxSizeMode]::CenterImage
            $warning.Margin=[Windows.Forms.Padding]::new(0,0,12,0)
            $warning.TabStop=$false
            $warning.AccessibleDescription=(Get-RdcOwnerDialogText 'dialog.accessibility.warningIcon' 'Стандартный значок предупреждения.')
            [void]$lead.Controls.Add($warning,0,0)
            [void]$lead.Controls.Add($label,1,0)
            $layout.Controls.Add($lead,0,$i)
        }else{
            $layout.Controls.Add($label,0,$i)
        }
    }

    # Two zones in the original bottom row: site helper at far left,
    # unchanged Yes/No pair aligned at far right with symmetric edge insets.
    $buttonRow=New-Object Windows.Forms.TableLayoutPanel
    $buttonRow.Name='rc1-account-switch-bottom-row'
    $buttonRow.Dock=[Windows.Forms.DockStyle]::Fill
    $buttonRow.ColumnCount=2
    $buttonRow.RowCount=1
    $buttonRow.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
    [void]$buttonRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,50))
    [void]$buttonRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,50))
    $site=New-Object RdcModalButton
    $site.AmbientShadow=[bool]$OwnerGui
    $site.Name='rc1-account-switch-signout-website'
    $site.Text=(Get-RdcOwnerDialogText 'dialog.switch.signOut' 'Выйти из аккаунта')
    $site.Size=[Drawing.Size]::new(192,34)
    $site.Anchor=([Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left)
    $site.Margin=[Windows.Forms.Padding]::new(0,8,0,0)
    $site.DialogResult=[Windows.Forms.DialogResult]::None
    $site.AccessibleDescription=(Get-RdcOwnerDialogText 'dialog.switch.signOutDescription' 'Открывает официальный кабинет Desktop Commander. Выход из аккаунта выполняется вручную на сайте.')
    $site.Add_Click({
        # A web-navigation helper only: never log out Remote, change
        # credentials or close this confirmation on the site-button click.
        try{
            Start-Process -FilePath 'https://mcp.desktopcommander.app/settings' -ErrorAction Stop | Out-Null
        }catch{
            [void][Windows.Forms.MessageBox]::Show(
                (Get-RdcOwnerDialogText 'dialog.switch.websiteError' 'Не удалось открыть сайт Desktop Commander.'),
                'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning)
        }
    })
    $buttons=New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Name='rc1-account-switch-buttons'
    $buttons.Dock=[Windows.Forms.DockStyle]::Fill
    $buttons.FlowDirection=[Windows.Forms.FlowDirection]::RightToLeft
    $buttons.WrapContents=$false
    $buttons.Padding=[Windows.Forms.Padding]::new(0,8,0,0)
    $buttons.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
    $no=New-Object RdcModalButton
    $no.AmbientShadow=[bool]$OwnerGui
    $no.Name='rc1-account-switch-no'
    $no.Text=(Get-RdcOwnerDialogText 'dialog.button.no' 'Нет')
    $no.Size=[Drawing.Size]::new(96,34)
    $no.DialogResult=[Windows.Forms.DialogResult]::No
    $no.Margin=[Windows.Forms.Padding]::new(8,0,0,0)
    $yes=New-Object RdcModalButton
    $yes.AmbientShadow=[bool]$OwnerGui
    $yes.Name='rc1-account-switch-yes'
    $yes.Text=(Get-RdcOwnerDialogText 'dialog.button.yes' 'Да')
    $yes.Size=[Drawing.Size]::new(96,34)
    $yes.DialogResult=[Windows.Forms.DialogResult]::Yes
    $yes.Margin=[Windows.Forms.Padding]::new(8,0,0,0)
    [void]$buttons.Controls.Add($no)
    [void]$buttons.Controls.Add($yes)
    [void]$buttonRow.Controls.Add($site,0,0)
    [void]$buttonRow.Controls.Add($buttons,1,0)
    $layout.Controls.Add($buttonRow,0,5)
    if($OwnerGui){
        # Extend the action row into the existing 24px horizontal gutter.
        # Compensate every other row's margins, retaining body geometry.
        $layout.Padding=[Windows.Forms.Padding]::new(21,20,21,16)
        foreach($child in $layout.Controls){
            if($child -ne $buttonRow){
                $m=$child.Margin
                $child.Margin=[Windows.Forms.Padding]::new($m.Left+3,$m.Top,$m.Right+3,$m.Bottom)
            }
        }
        $site.Margin=[Windows.Forms.Padding]::new(3,8,0,0)
        $buttons.Padding=[Windows.Forms.Padding]::new(0,8,3,0)
    }
    $dialog.Controls.Add($layout)
    # Destructive account logout must never be the implicit Enter/Esc choice.
    $dialog.AcceptButton=$no
    $dialog.CancelButton=$no
    $dialog.ActiveControl=$no
    return $dialog
}
function Show-RdcOwnerAccountSwitchConfirmation {
    $confirmation=New-RdcOwnerAccountSwitchDialog
    try{
        return $confirmation.ShowDialog($form)
    }finally{
        $confirmation.Dispose()
    }
}
$switchAccountItem.Add_Click({
    if ($OwnerGui) {
        if (-not $script:ownerManagedMode -or -not $script:ownerCanSwitchAccount) { return }
        $answer=Show-RdcOwnerAccountSwitchConfirmation
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        $script:ownerCanSwitchAccount=$false
        $switchAccountItem.Enabled=$false
        $script:ownerQueuedAction='SWITCH_ACCOUNT'
        $script:ownerLastSafePresentation=$null
        Set-State (Get-RdcOwnerDialogText 'owner.progress.switchName' 'Смена аккаунта…') (Get-RdcOwnerDialogText 'owner.progress.switchDetail' 'Выход из аккаунта') ([Drawing.Color]::Khaki)
        return
    }
    Switch-RemoteAccount
})
# Reuse the exact Stop modal geometry, safe No default and standard
# Windows warning triangle. No second style/layout implementation.
function New-RdcOwnerReconnectDialog {
    $dialog=New-RdcOwnerStopDialog
    $dialog.Name='rc1-reconnect-remote-confirmation'
    $dialog.Text=(Get-RdcOwnerDialogText 'dialog.reconnect.title' 'Переподключение Remote')
    $message=@($dialog.Controls.Find('rc1-stop-remote-question',$true))|Select-Object -First 1
    $warning=@($dialog.Controls.Find('rc1-stop-remote-warning-icon',$true))|Select-Object -First 1
    $buttons=@($dialog.Controls.Find('rc1-stop-remote-buttons',$true))|Select-Object -First 1
    $yes=@($dialog.Controls.Find('rc1-stop-remote-yes',$true))|Select-Object -First 1
    $no=@($dialog.Controls.Find('rc1-stop-remote-no',$true))|Select-Object -First 1
    if(-not $message -or -not $warning -or -not $buttons -or -not $yes -or -not $no){
        $dialog.Dispose()
        throw 'RC1_RECONNECT_CONFIRMATION_LAYOUT_MISSING'
    }
    $message.Name='rc1-reconnect-remote-question'
    $message.Text=(Get-RdcOwnerDialogText 'dialog.reconnect.question' 'Переподключить Remote?')
    $warning.Name='rc1-reconnect-remote-warning-icon'
    $buttons.Name='rc1-reconnect-remote-buttons'
    $yes.Name='rc1-reconnect-remote-yes'
    $no.Name='rc1-reconnect-remote-no'
    return $dialog
}
function Show-RdcOwnerReconnectConfirmation {
    $confirmation=New-RdcOwnerReconnectDialog
    try { return $confirmation.ShowDialog($form) }
    finally { $confirmation.Dispose() }
}
$reconnectItem.Add_Click({
    if ($OwnerGui) {
        if (-not $script:ownerManagedMode -or -not $script:ownerCanReconnect) { return }
        $answer=Show-RdcOwnerReconnectConfirmation
        if ($answer -eq [Windows.Forms.DialogResult]::Yes) { $script:ownerQueuedAction='RECONNECT' }
        return
    }
    Restart-Remote
})
$devicesItem.Add_Click({
    if ($OwnerGui) {
        if ($script:ownerRealMode) { $script:ownerQueuedNavigation='DEVICE_MANAGEMENT' }
        return
    }
    try { Start-Process 'https://mcp.desktopcommander.app/' } catch {}
})
$verifyDeviceItem.Add_Click({
    if ($OwnerGui) { return } # The RC1 item is absent; no manual verification path.
    try { Start-Process 'https://mcp.desktopcommander.app/device/verify' } catch {}
})
# Direct Help action: no intermediate context menu.
# Do not change focus during MouseDown: WinForms may then suppress the Click.
# Clear the focus only AFTER opening About, once the normal Click has fired.
$helpButton.Add_Click({
    try { Show-RdcAbout }
    finally { $form.ActiveControl=$null }
})

# Keep all existing mode-specific Help content, but present it in an
# Owner-only dark scrollable dialog instead of a light system MessageBox.
function New-RdcOwnerHelpDialog([string]$content) {
    $dialog=New-Object Windows.Forms.Form
    $dialog.Name='rc1-help-dialog'
    $dialog.Text=(Get-RdcOwnerDialogText 'help.dialog.title' 'RDC Relay — справка')
    $dialog.FormBorderStyle=[Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition=[Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ShowInTaskbar=$false
    $dialog.MaximizeBox=$false
    $dialog.MinimizeBox=$false
    $dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Font
    $dialog.Font=[Drawing.Font]::new('Segoe UI',10)
    # Height is set after measuring the help text: do not leave the former
    # oversized 480px panel for the short Owner help variants.
    $dialog.ClientSize=[Drawing.Size]::new(660,325)
    $dialog.BackColor=[Drawing.Color]::FromArgb(29,32,36)
    $dialog.ForeColor=[Drawing.Color]::Gainsboro

    $layout=New-Object Windows.Forms.TableLayoutPanel
    $layout.Name='rc1-help-layout'
    $layout.Dock=[Windows.Forms.DockStyle]::Fill
    $layout.Padding=[Windows.Forms.Padding]::new(24,20,24,16)
    $layout.ColumnCount=1
    $layout.RowCount=3
    [void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,44))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,52))

    # Standard Windows circled-question icon, aligned with the title.
    $headingRow=New-Object Windows.Forms.TableLayoutPanel
    $headingRow.Name='rc1-help-heading-row'
    $headingRow.Dock=[Windows.Forms.DockStyle]::Top
    $headingRow.ColumnCount=2
    $headingRow.RowCount=1
    $headingRow.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
    [void]$headingRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,44))
    [void]$headingRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $helpIcon=New-Object Windows.Forms.PictureBox
    $helpIcon.Name='rc1-help-question-icon'
    $helpIcon.Image=([Drawing.SystemIcons]::Question).ToBitmap()
    $helpIcon.Size=[Drawing.Size]::new(32,32)
    $helpIcon.SizeMode=[Windows.Forms.PictureBoxSizeMode]::CenterImage
    $helpIcon.Margin=[Windows.Forms.Padding]::new(0,0,12,0)
    $helpIcon.TabStop=$false
    $helpIcon.AccessibleDescription=(Get-RdcOwnerDialogText 'help.dialog.iconAccessible' 'Стандартный значок вопроса.')
    $heading=New-Object Windows.Forms.Label
    $heading.Name='rc1-help-heading'
    $heading.Text=(Get-RdcOwnerDialogText 'help.dialog.heading' 'Справка / О программе')
    $heading.Font=[Drawing.Font]::new('Segoe UI',12,[Drawing.FontStyle]::Bold)
    $heading.ForeColor=$dialog.ForeColor
    $heading.AutoSize=$true
    $heading.Margin=[Windows.Forms.Padding]::new(0,3,0,0)
    [void]$headingRow.Controls.Add($helpIcon,0,0)
    [void]$headingRow.Controls.Add($heading,1,0)
    [void]$layout.Controls.Add($headingRow,0,0)

    $body=New-Object Windows.Forms.RichTextBox
    $body.Name='rc1-help-content'
    $body.Text=$content
    $body.ReadOnly=$true
    $body.TabStop=$true
    $body.AccessibleName=(Get-RdcOwnerDialogText 'help.dialog.contentAccessible' 'Справка RDC Relay')
    $body.ScrollBars=[Windows.Forms.RichTextBoxScrollBars]::Vertical
    $body.WordWrap=$true
    $body.DetectUrls=$false
    $body.ShortcutsEnabled=$true
    $body.BorderStyle=[Windows.Forms.BorderStyle]::None
    $body.Dock=[Windows.Forms.DockStyle]::Fill
    # No contrasting grey textbox panel: help reads as one continuous surface.
    $body.BackColor=$dialog.BackColor
    $body.ForeColor=$dialog.ForeColor
    $body.Font=$dialog.Font
    $body.Margin=[Windows.Forms.Padding]::new(0,0,0,8)
    [void]$layout.Controls.Add($body,0,1)

    # Keep the journal action at the left edge and Close at the right.
    $buttons=New-Object Windows.Forms.TableLayoutPanel
    $buttons.Name='rc1-help-buttons'
    $buttons.Dock=[Windows.Forms.DockStyle]::Fill
    $buttons.ColumnCount=2
    $buttons.RowCount=1
    [void]$buttons.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$buttons.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,96))
    $buttons.Padding=[Windows.Forms.Padding]::new(0,8,0,0)
    $buttons.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
    $showJournal=New-Object RdcModalButton
    $showJournal.AmbientShadow=[bool]$OwnerGui
    $showJournal.Name='rc1-help-show-journal'
    $showJournal.Text=(Get-RdcOwnerDialogText 'help.dialog.showJournal' 'Показать журнал')
    $showJournal.AccessibleName=(Get-RdcOwnerDialogText 'help.dialog.showJournalAccessible' 'Показать журнал событий')
    $showJournal.Size=[Drawing.Size]::new(160,34)
    $showJournal.Margin=[Windows.Forms.Padding]::new(0)
    # Owner journal access follows the authenticated Host's capability;
    # legacy/non-Owner About can still show its empty journal placeholder.
    $showJournal.Enabled=(-not $OwnerGui) -or [bool]$script:ownerJournalAllowed
    $showJournal.Add_Click({
        param($sender,$e)
        Show-RdcOwnerJournal ($sender.FindForm())
    })
    $close=New-Object RdcModalButton
    $close.AmbientShadow=[bool]$OwnerGui
    $close.Name='rc1-help-close'
    $close.Text=(Get-RdcOwnerDialogText 'help.dialog.close' 'Закрыть')
    $close.Size=[Drawing.Size]::new(96,34)
    $close.DialogResult=[Windows.Forms.DialogResult]::OK
    $close.Margin=[Windows.Forms.Padding]::new(0)
    [void]$buttons.Controls.Add($showJournal,0,0)
    [void]$buttons.Controls.Add($close,1,0)
    [void]$layout.Controls.Add($buttons,0,2)
    if($OwnerGui){
        # Extend the action row into the existing 24px horizontal gutter.
        # Compensate every other row's margins, retaining body geometry.
        $layout.Padding=[Windows.Forms.Padding]::new(21,20,21,16)
        foreach($child in $layout.Controls){
            if($child -ne $buttons){
                $m=$child.Margin
                $child.Margin=[Windows.Forms.Padding]::new($m.Left+3,$m.Top,$m.Right+3,$m.Bottom)
            }
        }
        $buttons.Padding=[Windows.Forms.Padding]::new(3,8,3,0)
    }
    $dialog.Controls.Add($layout)
    # Same vertical rhythm and maximum client height as the accepted
    # 600x325 Account Switch dialog. Measure the actual wrapped text instead
    # of estimating by character count. Long help scrolls, never clips.
    $measureWidth=[Math]::Max(320,$dialog.ClientSize.Width-80)
    $textFlags=([Windows.Forms.TextFormatFlags]::WordBreak -bor
        [Windows.Forms.TextFormatFlags]::TextBoxControl -bor
        [Windows.Forms.TextFormatFlags]::NoPrefix)
    $measured=[Windows.Forms.TextRenderer]::MeasureText(
        [string]$body.Text,$body.Font,
        [Drawing.Size]::new($measureWidth,10000),$textFlags)
    $neededHeight=$layout.Padding.Top+44+$measured.Height+20+52+$layout.Padding.Bottom
    $dialog.ClientSize=[Drawing.Size]::new(
        $dialog.ClientSize.Width,
        [Math]::Max(220,[Math]::Min(325,$neededHeight)))
    $dialog.AcceptButton=$close
    $dialog.CancelButton=$close
    $dialog.ActiveControl=$close
    return $dialog
}
function Show-RdcOwnerHelp([string]$content) {
    $helpDialog=New-RdcOwnerHelpDialog $content
    try { return $helpDialog.ShowDialog($form) }
    finally { $helpDialog.Dispose() }
}
function Get-RdcOwnerJournalText {
    if($OwnerGui){
        # A dedicated diagnostic report, NOT a copy of the compact activity
        # eventBlocks. All values are from authenticated sanitized Host
        # snapshots; raw Remote stdout/arguments/files must not be loaded.
        $lines=New-Object 'System.Collections.Generic.List[string]'
        [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.title' 'RDC Relay — подробный диагностический журнал'))
        [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.intro' 'Отображаются обезличенные события Host и Remote; сырой stdout и содержимое файлов исключены.'))
        [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.timeNote' 'Время записей истории — получение GUI (UTC), не время выполнения команды.'))
        [void]$lines.Add('')
        [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.sessionHeading' 'СОСТОЯНИЕ СЕАНСА'))
        $remoteState=[string]$script:ownerJournalRemoteState
        if($remoteState -cnotin @('Disconnected','Connecting','AuthPending','Ready','Fault','Reconnecting')){
            $remoteState='Unknown'
        }
        $ownership=[string]$script:ownerJournalOwnership
        if($ownership -cnotin @('Unknown','Owned','Adopted')){$ownership='Unknown'}
        $toolActivity=[string]$script:ownerJournalToolActivity
        if($toolActivity -cnotin @('working','hold','idle')){$toolActivity='unknown'}
        # Trusted allowlist values become user-facing labels; never mutate Host codes.
        $stateLabel=switch -CaseSensitive ($remoteState){
            'Ready' {(Get-RdcOwnerDialogText 'owner.connection.name.ready' 'Подключён');break}
            'Connecting' {(Get-RdcOwnerDialogText 'owner.connection.name.connecting' 'Подключение');break}
            'AuthPending' {(Get-RdcOwnerDialogText 'owner.connection.name.auth' 'Авторизация');break}
            'Reconnecting' {(Get-RdcOwnerDialogText 'owner.connection.name.reconnecting' 'Восстановление');break}
            'Fault' {(Get-RdcOwnerDialogText 'owner.connection.name.fault' 'Ошибка связи');break}
            'Disconnected' {(Get-RdcOwnerDialogText 'owner.connection.name.disconnected' 'Отключён');break}
            default {(Get-RdcOwnerDialogText 'owner.connection.name.unknown' 'Состояние неизвестно')}
        }
        $ownershipLabel=switch -CaseSensitive ($ownership){
            'Owned' {(Get-RdcOwnerDialogText 'journal.owner.ownership.owned' 'управляемый Host');break}
            'Adopted' {(Get-RdcOwnerDialogText 'journal.owner.ownership.adopted' 'наблюдение');break}
            default {(Get-RdcOwnerDialogText 'journal.owner.ownership.unknown' 'неизвестно')}
        }
        $activityLabel=switch -CaseSensitive ($toolActivity){
            'working' {(Get-RdcOwnerDialogText 'journal.owner.activity.working' 'выполняется');break}
            'hold' {(Get-RdcOwnerDialogText 'journal.owner.activity.hold' 'ожидание');break}
            'idle' {(Get-RdcOwnerDialogText 'journal.owner.activity.idle' 'ожидание вызова');break}
            default {(Get-RdcOwnerDialogText 'journal.owner.activity.unknown' 'неизвестно')}
        }
        [void]$lines.Add(
            (Get-RdcOwnerDialogText 'journal.owner.remotePrefix' 'Remote: ')+$stateLabel+
            (Get-RdcOwnerDialogText 'journal.owner.modePrefix' ' | Режим: ')+$ownershipLabel+
            (Get-RdcOwnerDialogText 'journal.owner.activityPrefix' ' | Активность: ')+$activityLabel)
        if([int]$script:ownerJournalRemotePid -gt 0){
            [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.processPrefix' 'Процесс Remote: PID ')+[int]$script:ownerJournalRemotePid)
        }
        if($script:ownerJournalLastSnapshotUtc -is [DateTime] -and
           $script:ownerJournalLastSnapshotUtc -gt [DateTime]::MinValue){
            [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.snapshotPrefix' 'Последний снимок Host: ')+
                $script:ownerJournalLastSnapshotUtc.ToUniversalTime().ToString(
                 'yyyy-MM-dd HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)+' UTC')
        }
        [void]$lines.Add('')
        # Revalidate only fixed fields from the authenticated attempt snapshot.
        # Never open Last unsuccessful sessions.log: that file contains private raw bytes.
        $attemptLines=New-Object 'System.Collections.Generic.List[string]'
        $fileState='(missing|unknown|not_file|present)'
        $nodeState='(missing|unknown|not_file|present\(version_unknown\)|(present|unsupported)\([0-9]{1,10}(\.[0-9]{1,10}){3}\))'
        $runtimePattern='\Aruntime (ProgramFiles|AppDataNpm|ProgramFilesX86): (check_unknown|node='+$nodeState+' npm='+$fileState+' npx='+$fileState+'|npm-cli='+$fileState+' npx-cli='+$fileState+')\z'
        $fixedPattern='\A(attempt_phase=(startup_observation|completed|preflight_failed|launch_failed)|completion_kind=(unknown|preflight_failed|launch_failed|exit_before_ready|startup_stop_requested|authorization_stop_requested|stop_requested_after_ready|unexpected_after_ready)|preflight_reason=(none|runtime_unavailable|inspection_failed)|cmd_exit=(unknown|-?[0-9]{1,10})|(stop_requested|accepted_session|auth_pending_observed|eof|read_fault|storage_fault|parser_fault)=(yes|no|unknown)|(capture_read|write_ack|retained|parser_pending)=(unknown|[0-9]{1,19})|prerequisite_observations=unknown)\z'
        $packagePattern='\Aruntime (ProgramFiles|AppDataNpm|ProgramFilesX86): npm_package=(missing|unknown|not_file|present\(version_unknown\)|present\([0-9]{1,9}(\.[0-9]{1,9}){2}\))\z'
        $systemPattern='\A(windows_version=(unknown|[0-9]{1,10}(\.[0-9]{1,10}){2}) native_arch=(unknown|x86|x64|arm64|arm) host_bits=(32|64)|remote_requested=(0\.2\.52|latest) remote_actual_version=unknown|relay_version=[0-9]{1,9}(\.[0-9]{1,9}){2}( RC[1-9][0-9]*)? relay_mode=(installed|portable|unknown)|runtime_selected=(ProgramFiles|AppDataNpm|ProgramFilesX86))\z'
        foreach($entry in @($script:ownerAttemptDiagnostics | Select-Object -First 30)){
            if($entry -is [string] -and $entry.Length -le 120 -and
                ($entry -cmatch $fixedPattern -or $entry -cmatch $runtimePattern -or
                 $entry -cmatch $packagePattern -or $entry -cmatch $systemPattern)){
                [void]$attemptLines.Add($entry)
            }
        }
        if($attemptLines.Count -gt 0){
            [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.attemptHeading' 'ДИАГНОСТИКА ТЕКУЩЕЙ ИЛИ ПОСЛЕДНЕЙ ПОПЫТКИ (данные Host)'))
            foreach($entry in $attemptLines){[void]$lines.Add('  • '+$entry)}
            [void]$lines.Add('')
        }
        [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.diagHeading' 'ДИАГНОСТИКА HOST (последние доступные записи)'))
        $diagCount=0
        foreach($entry in @($script:ownerRecentDiagnostics)){
            $value=[string]$entry
            if(-not [string]::IsNullOrWhiteSpace($value) -and
               $value.Length -le 140 -and
               $value -notmatch '[\r\n\x00-\x1F]' -and
               $value -notmatch '(?i)([A-Za-z]:\\|\\\\|https?://|@|secret|password|token|credential|private[_-]?key)'){
                switch -Regex ($value){
                    '^remote: managed log recovery pending:' {$value=Get-RdcOwnerDialogText 'journal.owner.rawRecoveryPending' 'Восстановление сохранённых логов ещё не завершено.';break}
                    '^remote: managed log finalization pending:' {$value=Get-RdcOwnerDialogText 'journal.owner.rawFinalizePending' 'Завершение записи логов ещё не подтверждено.';break}
                    '^remote: managed log stream unavailable$' {$value=Get-RdcOwnerDialogText 'journal.owner.rawStreamUnavailable' 'Поток исходного лога недоступен.';break}
                    '^remote: raw log storage unavailable$' {$value=Get-RdcOwnerDialogText 'journal.owner.rawStorageUnavailable' 'Не удалось сохранить исходный лог.';break}
                    '^remote: log session acceptance failed:' {$value=Get-RdcOwnerDialogText 'journal.owner.rawSessionFailure' 'Не удалось подтвердить сохранение сессии логов.';break}
                }
                [void]$lines.Add('  • '+$value)
                $diagCount++
            }
        }
        if($diagCount -eq 0){[void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.noDiagnostics' '  Нет доступных диагностических записей.'))}
        [void]$lines.Add('')
        [void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.historyHeading' 'ИСТОРИЯ СОБЫТИЙ (до 512 последних записей текущего окна)'))
        $historyCount=0
        foreach($entry in @($script:ownerDetailedJournal)){
            if(-not [string]::IsNullOrWhiteSpace([string]$entry)){
                [void]$lines.Add([string]$entry)
                $historyCount++
            }
        }
        if($historyCount -eq 0){[void]$lines.Add((Get-RdcOwnerDialogText 'journal.owner.noEvents' '  Событий пока нет.'))}
        return [string]::Join([Environment]::NewLine,$lines)
    }
    # Legacy view retains its historical bounded activity journal.
    $items=New-Object System.Collections.Generic.List[string]
    if($script:eventBlocks){
        foreach($entry in $script:eventBlocks){
            if(-not [string]::IsNullOrWhiteSpace([string]$entry)){
                [void]$items.Add(([string]$entry).TrimEnd())
            }
        }
    }
    if(-not [string]::IsNullOrWhiteSpace([string]$script:currentEvent)){
        [void]$items.Add(([string]$script:currentEvent).TrimEnd())
    }
    if($items.Count -eq 0){
            if($OwnerGui){return (Get-RdcOwnerDialogText 'journal.owner.empty' 'Журнал пока пуст.')}
            return 'Журнал пока пуст.'
        }
    return [string]::Join([Environment]::NewLine,$items)
}
# Export only the same sanitized report that is already visible in the
# diagnostic window. No automatic file creation or private Remote log access.
function Write-RdcOwnerJournalTxtFile([string]$path,[string]$content) {
    # Only the validated, already sanitized journal snapshot is exportable.
    if([string]::IsNullOrWhiteSpace($content) -or $content.Length -gt 400000){
        throw 'RC1_JOURNAL_EXPORT_BOUNDARY'
    }
    $filePath=[IO.Path]::GetFullPath($path)
    if([IO.Path]::GetExtension($filePath) -ine '.txt'){throw 'RC1_JOURNAL_TXT_ONLY'}
    if([IO.File]::Exists($filePath) -and
       (([IO.File]::GetAttributes($filePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'RC1_JOURNAL_EXPORT_REPARSE_DENIED'
    }
    [IO.File]::WriteAllText($filePath,$content,(New-Object Text.UTF8Encoding($true)))
}
function Save-RdcOwnerJournalTxt([Windows.Forms.Form]$parent,[string]$content) {
    if([string]::IsNullOrWhiteSpace($content) -or $content.Length -gt 400000){
        throw 'RC1_JOURNAL_EXPORT_BOUNDARY'
    }
    $picker=New-Object Windows.Forms.SaveFileDialog
    try {
        $picker.Title=(Get-RdcOwnerDialogText 'journal.owner.saveTitle' 'Сохранить журнал RDC Relay')
        $picker.Filter=(Get-RdcOwnerDialogText 'journal.owner.saveFilter' 'Текстовый документ (*.txt)|*.txt')
        $picker.DefaultExt='txt'
        $picker.AddExtension=$true
        $picker.OverwritePrompt=$true
        $picker.FileName='RDC-Relay-journal-'+
            [DateTime]::Now.ToString('yyyyMMdd-HHmmss',[Globalization.CultureInfo]::InvariantCulture)+'.txt'
        if($picker.ShowDialog($parent) -ne [Windows.Forms.DialogResult]::OK){return}
        Write-RdcOwnerJournalTxtFile $picker.FileName $content
    }finally{$picker.Dispose()}
}
# Explicit owner action: open a byte-for-byte local snapshot, not sanitized
# IPC data. The running Host's original log must never be edited by Notepad.
function Get-RdcOwnerRawLogPath {
    param([switch]$All)
    if(-not $OwnerGui -or -not $script:ownerManagedMode -or
       -not $script:ownerRawLogRunRoot){return $null}
    $run=[IO.Path]::GetFullPath([string]$script:ownerRawLogRunRoot)
    if([IO.Path]::GetFileName($run) -cnotmatch '^run-[0-9a-f]{32}$' -or
       -not [IO.Directory]::Exists($run)){return $null}
    $check=$run
    while($check){
        if(([IO.File]::GetAttributes($check) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'RDC_RAW_LOG_REPARSE_REFUSED'
        }
        $parent=[IO.Path]::GetDirectoryName($check)
        if(-not $parent -or $parent -ceq $check){break}
        $check=$parent
    }
    $logs=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($run))) 'Logs'
    if([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($run)) -ceq '1.6.0-RC1' -and [IO.Directory]::Exists($logs)){
        if(([IO.File]::GetAttributes($logs) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RDC_RAW_LOG_REPARSE_REFUSED'}
        $files=@()
        foreach($session in @('CurrentSession','PreviousSession')){
            $folder=Join-Path $logs $session
            if(-not [IO.Directory]::Exists($folder)){continue}
            if(([IO.File]::GetAttributes($folder) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RDC_RAW_LOG_REPARSE_REFUSED'}
            $identity=Join-Path $folder '.rdc-session-v1'
            if(-not [IO.File]::Exists($identity)){continue}
            $info=Get-Item -LiteralPath $identity -Force -ErrorAction Stop
            if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $info.Length -ne 51){throw 'RDC_RAW_LOG_SESSION_MARKER'}
            $id=[IO.File]::ReadAllText($identity,[Text.Encoding]::ASCII)
            if($id -cnotmatch '^RDC-LOG-SESSION-V1:[0-9a-f]{32}$'){throw 'RDC_RAW_LOG_SESSION_MARKER'}
            if($session -ceq 'PreviousSession'){
                $accepted=Join-Path $folder '.rdc-accepted-v1'
                $proof=Get-Item -LiteralPath $accepted -Force -ErrorAction Stop
                if(($proof.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $proof.Length -ne $info.Length -or [IO.File]::ReadAllText($accepted,[Text.Encoding]::ASCII) -cne $id){throw 'RDC_RAW_LOG_SESSION_MARKER'}
            }
            $files+=@(Get-ChildItem -LiteralPath $folder -File -Filter '*.log' -ErrorAction Stop |
                Where-Object{$_.Name -cmatch '^\d{4}-\d{2}-\d{2}_part-[0-9]{3,10}\.log$' -and
                    $_.Length -le 10MB -and ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0} |
                Sort-Object CreationTimeUtc,LastWriteTimeUtc,Name -Descending)
        }
        if($All){return @($files|ForEach-Object{$_.FullName})}
        if($files.Count){return $files[0].FullName}
        return $null
    }
    $file=Get-ChildItem -LiteralPath $run -File -Filter 'remote-*.log' -ErrorAction Stop |
        Where-Object{$_.Name -cmatch '^remote-[0-9a-f]{32}\.log$' -and
            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0} |
        Sort-Object CreationTimeUtc,LastWriteTimeUtc,Name -Descending |
        Select-Object -First 1
    if($file){return $file.FullName}
    return $null
}
function Copy-RdcOwnerRawLogSnapshot([string]$source,[string]$destination) {
    # Read up to the length observed at open. A busy Remote can keep appending;
    # never chase its unbounded tail, transcode, sanitize or rewrite its bytes.
    foreach($path in @($source,$destination)){
        $cursor=[IO.Path]::GetFullPath($path)
        while($cursor){
            if(([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)) -and
               ([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RDC_RAW_LOG_REPARSE_REFUSED'}
            $cursor=[IO.Path]::GetDirectoryName($cursor)
        }
    }
    $inputStream=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $created=$false
    try{
        $remaining=$inputStream.Length
        if([IO.Path]::GetFileName($source) -cmatch '^\d{4}-\d{2}-\d{2}_part-\d+\.log$' -and $remaining -gt 10MB){throw 'RDC_RAW_LOG_PART_LIMIT'}
        $outputStream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $created=$true
        try{
            $buffer=New-Object byte[] 65536
            while($remaining -gt 0){
                $n=$inputStream.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length))
                if($n -le 0){throw 'RDC_RAW_LOG_CHANGED_DURING_COPY'}
                $outputStream.Write($buffer,0,$n)
                $remaining-=$n
            }
        }finally{$outputStream.Dispose()}
    }catch{
        if($created){[IO.File]::Delete($destination)}
        throw
    }finally{$inputStream.Dispose()}
}
function Open-RdcOwnerRawLog([Windows.Forms.Form]$parent) {
    try{
        $available=@(Get-RdcOwnerRawLogPath -All | Where-Object{$_})
        $source=$available|Select-Object -First 1
        if(-not $source){
            [void][Windows.Forms.MessageBox]::Show($parent,
                (Get-RdcOwnerDialogText 'journal.owner.rawUnavailable' 'Исходный лог Remote пока недоступен.'),
                'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
            return
        }
        if([IO.Path]::GetFileName($source) -cmatch '^\d{4}-\d{2}-\d{2}_part-\d+\.log$'){
            $picker=New-Object Windows.Forms.OpenFileDialog
            try{
                $picker.Title=Get-RdcOwnerDialogText 'journal.owner.rawSelect' 'Выберите часть лога'
                $picker.Filter=(Get-RdcOwnerDialogText 'journal.owner.rawFilter' 'Файлы логов (*.log)')+'|*.log'
                $picker.InitialDirectory=[IO.Path]::GetDirectoryName($source)
                $picker.FileName=[IO.Path]::GetFileName($source)
                $picker.CheckFileExists=$true;$picker.Multiselect=$false;$picker.RestoreDirectory=$true
                if($picker.ShowDialog($parent) -ne [Windows.Forms.DialogResult]::OK){return}
                $source=[IO.Path]::GetFullPath($picker.FileName)
                if(@(Get-RdcOwnerRawLogPath -All) -cnotcontains $source){throw 'RDC_RAW_LOG_SELECTION_REFUSED'}
            }finally{$picker.Dispose()}
        }
        # Bounded temporary copy pool. Never delete an editable copy behind
        # the user's back; after four copies, explicitly export the next one.
        $pool=Join-Path ([IO.Path]::GetTempPath()) 'RDC-Relay-LogViewer-v1'
        $cursor=[IO.Path]::GetFullPath($pool)
        while($cursor){
            if(([IO.Directory]::Exists($cursor) -or [IO.File]::Exists($cursor)) -and
                ([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RDC_RAW_LOG_REPARSE_REFUSED'}
            $cursor=[IO.Path]::GetDirectoryName($cursor)
        }
        [void][IO.Directory]::CreateDirectory($pool)
        $lockPath=Join-Path $pool '.snapshot-lock-v1'
        if([IO.File]::Exists($lockPath) -and ([IO.File]::GetAttributes($lockPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'RDC_RAW_LOG_REPARSE_REFUSED'}
        $lease=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $copy=$null;$copied=$false;$automatic=$false
        try{
            $count=0;$total=0L
            foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($pool)){
                if([IO.Path]::GetFileName($entry) -ceq '.snapshot-lock-v1'){continue}
                $attr=[IO.File]::GetAttributes($entry)
                if(($attr -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) -ne 0 -or
                    [IO.Path]::GetFileName($entry) -cnotmatch '^RDC-Relay-Remote-[0-9a-f]{32}\.log$'){throw 'RDC_RAW_LOG_SNAPSHOT_POOL_FOREIGN'}
                $count++;$total+=[IO.FileInfo]::new($entry).Length
                if($count -gt 4){throw 'RDC_RAW_LOG_SNAPSHOT_POOL_LIMIT'}
            }
            $length=[IO.FileInfo]::new($source).Length
            if($count -lt 4 -and $length -le 10MB -and $total -le (40MB-10MB)){
                $copy=Join-Path $pool ('RDC-Relay-Remote-'+[Guid]::NewGuid().ToString('N')+'.log')
                $automatic=$true
            }else{
                $save=New-Object Windows.Forms.SaveFileDialog
                try{
                    $save.Title=Get-RdcOwnerDialogText 'journal.owner.rawSaveCopy' 'Сохранить копию лога'
                    $save.Filter=(Get-RdcOwnerDialogText 'journal.owner.rawFilter' 'Файлы логов (*.log)')+'|*.log'
                    $save.FileName=[IO.Path]::GetFileName($source)
                    $save.OverwritePrompt=$true;$save.RestoreDirectory=$true
                    if($save.ShowDialog($parent) -ne [Windows.Forms.DialogResult]::OK){return}
                    $copy=[IO.Path]::GetFullPath($save.FileName)
                    $logRoot=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName([string]$script:ownerRawLogRunRoot))) 'Logs'
                    foreach($protected in @($pool,$logRoot,[string]$script:ownerRawLogRunRoot)){
                        if($copy.StartsWith($protected.TrimEnd([char]92)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'RDC_RAW_LOG_EXPORT_BOUNDARY'}
                    }
                }finally{$save.Dispose()}
            }
            Copy-RdcOwnerRawLogSnapshot $source $copy
            $copied=$true
            $viewer=Join-Path ([Environment]::SystemDirectory) 'notepad.exe'
            Start-Process -FilePath $viewer -ArgumentList ('"'+$copy+'"') -ErrorAction Stop
        }catch{
            if($copied -and $automatic){[IO.File]::Delete($copy)}
            throw
        }finally{$lease.Dispose()}
    }catch{
        [void][Windows.Forms.MessageBox]::Show($parent,
            (Get-RdcOwnerDialogText 'journal.owner.rawError' 'Не удалось открыть исходный лог Remote.'),
            'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
    }
}
function New-RdcOwnerJournalDialog([string]$content) {
    $dialog=New-Object Windows.Forms.Form
    $dialog.Name='rc1-journal-dialog'
    $dialog.Text=(Get-RdcOwnerDialogText 'journal.owner.dialogTitle' 'RDC Relay - Журнал')
    $dialog.StartPosition=[Windows.Forms.FormStartPosition]::CenterParent
    $dialog.FormBorderStyle=[Windows.Forms.FormBorderStyle]::Sizable
    # Preserve the usable 520x280 minimum while allowing whole-form grip resize.
    $dialog.MinimumSize=[Drawing.Size]::new(520,280)
    $dialog.ClientSize=[Drawing.Size]::new(740,440)
    $dialog.ShowInTaskbar=$false
    $dialog.MaximizeBox=$true
    $dialog.MinimizeBox=$false
    $dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Font
    $dialog.Font=[Drawing.Font]::new('Segoe UI',10)
    $dialog.BackColor=[Drawing.Color]::FromArgb(29,32,36)
    $dialog.ForeColor=[Drawing.Color]::Gainsboro
    $dialog.Tag=$content # immutable snapshot, used solely by explicit Save TXT
    # Main window rhythm: header / purple rail / dark RichEdit / footer.
    $layout=New-Object Windows.Forms.TableLayoutPanel
    $layout.Name='rc1-journal-layout'
    $layout.Dock=[Windows.Forms.DockStyle]::Fill
    $layout.Margin=[Windows.Forms.Padding]::new(0)
    $layout.Padding=[Windows.Forms.Padding]::new(0)
    $layout.BackColor=$dialog.BackColor
    $layout.ColumnCount=1
    $layout.RowCount=4
    [void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,52))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,1))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,62))
    $headingHost=New-Object Windows.Forms.Panel
    $headingHost.Name='rc1-journal-heading-panel'
    $headingHost.Dock=[Windows.Forms.DockStyle]::Fill
    $headingHost.Margin=[Windows.Forms.Padding]::new(0)
    $headingHost.BackColor=$dialog.BackColor
    $heading=New-Object Windows.Forms.Label
    $heading.Name='rc1-journal-heading'
    $heading.Text=(Get-RdcOwnerDialogText 'journal.owner.heading' 'Журнал')
    $heading.Font=[Drawing.Font]::new('Segoe UI',12,[Drawing.FontStyle]::Bold)
    $heading.ForeColor=$dialog.ForeColor
    $heading.AutoSize=$true
    $heading.Location=[Drawing.Point]::new(20,14)
    [void]$headingHost.Controls.Add($heading)
    [void]$layout.Controls.Add($headingHost,0,0)
    $rail=New-Object Windows.Forms.Panel
    $rail.Name='rc1-journal-purple-rail'
    $rail.Dock=[Windows.Forms.DockStyle]::Fill
    $rail.Margin=[Windows.Forms.Padding]::new(0)
    $rail.BackColor=[Drawing.Color]::FromArgb(123,95,162)
    [void]$layout.Controls.Add($rail,0,1)
    $textHost=New-Object RdcBufferedPanel
    $textHost.Name='rc1-journal-text-host'
    $textHost.Dock=[Windows.Forms.DockStyle]::Fill
    $textHost.Margin=[Windows.Forms.Padding]::new(0)
    $textHost.Padding=[Windows.Forms.Padding]::new(0)
    $textHost.BackColor=[Drawing.Color]::FromArgb(18,20,23)
    $body=New-Object RdcLogBox
    $body.Name='rc1-journal-content'
    $body.Text=$content
    $body.ReadOnly=$true
    $body.WordWrap=$false
    $body.DetectUrls=$false
    $body.ShortcutsEnabled=$true
    $body.JournalNativeInteraction=$true
    $body.HideSelection=$false
    $body.TabStop=$true
    $body.ScrollBars=[Windows.Forms.RichTextBoxScrollBars]::None
    $body.BorderStyle=[Windows.Forms.BorderStyle]::None
    $body.BackColor=$textHost.BackColor
    $body.ForeColor=[Drawing.Color]::Gainsboro
    $body.Font=[Drawing.Font]::new($script:ownerTextFontFamily,10)
    $body.Dock=[Windows.Forms.DockStyle]::None
    $body.Margin=[Windows.Forms.Padding]::new(0)
    $body.AccessibleName=(Get-RdcOwnerDialogText 'journal.owner.contentAccessible' 'Диагностический журнал RDC Relay')
    # Full document affordances: select lines with the pointer, Ctrl+C,
    # and an explicit context menu. Tag pins this journal's RichEdit for clicks.
    $journalMenu=New-Object Windows.Forms.ContextMenuStrip
    $journalMenu.Name='rc1-journal-context'
    $journalMenu.Tag=$body # stable source even after ToolStrip closes
    $copyItem=New-Object Windows.Forms.ToolStripMenuItem((Get-RdcOwnerDialogText 'journal.owner.copy' 'Копировать'))
    $copyItem.Name='rc1-journal-copy'
    $copyItem.Add_Click({
        param($sender,$e)
        $editor=$sender.Owner.Tag
        if($editor -is [Windows.Forms.RichTextBox] -and $editor.SelectionLength -gt 0){
            $editor.Copy()
        }
    })
    $selectAllItem=New-Object Windows.Forms.ToolStripMenuItem((Get-RdcOwnerDialogText 'journal.owner.selectAll' 'Выделить всё'))
    $selectAllItem.Name='rc1-journal-select-all'
    $selectAllItem.Add_Click({
        param($sender,$e)
        $editor=$sender.Owner.Tag
        if($editor -is [Windows.Forms.RichTextBox]){$editor.SelectAll()}
    })
    [void]$journalMenu.Items.Add($copyItem)
    [void]$journalMenu.Items.Add($selectAllItem)
    $journalMenu.Add_Opening({
        param($sender,$e)
        $editor=$sender.Tag
        $sender.Items['rc1-journal-copy'].Enabled=(
            $editor -is [Windows.Forms.RichTextBox] -and $editor.SelectionLength -gt 0)
    })
    $body.ContextMenuStrip=$journalMenu
    $body.Add_Disposed({
        param($sender,$e)
        $menu=$sender.ContextMenuStrip
        if($menu -and -not $menu.IsDisposed){$menu.Dispose()}
    })
    $journalVScroll=New-Object RdcOverlayScrollBar
    $journalVScroll.Name='rc1-journal-vscroll'
    $journalVScroll.Target=$body
    $journalVScroll.Vertical=$true
    $journalVScroll.Dock=[Windows.Forms.DockStyle]::None
    $journalVScroll.Margin=[Windows.Forms.Padding]::new(0)
    $journalHScroll=New-Object RdcOverlayScrollBar
    $journalHScroll.Name='rc1-journal-hscroll'
    $journalHScroll.Target=$body
    $journalHScroll.Vertical=$false
    $journalHScroll.Dock=[Windows.Forms.DockStyle]::None
    $journalHScroll.Margin=[Windows.Forms.Padding]::new(0)
    # Native-looking scroll-corner artwork; dragging now resizes the entire
    # journal Form, not just the text pane or the main activity divider.
    $journalCorner=New-Object RdcJournalScrollGrip
    $journalCorner.Name='rc1-journal-scroll-corner'
    $journalCorner.Dock=[Windows.Forms.DockStyle]::None
    $journalCorner.Margin=[Windows.Forms.Padding]::new(0)
    # RdcJournalScrollGrip uses the exact main-panel grip painter.
    [void]$textHost.Controls.Add($body)
    [void]$textHost.Controls.Add($journalVScroll)
    [void]$textHost.Controls.Add($journalHScroll)
    [void]$textHost.Controls.Add($journalCorner)
    # Identical 17px overlays and RichEdit viewport geometry as the main
    # activity pane. Resolve controls from the sender so the resize handler
    # works after New-RdcOwnerJournalDialog has returned.
    $textHost.Add_Resize({
        param($sender,$e)
        $b=$sender.Controls['rc1-journal-content']
        $v=$sender.Controls['rc1-journal-vscroll']
        $h=$sender.Controls['rc1-journal-hscroll']
        $c=$sender.Controls['rc1-journal-scroll-corner']
        if(-not $b -or -not $v -or -not $h -or -not $c){return}
        $w=[Math]::Max(17,$sender.ClientSize.Width)
        $height=[Math]::Max(17,$sender.ClientSize.Height)
        $contentW=[Math]::Max(0,$w-17)
        $contentH=[Math]::Max(0,$height-17)
        $sender.SuspendLayout()
        try {
            $b.SetBounds(0,0,$contentW,$contentH)
            $v.SetBounds($contentW,0,17,$contentH)
            $h.SetBounds(0,$contentH,$contentW,17)
            $c.SetBounds($contentW,$contentH,17,17)
        }finally{$sender.ResumeLayout($false)}
        $v.Invalidate()
        $h.Invalidate()
    })
    $body.Add_ScrollActivity({
        param($sender,$e)
        if($sender.Parent){
            $v=$sender.Parent.Controls['rc1-journal-vscroll']
            $h=$sender.Parent.Controls['rc1-journal-hscroll']
            if($v){$v.Invalidate()}
            if($h){$h.Invalidate()}
        }
    })
    [void]$layout.Controls.Add($textHost,0,2)
    # Main-window style: no lower text/footer accent divider or 1px spacer.
    # The footer follows the text area directly.
    $footer=New-Object Windows.Forms.TableLayoutPanel
    $footer.Name='rc1-journal-footer'
    $footer.Dock=[Windows.Forms.DockStyle]::Fill
    $footer.BackColor=$dialog.BackColor
    $footer.ColumnCount=if($OwnerGui){3}else{2}
    $footer.RowCount=1
    $footer.Margin=[Windows.Forms.Padding]::new(0)
    $footer.Padding=[Windows.Forms.Padding]::new(20,13,20,11)
    if($OwnerGui){
        [void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,156))
    }
    [void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,100))
    if($OwnerGui){
        $openRaw=New-Object RdcModalButton
        $openRaw.AmbientShadow=[bool]$OwnerGui
        $openRaw.Name='rc1-journal-open-raw-log'
        $openRaw.Text=(Get-RdcOwnerDialogText 'journal.owner.openRaw' 'Открыть лог')
        $openRaw.AccessibleDescription=(Get-RdcOwnerDialogText 'journal.owner.rawDescription' 'Выбирает часть исходного лога Remote и открывает её локальную копию. Сохраните свою копию отдельно.')
        $openRaw.Size=[Drawing.Size]::new(148,34)
        $openRaw.Margin=[Windows.Forms.Padding]::new(0)
        $openRaw.Add_Click({
            param($sender,$e)
            Open-RdcOwnerRawLog ($sender.FindForm())
        })
        [void]$footer.Controls.Add($openRaw,0,0)
    }
    $save=New-Object RdcModalButton
    $save.AmbientShadow=[bool]$OwnerGui
    $save.Name='rc1-journal-save-txt'
    $save.Text=(Get-RdcOwnerDialogText 'journal.owner.saveButton' 'Сохранить TXT')
    $save.Size=[Drawing.Size]::new(148,34)
    $save.Margin=[Windows.Forms.Padding]::new(0)
    $save.Add_Click({
        param($sender,$e)
        # PowerShell reserves $Host (case-insensitive) as a read-only automatic variable.
        $journalForm=$sender.FindForm()
        try { Save-RdcOwnerJournalTxt $journalForm ([string]$journalForm.Tag) }
        catch {
            [void][Windows.Forms.MessageBox]::Show($journalForm,
              (Get-RdcOwnerDialogText 'journal.owner.saveError' 'Не удалось сохранить журнал. Проверьте выбранную папку.'),
              'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,
              [Windows.Forms.MessageBoxIcon]::Warning)
        }
    })
    $close=New-Object RdcModalButton
    $close.AmbientShadow=[bool]$OwnerGui
    $close.Name='rc1-journal-close'
    $close.Text=(Get-RdcOwnerDialogText 'journal.owner.closeButton' 'Закрыть')
    $close.Size=[Drawing.Size]::new(96,34)
    $close.DialogResult=[Windows.Forms.DialogResult]::OK
    $close.Margin=[Windows.Forms.Padding]::new(0)
    [void]$footer.Controls.Add($save,$(if($OwnerGui){1}else{0}),0)
    [void]$footer.Controls.Add($close,$(if($OwnerGui){2}else{1}),0)
    [void]$layout.Controls.Add($footer,0,3)
    $dialog.Controls.Add($layout)
    $dialog.PerformLayout()
    $layout.PerformLayout()
    $textHost.PerformLayout()
    $dialog.AcceptButton=$close
    $dialog.CancelButton=$close
    $dialog.ActiveControl=$body
    return $dialog
}
function Show-RdcOwnerJournal([Windows.Forms.Form]$parent) {
    $snapshot=Get-RdcOwnerJournalText
    $journal=New-RdcOwnerJournalDialog $snapshot
    try { return $journal.ShowDialog($parent) }
    finally { $journal.Dispose() }
}

function Show-RdcAbout {
    $helpText =
        'RDC Relay v' + $appVersion + $nl + $nl +
        'О программе' + $nl +
        'Графическая оболочка для Desktop Commander Remote. Remote-процесс работает скрыто, ' +
        'а его состояние и журнал отображаются в этом окне.' + $nl + $nl +
        'Управление' + $nl +
        '• «Остановить» — останавливает remote-процесс; после остановки кнопка становится «Запустить».' + $nl +
        '• «Аккаунт» — смена аккаунта, переподключение и управление устройствами.' + $nl +
        '• Крестик окна завершает remote-процесс вместе с оболочкой.' + $nl + $nl +
        'Аккаунты' + $nl +
        'Компьютер и Desktop Commander в ChatGPT должны быть авторизованы в одном и том же аккаунте. ' +
        'Если аккаунты различаются, ChatGPT не увидит этот компьютер.' + $nl + $nl +
        'При выборе «Сменить аккаунт…» текущее remote-соединение будет остановлено, ' +
        'выполнен штатный выход и запущена новая браузерная авторизация.' + $nl + $nl +
        'Для добавления устройства достаточно установить RDC Relay и запустить его: ' +
        'команду npx с сайта копировать в терминал не требуется. ' +
        'При первой авторизации подтвердите устройство в браузере, сверив код из журнала. ' +
        'Повторные запуски обычно используют сохранённую сессию. ' + $nl + $nl +
        'Пароли и токены эта оболочка не копирует и не хранит.'
    if ($OwnerGui) {
        if($script:ownerObservedMode){
            $helpText = 'RDC Relay 1.6.0 RC1' + $nl + $nl +
              'Найден уже работающий Desktop Commander Remote. Приложение показывает его состояние, не прерывая подключение.' + $nl + $nl +
              'Закрытие окна закрывает только GUI; Host и Remote продолжают работать.' + $nl +
              'Повторное открытие через трей восстанавливает состояние и журнал.' + $nl +
              'Полное завершение RDC Relay через трей не отключает ранее запущенный Remote.'
        }elseif($script:ownerManagedMode){
            $helpText = 'RDC Relay 1.6.0 RC1' + $nl + $nl +
              'Host запускает Desktop Commander Remote (latest).' + $nl + $nl +
              'Закрытие окна закрывает только GUI; Host и Remote продолжают работать.' + $nl +
              'Повторное открытие через трей восстанавливает состояние и журнал.' + $nl +
              'Статистику вызовов при необходимости можно подключить повторно в меню «Аккаунт».'
        }else{
            $helpText = 'RDC Relay 1.6.0 RC1' + $nl + $nl +
              'Режим проверки: Desktop Commander Remote не подключён.' + $nl +
              'Закрытие окна закрывает только GUI; Host продолжает работать.' + $nl +
              'Повторное открытие через трей восстанавливает состояние и журнал.'
        }
        # Locale is presentation-only: translate complete mode-specific help content
        # after choosing the existing trusted Owner mode, never by Host/IPC text.
        $helpKey=if($script:ownerObservedMode){'help.owner.observed'
        }elseif($script:ownerManagedMode){'help.owner.managed'}else{'help.owner.fake'}
        $helpText=(Get-RdcOwnerDialogText $helpKey $helpText).Replace('{nl}',$nl)
        # Diagnostics belong in About, not the compact RC1 footer.
        $helpPid=if([int]$script:ownerRemotePid -gt 0){[string][int]$script:ownerRemotePid}else{'—'}
        $helpText += $nl + $nl + 'PID Remote: ' + $helpPid
    }
    if ($OwnerGui) {
        [void](Show-RdcOwnerHelp $helpText)
    }else{
        [Windows.Forms.MessageBox]::Show(
            $helpText,
            'RDC Relay — справка',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
}
function Refresh-Window {
    if ($OwnerGui) { return }
    if ($script:initializing) { Complete-RuntimeInitialization; return }
    if ($script:remoteOperation) { Update-RemoteOperation; return }
    Apply-SystemFrameTheme
    if ($script:enableUpdateNotice) { Update-RdcUpdateNoticePolling }

    if ($script:uiInteracting -or $vScroll.IsDragging -or $hScroll.IsDragging) {
        return
    }

    Read-LiveLog
    Refresh-DividerActivitySession

    $now = Get-Date

    if (
        $script:proc -and
        -not $script:proc.HasExited -and
        -not $script:remoteReady -and
        -not $script:remoteInteractiveAuth -and
        $script:remoteConnectDeadline -and
        $now -ge $script:remoteConnectDeadline
    ) {
        # A missed readiness deadline is not itself evidence that the transport failed.
        $script:remoteConnectDeadline = $null
    }

    if ($script:autoReconnectAt -and $now -ge $script:autoReconnectAt) {
        Invoke-AutoReconnect
        if ($script:remoteOperation) { return }
        Read-LiveLog
    }

    if ($script:proc) {
        $script:proc.Refresh()

        if (-not $script:proc.HasExited) {
            $elapsed = $now - $script:startTime
            Set-RuntimeDisplay (
                'PID ' + $script:proc.Id
            ) (
                'Время работы {0:hh\:mm\:ss}' -f $elapsed
            ) $true

            if (-not $script:stopping) {
                if ($script:remoteFaultLatched) {
                    $faultDetail = $script:remoteFaultReason
                    if ($script:autoReconnectAt) {
                        $left = [Math]::Max(
                            0.0,
                            ($script:autoReconnectAt - $now).TotalSeconds
                        )
                        $faultDetail += ' Повтор через ' +
                            [Math]::Ceiling($left) + ' с.'
                    }
                    Set-State 'Проблема связи' $faultDetail ([Drawing.Color]::LightCoral)
                }
                elseif ($script:remoteInteractiveAuth) {
                    Set-State (
                        'Ожидание авторизации…'
                    ) (
                        'Подтвердите устройство в браузере; код — в журнале выше. Команды в терминале не нужны.'
                    ) ([Drawing.Color]::Khaki)
                }
                elseif ($script:remoteReady) {
                    Set-State (
                        'Работает'
                    ) (
                        'Remote MCP подключён и готов принимать задачи.'
                    ) ([Drawing.Color]::LightGreen)
                }
                else {
                    Set-State (
                        'Подключается…'
                    ) (
                        'Remote-процесс запущен; ожидаю подтверждение Remote MCP.'
                    ) ([Drawing.Color]::Khaki)
                }
            }
        }
        elseif (-not $script:exitHandled) {
            Read-LiveLog
            $code = $script:proc.ExitCode
            $script:exitHandled = $true
            Set-FinishButtonMode $false

            if ($script:stopping) {
                Set-State 'Завершён' 'Remote-процесс остановлен.' ([Drawing.Color]::Silver)
            }
            elseif (Repair-DesktopCommanderMissingNpxPackageJson) {
                $bootstrapReason = 'npm не смог найти package.json в повреждённом npx-кэше (ENOENT / -4058). Удалена только сбойная запись; повторяю запуск.'
                Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] ВОССТАНОВЛЕНИЕ: ' + $bootstrapReason + $nl)
                Schedule-AutoReconnect $bootstrapReason
                Set-DividerFaultState $false
                Set-State 'Восстановление npm-кэша…' $bootstrapReason ([Drawing.Color]::Khaki)
            }
            elseif ($code -eq 1 -and (Test-DesktopCommanderBootstrapFailure)) {
                [void](Repair-DesktopCommanderNpxCache)
                $bootstrapReason = 'Desktop Commander не запустился: в локальном npx-кэше отсутствует dist/index.js. Повреждённый кэш удалён; повторяю запуск автоматически.'
                Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] ВОССТАНОВЛЕНИЕ: ' + $bootstrapReason + $nl)
                Schedule-AutoReconnect $bootstrapReason
                Set-DividerFaultState $false
                Set-State 'Восстановление Desktop Commander…' $bootstrapReason ([Drawing.Color]::Khaki)
            }
            else {
                Set-RemoteFault 'process-exit' (
                    'Remote-процесс неожиданно завершился с кодом ' + $code + '.'
                ) $true
                Set-State 'Проблема связи' $script:remoteFaultReason ([Drawing.Color]::LightCoral)
            }

            Set-RuntimeDisplay ('Код завершения: ' + $code)
            Add-Log (
                $nl + '[' + (Get-Date -Format 'HH:mm:ss') +
                '] Процесс завершён. Код: ' + $code + $nl
            )
            $script:freezeViewport = $false
        }
    }
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 700
$script:lastRefreshException = ''
$timer.Add_Tick({
    try {
        Refresh-Window
        $script:lastRefreshException = ''
    }
    catch {
        # A background health/UI refresh must never surface as a modal WinForms
        # exception dialog. Record each distinct failure once and keep the event
        # loop alive so Remote MCP recovery can continue in the background.
        $refreshError = $_.Exception.Message
        if ($script:lastRefreshException -ne $refreshError) {
            $script:lastRefreshException = $refreshError
            try {
                $uiErrorPath = Join-Path $root 'rdc-relay-ui-errors.log'
                $entry =
                    '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') +
                    '] Refresh-Window: ' + $refreshError + $nl +
                    $_.ScriptStackTrace + $nl
                [IO.File]::AppendAllText(
                    $uiErrorPath,
                    $entry,
                    (New-Object Text.UTF8Encoding($false))
                )
            } catch {}
        }
    }
})

# The notification module owns only its temporary footer replacement, async
# stable-branch checker and update button; removing it restores the old footer.
$script:enableUpdateNotice = $script:enableUpdateNotice -and
    (Test-Path -LiteralPath (Join-Path $root 'update-notice.ps1'))
if ($script:enableUpdateNotice) { . (Join-Path $root 'update-notice.ps1') }

$script:shortcutSyncTimer = $null
if (-not $SelfTest -and -not $Preview) {
    $script:shortcutSyncTimer = New-Object Windows.Forms.Timer
    $script:shortcutSyncTimer.Interval = 800
    $script:shortcutSyncTimer.Add_Tick({
        $script:shortcutSyncTimer.Stop()
        [void](Sync-RdcShortcuts)
        $script:shortcutSyncTimer.Dispose()
        $script:shortcutSyncTimer = $null
    })
    $form.Add_Shown({
        if ($script:shortcutSyncTimer) {
            $script:shortcutSyncTimer.Start()
        }
    })
}

$form.Add_Activated({
    try {
        $headerLog.SetViewPosition(0,0)
        $headerVScroll.Invalidate()
    } catch {}
})

$form.Add_ResizeBegin({
    $script:uiInteracting = $true
})
$form.Add_ResizeEnd({
    $script:uiInteracting = $false
    if($OwnerGui -and $script:startupBlock -and $script:lastHeaderLayoutKey -cne $headerLog.BannerLayoutKey){Render-CompactLog}
    Layout-LogScrollbars
    if($script:ownerCompactJournal){Refresh-Rc1JournalOnResize}
    try { $log.RefreshViewport() } catch {}
    Refresh-Window
})

$form.Add_FormClosing({
    param($sender,$e)
    # OwnerGui X always closes this replacement GUI, never legacy Remote.
    if ($OwnerGui) { return }
    if ($script:allowClose -or $SelfTest -or $Preview) { return }
    if ($script:initializing -or $script:remoteOperation) {
        $e.Cancel = $true
        $script:closeRequested = $true
        return
    }
    if ($script:proc -and -not $script:proc.HasExited) {
        $e.Cancel = $true
        $script:closeRequested = $true
        Begin-RemoteOperation 'close'
    }
})
$form.Add_FormClosed({
    $timer.Stop()
    if($script:ownerVersionIntroTimer){
        $script:ownerVersionIntroTimer.Stop()
        $script:ownerVersionIntroTimer.Dispose()
        $script:ownerVersionIntroTimer=$null
    }
    if ($script:enableUpdateNotice) { Dispose-RdcUpdateNotice }
    if ($script:shortcutSyncTimer) {
        try { $script:shortcutSyncTimer.Stop() } catch {}
        try { $script:shortcutSyncTimer.Dispose() } catch {}
        $script:shortcutSyncTimer = $null
    }
    if ($script:reader) { $script:reader.Dispose() }
    if ($script:proc) { $script:proc.Dispose() }
})
if ($SelfTest) {
    foreach ($button in @($finish,$accountButton,$helpButton)) {
        if (-not $button.TabStop -or $button.AccessibleRole -ne [Windows.Forms.AccessibleRole]::PushButton) {
            throw 'Primary action is not keyboard/accessibility enabled'
        }
        if ($button.BackColor.A -ne 255) {
            throw 'Primary action button background must be opaque'
        }
    }
    if ($headerLog.TabStop -or $log.TabStop) {
        throw 'Read-only log surfaces must not participate in primary Tab navigation'
    }

    $tabTargets = @(Get-TabStopControls $form)
    $unexpectedTabTargets = @(
        $tabTargets | Where-Object {
            $_ -ne $finish -and
            $_ -ne $accountButton -and
            $_ -ne $helpButton
        }
    )
    if ($tabTargets.Count -ne 3 -or $unexpectedTabTargets.Count -ne 0) {
        $tabNames = @($tabTargets | ForEach-Object { $_.GetType().Name + ':' + $_.Name }) -join ', '
        throw ('Unexpected Tab traversal targets: ' + $tabNames)
    }

    if ($menuColors.MenuItemSelected.A -ne 128 -or
        $menuColors.MenuItemPressedGradientBegin.A -ne 128 -or
        $menuColors.MenuItemPressedGradientMiddle.A -ne 128 -or
        $menuColors.MenuItemPressedGradientEnd.A -ne 128 -or
        $menuColors.MenuItemBorder.A -ne 255) {
        throw 'Account/help menu selection alpha contract is invalid'
    }

    Set-State 'Тест' 'Проверка интерфейса без запуска remote.' ([Drawing.Color]::LightBlue)
    Add-Log ('SELF TEST OK' + $nl)

    # Release/runtime integrity: the version, manifest and payload must describe
    # one exact build. This catches the split-brain 1.5.10 state where Source,
    # dist and the installed payload could carry different files under one version.
    $selfVersionPath = Join-Path $root 'version.txt'
    if (-not (Test-Path -LiteralPath $selfVersionPath)) { throw 'version.txt missing' }
    $selfVersion = (Get-Content -LiteralPath $selfVersionPath -Raw -Encoding UTF8).Trim()
    if ($selfVersion -ne $appVersion) { throw ('Runtime version mismatch: script=' + $appVersion + ', file=' + $selfVersion) }

    $selfManifestPath = Join-Path $root 'update-manifest.json'
    if (-not (Test-Path -LiteralPath $selfManifestPath)) { throw 'update-manifest.json missing' }
    $selfManifest = Get-Content -LiteralPath $selfManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$selfManifest.version -ne $appVersion) { throw 'Update manifest version mismatch' }

    $requiredPayload = @(
        'remote-window.ps1',
        'update-notice.ps1',
        'divider-caustic.ps',
        'divider-caustic-detail.ps',
        'divider-particles.ps',
        'divider-particles-core.ps',
        'RDCRelay.ico',
        'version.txt',
        'update.ps1',
        'RDC Relay.cmd'
    )
    $manifestNames = @($selfManifest.files | ForEach-Object { [string]$_.name })
    if ($manifestNames.Count -ne $requiredPayload.Count) {
        throw ('Update manifest payload count mismatch: expected ' + $requiredPayload.Count + ', got ' + $manifestNames.Count)
    }
    if (@($manifestNames | Sort-Object -Unique).Count -ne $manifestNames.Count) {
        throw 'Update manifest contains duplicate payload names'
    }
    foreach ($manifestName in $manifestNames) {
        if ($requiredPayload -notcontains $manifestName) {
            throw ('Update manifest contains unexpected payload: ' + $manifestName)
        }
    }
    foreach ($requiredName in $requiredPayload) {
        if ($manifestNames -notcontains $requiredName) {
            throw ('Update manifest missing payload: ' + $requiredName)
        }
    }
    foreach ($manifestFile in $selfManifest.files) {
        $payloadName = [string]$manifestFile.name
        $payloadPath = Join-Path $root $payloadName
        if (-not (Test-Path -LiteralPath $payloadPath)) {
            throw ('Manifest payload file missing: ' + $payloadName)
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $payloadPath).Hash.ToUpperInvariant()
        $expectedHash = ([string]$manifestFile.sha256).ToUpperInvariant()
        if ($actualHash -ne $expectedHash) {
            throw ('Manifest SHA256 mismatch: ' + $payloadName)
        }
    }

    # Development checkout checks. Installed releases intentionally do not ship
    # HLSL/build scripts, so these run only when the repository files are present.
    $selfRepoRoot = Split-Path -Parent $root
    $selfShaderBuild = Join-Path $selfRepoRoot 'Scripts\build-shaders.ps1'
    if (Test-Path -LiteralPath $selfShaderBuild) {
        $shaderBuildText = Get-Content -LiteralPath $selfShaderBuild -Raw -Encoding UTF8
        foreach ($shaderSourceName in @(
            'divider-caustic.hlsl',
            'divider-caustic-detail.hlsl',
            'divider-particles.hlsl',
            'divider-particles-core.hlsl'
        )) {
            if ($shaderBuildText.IndexOf($shaderSourceName,[StringComparison]::Ordinal) -lt 0) {
                throw ('Shader build does not compile source: ' + $shaderSourceName)
            }
        }

        foreach ($particleSourceName in @('divider-particles.hlsl','divider-particles-core.hlsl')) {
            $particleSourcePath = Join-Path $root $particleSourceName
            $particleSourceText = Get-Content -LiteralPath $particleSourcePath -Raw -Encoding UTF8
            if ($particleSourceText -notmatch 'PassIndex\s*:\s*register\(c7\)') {
                throw ('Explicit particle PassIndex c7 missing: ' + $particleSourceName)
            }
            if ($particleSourceText -match 'Intensity\s*>\s*0\.5805') {
                throw ('Particle pass selection is coupled to Intensity again: ' + $particleSourceName)
            }
            if ($particleSourceText -match '(?s)return\s+float4\([^;]*,\s*1\.0\s*\)') {
                throw ('Particle shader returned an opaque frame: ' + $particleSourceName)
            }
            if ($particleSourceText -notmatch 'min\(saturate\(outRgb\),\s*(alpha|outAlpha|coreAlpha)\.xxx\)') {
                throw ('Particle shader lost premultiplied-alpha clamp: ' + $particleSourceName)
            }
            if ($particleSourceText -notmatch 'float\s+t\s*=\s*Time\s*\*\s*0\.5') {
                throw ('Particle shader lost half-speed time scale: ' + $particleSourceName)
            }
            if ($particleSourceText -notmatch 'float\s+horizontalScale\s*=\s*2\.0') {
                throw ('Particle shader lost 2x horizontal scale: ' + $particleSourceName)
            }
            if ($particleSourceText -notmatch 'float\s+verticalScale\s*=\s*0\.6666667') {
                throw ('Particle shader lost 1.5x vertical compression: ' + $particleSourceName)
            }
            if ($particleSourceText -notmatch 'float\s+brightnessScale\s*=\s*0\.82') {
                throw ('Particle shader lost 18 percent brightness trim: ' + $particleSourceName)
            }
        }

        $detailSourcePath = Join-Path $root 'divider-caustic-detail.hlsl'
        $detailSourceText = Get-Content -LiteralPath $detailSourcePath -Raw -Encoding UTF8
        if ($detailSourceText -match '(?s)return\s+float4\([^;]*,\s*1\.0\s*\)') {
            throw 'Transparent caustic detail shader returned an opaque frame'
        }
        if ($detailSourceText -notmatch 'return\s+float4\(rgb,alpha\)') {
            throw 'Transparent caustic detail shader lost explicit alpha output'
        }

        $runtimeSourceText = Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8
        if ($runtimeSourceText.IndexOf('particlePopup.Child=popupRoot',[StringComparison]::Ordinal) -lt 0) {
            throw 'GPU sandwich is no longer hosted by the single popup root'
        }
        if ([Regex]::Matches($runtimeSourceText,'new\s+Popup\(\);').Count -ne 1) {
            throw 'GPU divider must use exactly one native WPF Popup'
        }
        foreach ($transparentContract in @(
            'popupRoot.Background=Brushes.Transparent',
            'particleLayer.Background=Brushes.Transparent',
            'particleSource.Background=Brushes.Transparent'
        )) {
            if ($runtimeSourceText.IndexOf($transparentContract,[StringComparison]::Ordinal) -lt 0) {
                throw ('GPU sandwich transparency contract missing: ' + $transparentContract)
            }
        }
        foreach ($densityContract in @(
            'particleEffectC = new RdcDividerGlowEffect(particleShaderPath)',
            'particleEffectD = new RdcDividerGlowEffect(particleShaderPath)',
            'coreEffectC = new RdcDividerGlowEffect(particleCoreShaderPath)',
            'coreEffectD = new RdcDividerGlowEffect(particleCoreShaderPath)'
        )) {
            if ($runtimeSourceText.IndexOf($densityContract,[StringComparison]::Ordinal) -lt 0) {
                throw ('Doubled particle density contract missing: ' + $densityContract)
            }
        }
        if ($runtimeSourceText.IndexOf('int crossingCenterExtra = 6;',[StringComparison]::Ordinal) -lt 0 -or
            $runtimeSourceText.IndexOf('dividerHeight+crossingCenterExtra-1',[StringComparison]::Ordinal) -lt 0) {
            throw 'Divider drag mask center geometry regressed'
        }
        if ($runtimeSourceText.IndexOf('ApplyCompactLineSpacing()',[StringComparison]::Ordinal) -lt 0 -or
            $runtimeSourceText.IndexOf('if($OwnerGui){$headerLog.ApplyCompactHeaderLineArtSpacing()}',[StringComparison]::Ordinal) -lt 0 -or
            $runtimeSourceText.IndexOf('else{$headerLog.ApplyCompactLineSpacing()}',[StringComparison]::Ordinal) -lt 0 -or
            $runtimeSourceText.IndexOf('$log.ApplyCompactLineSpacing()',[StringComparison]::Ordinal) -lt 0) {
            throw 'RC1 selective / legacy RichEdit spacing contract regressed'
        }
        if ($runtimeSourceText.IndexOf('250.0 * i / fadeDenominator',[StringComparison]::Ordinal) -lt 0 -or
            $runtimeSourceText.IndexOf('250.0 * (crossingFade-1-i) / fadeDenominator',[StringComparison]::Ordinal) -lt 0) {
            throw 'Divider drag mask linear 0-250 fade regressed'
        }
    }
    if ($form.Controls.Count -lt 3) { throw 'UI controls missing' }
    if ($finish.Text -ne 'Остановить' -or $finish.Glyph -ne [RdcButtonGlyph]::Stop) { throw 'Stop button state missing' }
    Set-FinishButtonMode $false
    if ($finish.Text -ne 'Запустить' -or $finish.Glyph -ne [RdcButtonGlyph]::Play) { throw 'Start button state missing' }
    Set-FinishButtonMode $true
    if ($accountButton.Text -notlike 'Аккаунт*') { throw 'Account button missing' }
    if ($helpButton.Text -ne '' -or -not $helpButton.Image -or
        $helpButton.Parent -ne $(if($OwnerGui){$bottom}else{$titleHost}) -or
        $helpButton.AccessibleName -ne 'Справка / О программе') {
        throw 'Native Help button missing from expected header/footer host'
    }
    if ($accountMenu.Items.Count -lt 4) { throw 'Account menu missing' }
    if ($reconnectItem.Text -ne 'Переподключить') { throw 'Reconnect account action missing' }
    if ($form.Text -ne 'RDC Relay') { throw 'Window title changed unexpectedly' }
    if ($form.FormBorderStyle -ne [Windows.Forms.FormBorderStyle]::Sizable -or $form.MaximizeBox -or $form.SizeGripStyle -ne [Windows.Forms.SizeGripStyle]::Hide) { throw 'Window vertical resize policy mismatch' }
    if ($form.MinimumSize.Width -ne $windowWidth -or $form.MaximumSize.Width -ne $windowWidth) { throw 'Window width must stay fixed' }
    if ($form.MinimumSize.Height -ge $form.MaximumSize.Height) { throw 'Window height must remain resizable' }
    if ($form.MinimumSize.Height -ne $minimumWindowHeight) { throw 'Window minimum height mismatch' }
    if ($form.Width -gt $startupWorkArea.Width -or $form.Height -gt $startupWorkArea.Height) { throw 'Window exceeds startup working area' }
    if ($startupWorkArea.Width -ge $baseWindowWidth -and $startupWorkArea.Height -ge $baseWindowHeight) {
        if ($form.Width -ne $baseWindowWidth -or $form.Height -ne $baseWindowHeight) { throw 'Window should use configured base size on capable screen' }
    }
    if ($scrollCorner.Cursor -ne [Windows.Forms.Cursors]::SizeNS) { throw 'Activity resize grip cursor mismatch' }
    $legacyGripPattern = ('WM_NCLBUTTON'+'DOWN|HTBOTTOM'+'RIGHT')
    if (Select-String -LiteralPath $PSCommandPath -Pattern $legacyGripPattern -Quiet) { throw 'Legacy whole-window resize grip still present' }
    if ($title.Text -notlike 'RDC Relay*') { throw 'Header title missing' }
    if ($title.Text -match '\bv\d+\.\d+\b') { throw 'Version must not be in header' }
    if ($hintVersion.Text -ne ('v' + $appVersion)) { throw 'Bottom version label missing' }
    if ($bottom.ColumnStyles[1].Width -lt 440) { throw 'Bottom version container too narrow' }
    $bannerProbe = New-Object RdcLogBox
    $bannerProbe.ForeColor = [Drawing.Color]::Gainsboro
    $probeLine = ('A' * 61) + ('B' * 12)
    $bannerProbe.Text = (($probeLine + $nl) * 6) + 'Remote Connection'
    if (-not $bannerProbe.StyleStartupBanner([Drawing.Color]::FromArgb(191,118,67),[Drawing.Color]::FromArgb(123,95,162))) { throw 'Startup banner styling failed' }
    $bannerProbe.Select(0,1)
    if ($bannerProbe.SelectionColor.ToArgb() -ne [Drawing.Color]::FromArgb(191,118,67).ToArgb()) { throw 'Startup banner DESKTOP orange color mismatch' }
    $bannerProbe.Select(61,1)
    if ($bannerProbe.SelectionColor.ToArgb() -ne [Drawing.Color]::FromArgb(123,95,162).ToArgb()) { throw 'Startup banner COMMANDER purple color mismatch' }
    $bannerProbe.Dispose()
    if ($hintSep.Text -ne '•') { throw 'Bottom separator missing' }
    if ($runtimeSep.Text -ne '|') { throw 'Runtime separator missing' }
    $npxProbe = Resolve-NpxPath
    if (-not $npxProbe -or -not (Test-Path -LiteralPath $npxProbe)) { throw 'npx resolver failed' }
    if ($desktopCommanderPackage -ne '@wonderwhy-er/desktop-commander@latest') { throw 'Unexpected Desktop Commander package pin' }
    if ($hintSep.ForeColor.ToArgb() -ne $accentOrange.ToArgb()) { throw 'Bottom separator color mismatch' }
    if ($runtimeSep.ForeColor.ToArgb() -ne $accentOrange.ToArgb()) { throw 'Runtime separator color mismatch' }
    if ($script:enableUpdateNotice) {
        $normalWidth = [int]$bottom.ColumnStyles[1].Width
        if ($normalWidth -ne 440 -or -not $bottom.Controls.Contains($script:rdcNoticeControl) -or
            $bottom.Controls.Contains($hintHost) -or $script:rdcNoticeControl.IsActive) {
            throw 'Idle notification renderer must remain attached without changing footer width'
        }
        $baselineNoticeControl = $script:rdcNoticeControl
        $baselineNoticeTop = $script:rdcNoticeControl.Top
        $baselineNoticeFont = $script:rdcNoticeControl.Font
        # Render and store the exact right-hand informational text before
        # animation. Its pixels must remain bit-for-bit unchanged afterwards.
        $bmpIdle = New-Object Drawing.Bitmap($script:rdcNoticeControl.Width,$script:rdcNoticeControl.Height)
        $script:rdcNoticeControl.DrawToBitmap($bmpIdle,(New-Object Drawing.Rectangle(0,0,$bmpIdle.Width,$bmpIdle.Height)))
        $parsedCurrent = [Version]$appVersion
        $noticeTestVersion = '{0}.{1}.{2}' -f $parsedCurrent.Major,$parsedCurrent.Minor,($parsedCurrent.Build+1)
        $newerManifest = '{"version":"' + $noticeTestVersion + '"}'
        $sameManifest = '{"version":"' + $appVersion + '"}'
        if ((Get-RdcAvailableVersionFromManifest $newerManifest) -ne $noticeTestVersion -or
            (Get-RdcAvailableVersionFromManifest $sameManifest)) {
            throw 'Stable manifest version comparison is incorrect'
        }
        Show-RdcUpdateNotice $noticeTestVersion
        if ([Math]::Abs($script:rdcNoticeControl.Font.SizeInPoints - $hint.Font.SizeInPoints) -gt 0.001 -or
            [Math]::Abs($hintVersion.Font.SizeInPoints - $hint.Font.SizeInPoints) -gt 0.001) {
            throw ('Installed version footer font mismatch: control=' + $script:rdcNoticeControl.Font.SizeInPoints + ', version=' + $hintVersion.Font.SizeInPoints + ', info=' + $hint.Font.SizeInPoints)
        }
        if (-not $script:rdcNoticeActive -or $bottom.Controls.Contains($hintHost) -or
            -not [Object]::ReferenceEquals($baselineNoticeControl,$script:rdcNoticeControl) -or
            -not [Object]::ReferenceEquals($baselineNoticeFont,$script:rdcNoticeControl.Font)) {
            throw 'Notice activation rebuilt the footer renderer or changed its font'
        }
        $script:rdcNoticeControl.FinishAnimationForTest()
        $bottom.ColumnStyles[1].Width = $script:rdcNoticeControl.SuggestedWidth
        $bottom.PerformLayout()
        # Regression: the footer's auto-layout row is 100px high, while only
        # the top 25px is visible. An opaque control drawing in the center of
        # that row disappears completely on-screen (even though DrawToBitmap
        # of its entire 100px area can pass).
        $visibleFooterHeight = $bottom.ClientSize.Height - $bottom.Padding.Vertical
        if ($script:rdcNoticeControl.Height -gt $visibleFooterHeight -or
            $script:rdcNoticeControl.Top -ne $bottom.Padding.Top -or
            $script:rdcNoticeControl.Height -lt 20) {
            throw ('Update notice clipped outside visible footer: control=' +
                $script:rdcNoticeControl.Bounds + ', visible height=' +
                $visibleFooterHeight)
        }
        $bmp = New-Object Drawing.Bitmap([Math]::Max(1,$script:rdcNoticeControl.Width),[Math]::Max(1,$script:rdcNoticeControl.Height))
        try {
            $script:rdcNoticeControl.DrawToBitmap($bmp,(New-Object Drawing.Rectangle(0,0,$bmp.Width,$bmp.Height)))
            # Compare right-hand note area relative to the fixed right edge:
            # rendering, glyph size, vertical position and colors must not move.
            $notePixelWidth = [Math]::Min(285,[Math]::Min($bmpIdle.Width,$bmp.Width))
            for ($py=0; $py -lt $bmp.Height; $py++) {
                for ($dx=1; $dx -le $notePixelWidth; $dx++) {
                    if ($bmpIdle.GetPixel(($bmpIdle.Width-$dx),$py).ToArgb() -ne
                        $bmp.GetPixel(($bmp.Width-$dx),$py).ToArgb()) {
                        throw ('Footer informational text changed pixel during animation: xFromRight=' +
                            $dx + ', y=' + $py)
                    }
                }
            }
            if ($env:RDC_RELAY_FOOTER_CAPTURE) {
                $bmp.Save($env:RDC_RELAY_FOOTER_CAPTURE,[Drawing.Imaging.ImageFormat]::Png)
            }
        } finally { $bmp.Dispose(); $bmpIdle.Dispose() }
        if (-not $script:rdcNoticeControl.AnimationComplete -or
            -not $script:rdcNoticeControl.ButtonReady -or
            $script:rdcNoticeControl.SuggestedWidth -ne 590 -or
            $script:rdcNoticeControl.OfferedVersion -ne $noticeTestVersion) {
            throw 'Update notification stage timings/geometry invalid'
        }
        # A newer stable release must replace an already displayed update
        # without recreating the footer or replaying identical notifications.
        $laterTestVersion = '{0}.{1}.{2}' -f $parsedCurrent.Major,$parsedCurrent.Minor,($parsedCurrent.Build+2)
        Show-RdcUpdateNotice $laterTestVersion
        if ($script:rdcNoticeControl.OfferedVersion -ne $laterTestVersion -or
            -not [Object]::ReferenceEquals($baselineNoticeControl,$script:rdcNoticeControl)) {
            throw 'A later release failed to replace the already visible update version'
        }
        $script:rdcNoticeControl.FinishAnimationForTest()
        Show-RdcUpdateNotice $laterTestVersion
        if (-not $script:rdcNoticeControl.ButtonReady -or
            $script:rdcNoticeControl.OfferedVersion -ne $laterTestVersion) {
            throw 'Identical update version unexpectedly replayed the animation'
        }
        $script:rdcNoticeTestClicks = 0
        $clickProbe = [EventHandler] { param($sender,$args) $script:rdcNoticeTestClicks++ }
        $script:rdcNoticeControl.add_Click($clickProbe)
        try {
            $downMethod = $script:rdcNoticeControl.GetType().GetMethod('OnKeyDown',
                [Reflection.BindingFlags]'Instance,NonPublic')
            $upMethod = $script:rdcNoticeControl.GetType().GetMethod('OnKeyUp',
                [Reflection.BindingFlags]'Instance,NonPublic')
            foreach ($key in @([Windows.Forms.Keys]::Enter,[Windows.Forms.Keys]::Space)) {
                $downEvent = New-Object Windows.Forms.KeyEventArgs($key)
                $upEvent = New-Object Windows.Forms.KeyEventArgs($key)
                $downMethod.Invoke($script:rdcNoticeControl,[object[]]@($downEvent.PSObject.BaseObject)) | Out-Null
                $upMethod.Invoke($script:rdcNoticeControl,[object[]]@($upEvent.PSObject.BaseObject)) | Out-Null
            }
            if ($script:rdcNoticeTestClicks -ne 2) {
                throw 'Update button must support Enter/Space activation exactly once'
            }
        } finally {
            $script:rdcNoticeControl.remove_Click($clickProbe)
        }
        Hide-RdcUpdateNotice
        if ($script:rdcNoticeActive -or $script:rdcNoticeControl.IsActive -or
            -not $bottom.Controls.Contains($script:rdcNoticeControl) -or
            $bottom.Controls.Contains($hintHost) -or
            -not [Object]::ReferenceEquals($baselineNoticeControl,$script:rdcNoticeControl) -or
            $script:rdcNoticeControl.Top -ne $baselineNoticeTop -or
            [int]$bottom.ColumnStyles[1].Width -ne $normalWidth -or
            $hintVersion.Text -ne ('v'+$appVersion) -or $hintSep.Text -ne '•') {
            throw 'Hiding update notification did not restore persistent idle footer'
        }
    }
    if ($statusDot.GetType().Name -ne 'RdcStatusIndicator') { throw 'Status indicator control missing' }
    if ($headerLog.GetType().Name -ne 'RdcLogBox') { throw 'Header log control missing' }
    if ($headerVScroll.GetType().Name -ne 'RdcOverlayScrollBar' -or -not $headerVScroll.Vertical -or $headerVScroll.Target -ne $headerLog) { throw 'Header vertical scrollbar missing' }
    if ($headerDivider.Cursor -ne [Windows.Forms.Cursors]::SizeNS -or [Math]::Abs($headerHost.RowStyles[1].Height - 7) -gt 0.1) { throw 'Draggable header divider missing' }
    if ($dividerDragPreview.GetType().Name -ne 'RdcDividerDragPreview') { throw 'Deferred divider drag preview missing' }
    $testFormWidth = $form.Width
    $testFormHeight = $form.Height
    $testPaneHeight = $contentHost.RowStyles[1].Height
    $testPaneMin = Get-EffectivePaneMinHeight
    Set-ActivityPaneHeight ($testPaneMin + 10)
    if ($form.Width -ne $testFormWidth -or $form.Height -ne $testFormHeight) { throw 'Pane resize changed whole window size' }
    if ($contentHost.RowStyles[1].Height -lt $testPaneMin) { throw 'Activity pane minimum height failed' }
    Set-ActivityPaneHeight 99999
    $testHeaderMin=[Math]::Min($headerPaneMinHeightPreferred,
        [Math]::Max(48,$contentHost.ClientSize.Height-$testPaneMin))
    if (($contentHost.ClientSize.Height - $contentHost.RowStyles[1].Height) -lt ($testHeaderMin-1)) {
        throw 'Header banner minimum height clamp failed'
    }
    Set-ActivityPaneHeight $testPaneHeight
    if ($log.GetType().Name -ne 'RdcLogBox') { throw 'Activity log control missing' }
    if ($logHost.GetType().Name -ne 'RdcBufferedPanel') { throw 'Buffered log viewport missing' }
    $form.PerformLayout()
    Layout-LogScrollbars
    $expectedLogW = [Math]::Max(0,$logHost.ClientSize.Width - 17)
    $expectedLogH = [Math]::Max(0,$logHost.ClientSize.Height - 17)
    if ($log.Left -ne 0 -or $log.Top -ne 0 -or
        $log.Width -ne $expectedLogW -or $log.Height -ne $expectedLogH -or
        $vScroll.Left -ne $expectedLogW -or $vScroll.Top -ne 0 -or
        $vScroll.Width -ne 17 -or $vScroll.Height -ne $expectedLogH -or
        $hScroll.Left -ne 0 -or $hScroll.Top -ne $expectedLogH -or
        $hScroll.Width -ne $expectedLogW -or $hScroll.Height -ne 17 -or
        $scrollCorner.Left -ne $expectedLogW -or $scrollCorner.Top -ne $expectedLogH -or
        $scrollCorner.Width -ne 17 -or $scrollCorner.Height -ne 17) {
        throw 'Atomic scrollbar viewport geometry mismatch'
    }
    if ($log.ScrollBars -ne [Windows.Forms.RichTextBoxScrollBars]::None) {
        throw 'Native RichEdit scrollbars must stay disabled'
    }
    if ($contentHost.RowCount -ne 2 -or $contentHost.RowStyles[0].SizeType -ne [Windows.Forms.SizeType]::Percent -or $contentHost.RowStyles[1].SizeType -ne [Windows.Forms.SizeType]::Absolute -or [Math]::Abs($contentHost.RowStyles[1].Height - $activityDefaultHeight) -gt 0.1) { throw 'Two-panel log layout missing' }
    if (-not $headerLog.WordWrap -or $headerLog.ScrollBars -ne [Windows.Forms.RichTextBoxScrollBars]::None -or [Math]::Abs($headerLog.Font.Size - 9.0) -gt 0.1) { throw 'Header wrapping/scroll policy mismatch' }
    if ([Math]::Abs($headerLog.ZoomFactor - 1.0) -gt 0.001) { throw 'Header zoom must be fixed at 100 percent' }
    if ([Math]::Abs($log.ZoomFactor - 1.0) -gt 0.001) { throw 'Activity zoom must be fixed at 100 percent' }
    if ($scrollCorner.GetType().Name -ne 'RdcScrollCorner') { throw 'Scroll corner grip missing' }
    if ($hScroll.GetType().Name -ne 'RdcOverlayScrollBar') { throw 'Horizontal scrollbar missing' }
    if ([string]::IsNullOrWhiteSpace($accountInfo.Text)) { throw 'Account display missing' }
    $log.Text = ('A' * 1000)
    $log.RemoveLeadingText(600)
    if ($log.TextLength -ne 400) { throw 'Read-only log trimming failed' }
    if ($log.SelectionLength -ne 0) { throw 'Log trimming left visible selection' }
    $chunkProbe = New-Object IO.StringReader(('B' * 50000))
    $chunk1 = [RdcLogBox]::ReadChunk($chunkProbe,$logReadChunkChars)
    $chunk2 = [RdcLogBox]::ReadChunk($chunkProbe,$logReadChunkChars)
    $chunkProbe.Dispose()
    if ($chunk1.Length -ne $logReadChunkChars) { throw 'Bounded log read first chunk failed' }
    if ($chunk2.Length -ne $logReadChunkChars) { throw 'Bounded log read second chunk failed' }
    if (Select-String -LiteralPath $PSCommandPath -Pattern 'ReadToEnd\(' -Quiet) { throw 'Unbounded ReadToEnd found in GUI script' }

    Reset-CompactLogSession
    $runtimeSynthetic =
        'START HEADER' + $nl +
        'Remote Connection' + $nl +
        '┌─ Commands' + $nl +
        '│ Help:    npx desktop-commander remote --help' + $nl +
        '│ Log out: npx desktop-commander remote --logout' + $nl +
        '└─ Run these in a new Terminal, or after disconnecting.' + $nl +
        $nl +
        '❌ Channel error: channel error: transport failure - socket=closed(-) ch=errored attempt=0' + $nl +
        '🔴 Device marked as offline' + $nl +
        '[DEBUG] Failed to set status offline: TypeError: fetch failed' + $nl +
        '🔄 Recreating channel... (attempt 1) - socket=closed(-) ch=errored attempt=1' + $nl +
        '⚠️ Channel closed - socket=closed(-) ch=closed attempt=1' + $nl +
        '✅ Channel subscribed (recovered after 1 attempt)' + $nl +
        '🟢 Device marked as online' + $nl +
        '👋 Presence tracked (device test-device visible as online)' + $nl
    Add-RemoteChunk $runtimeSynthetic
    if (-not $script:startupComplete) { throw 'Startup footer did not freeze the reference pane' }
    if ($headerLog.Text -like '*Channel error:*' -or $headerLog.Text -like '*Recreating channel*' -or $headerLog.Text -like '*Presence tracked*') {
        throw 'Runtime transport output leaked into the startup/reference pane'
    }
    if (
        $log.Text -notlike '*Channel error:*' -or
        $log.Text -notlike '*Device marked as offline*' -or
        $log.Text -notlike '*Recreating channel*' -or
        $log.Text -notlike '*Channel subscribed*' -or
        $log.Text -notlike '*Device marked as online*' -or
        $log.Text -notlike '*Presence tracked*'
    ) {
        throw 'Runtime transport output was not routed to the activity pane'
    }
    if ($log.Lines.Count -lt 8) { throw 'Activity pane lost multiline runtime output' }
    try { $log.RefreshViewport() } catch { throw 'Activity viewport refresh failed' }

    Reset-CompactLogSession
    Set-StartupFromProbe $runtimeSynthetic
    if (-not $script:startupComplete) { throw 'Startup probe did not find the Commands footer' }
    if ($script:startupBlock -like '*Channel error:*' -or $script:startupBlock -like '*Presence tracked*') {
        throw 'Startup probe retained post-Commands runtime output'
    }

    Reset-CompactLogSession
    $synthetic = 'START HEADER' + $nl + 'Remote Connection' + $nl +
        '🌐 https://example.invalid/remote  🚀 start  ⏳ wait  🔌 online  💾 saved  👋 presence' + $nl +
        'Found persisted session for device 11111111-2222-3333-4444-555555555555' + $nl +
        'Presence tracked (device 11111111-2222-3333-4444-555555555555 visible as online)' + $nl +
        '   - User:         demo@example.invalid' + $nl +
        '   - Device ID:    11111111-2222-3333-4444-555555555555' + $nl +
        '   - Device Name:  TEST-PC' + $nl +
        '   Device: TEST-PC' + $nl +
        '   Status: Online' + $nl +
        '   Previous status: Offline' + $nl +
        '│ Help:    npx desktop-commander remote --help' + $nl +
        '│ Log out: npx desktop-commander remote --logout' + $nl +
        'Session data' + $nl +
        '🔧 Received tool call a: one' + $nl + 'A' + $nl +
        '✅ Tool call a completed:' + $nl + 'B' + $nl +
        '🔧 Received tool call b: two' + $nl + 'C' + $nl +
        '✅ Tool call b completed:' + $nl + 'D' + $nl +
        '🔧 Received tool call c: three' + $nl + 'E' + $nl +
        '✅ Tool call c completed:' + $nl + 'F' + $nl +
        '🔧 Received tool call d: four' + $nl + 'G' + $nl
    Add-RemoteChunk $synthetic
    if ($script:startupBlock -notlike 'START HEADER*') { throw 'Startup block missing' }
    if ($headerLog.Text -notlike 'START HEADER*') { throw 'Header panel did not receive startup block' }
    if ($headerLog.Text -like '*Received tool call*' -or $headerLog.Text -like '*Tool call a completed:*') { throw 'Header panel contains activity events' }
    if ($log.Text -like '*START HEADER*' -or $log.Text -like '*Remote Connection*') { throw 'Activity panel contains startup header' }
    if ($log.Text -like '*Received tool call a: one*') { throw 'Activity panel retained more than six events' }
    if ($log.Text -notlike '*Tool call a completed:*' -or $log.Text -notlike '*Received tool call b: two*' -or $log.Text -notlike '*Tool call b completed:*' -or $log.Text -notlike '*Received tool call c: three*' -or $log.Text -notlike '*Tool call c completed:*' -or $log.Text -notlike '*Received tool call d: four*') { throw 'Activity panel lost recent six events' }
    $wrenchPos=$log.Text.IndexOf('🔧',[StringComparison]::Ordinal)
    if($wrenchPos -lt 0){throw 'Wrench marker missing'}
    $log.Select($wrenchPos,'🔧'.Length)
    if($log.SelectionColor.ToArgb() -ne $accentOrange.ToArgb()){throw 'Wrench marker color mismatch'}
    $checkPos=$log.Text.IndexOf('✅',[StringComparison]::Ordinal)
    if($checkPos -lt 0){throw 'Check marker missing'}
    $log.Select($checkPos,'✅'.Length)
    if($log.SelectionColor.ToArgb() -ne $accentSuccess.ToArgb()){throw 'Check marker color mismatch'}
    foreach($probe in @(
        @('🔌',$statusGreen,'Plug marker color mismatch'),
        @('⏳',$accentWait,'Wait marker color mismatch'),
        @('🌐',$accentNetwork,'Network marker color mismatch'),
        @('💾',$accentStorage,'Storage marker color mismatch'),
        @('👋',$accentGreeting,'Presence marker color mismatch'),
        @('🚀',$accentOrange,'Launch marker color mismatch')
    )){
        $p=$headerLog.Text.IndexOf([string]$probe[0],[StringComparison]::Ordinal)
        if($p -lt 0){throw ([string]$probe[2]+' (missing)')}
        $headerLog.Select($p,([string]$probe[0]).Length)
        if($headerLog.SelectionColor.ToArgb() -ne ([Drawing.Color]$probe[1]).ToArgb()){throw [string]$probe[2]}
    }
    foreach($probe in @(
        @('Online',$stateOnline,'Online color mismatch'),
        @('Offline',$stateOffline,'Offline color mismatch'),
        @('TEST-PC',$headerValue,'Device value color mismatch'),
        @('npx desktop-commander remote --help',$commandAccent,'Help command text color mismatch'),
        @('npx desktop-commander remote --logout',$commandAccent,'Logout command text color mismatch')
    )){
        $p=$headerLog.Text.IndexOf([string]$probe[0],[StringComparison]::Ordinal)
        if($p -lt 0){throw ([string]$probe[2]+' (missing)')}
        $headerLog.Select($p,([string]$probe[0]).Length)
        if($headerLog.SelectionColor.ToArgb() -ne ([Drawing.Color]$probe[1]).ToArgb()){throw [string]$probe[2]}
    }
    $uuidProbe='11111111-2222-3333-4444-555555555555'
    $uuidPos=0
    $uuidCount=0
    while(($uuidPos=$headerLog.Text.IndexOf($uuidProbe,$uuidPos,[StringComparison]::Ordinal)) -ge 0){
        $headerLog.Select($uuidPos,$uuidProbe.Length)
        if($headerLog.SelectionColor.ToArgb() -ne $headerValue.ToArgb()){throw 'Device UUID color mismatch'}
        $uuidCount++
        $uuidPos += $uuidProbe.Length
    }
    if($uuidCount -ne 3){throw ('Expected 3 highlighted device UUID occurrences, got '+$uuidCount)}
    foreach($labelProbe in @('Help:','Log out:')){
        $p=$headerLog.Text.IndexOf($labelProbe,[StringComparison]::Ordinal)
        if($p -lt 0){throw ('Neutral label missing: '+$labelProbe)}
        $headerLog.Select($p,$labelProbe.Length)
        if($headerLog.SelectionColor.ToArgb() -ne ([Drawing.Color]::Gainsboro).ToArgb()){throw ('Command label should be neutral: '+$labelProbe)}
    }
    $mailProbe='demo@example.invalid'
    $p=$headerLog.Text.IndexOf($mailProbe,[StringComparison]::Ordinal)
    if($p -lt 0){throw 'Email probe missing'}
    $headerLog.Select($p,$mailProbe.Length)
    if($headerLog.SelectionColor.ToArgb() -ne $headerValue.ToArgb()){throw 'Email highlight color mismatch'}
    if($accountInfo.ForeColor.ToArgb() -ne ([Drawing.Color]::Silver).ToArgb()){throw 'Bottom account color mismatch'}

    if ($activityMinHoldSeconds -ne 10.0 -or
        $activityMaxHoldSeconds -ne 30.0 -or
        $activityInterruptedTimeoutSeconds -ne 60.0) {
        throw 'Divider activity timing constants mismatch'
    }

    Reset-CompactLogSession
    Clear-RemoteFault

    # A cold start is a distinct yellow connecting state, followed by one
    # green confirmation only after real Remote MCP readiness is established.
    $script:remoteReady = $false
    Set-DividerStartupState $true
    if ($gpuDivider -and -not $gpuDivider.StartupRequested) {
        throw 'Cold-start connecting state did not request the yellow startup palette'
    }
    Update-RemoteHealthFromLine 'Desktop Commander Remote is connected'
    if (-not $script:remoteReady -or $script:remoteFaultLatched) {
        throw 'Cold-start ready marker did not establish Remote MCP readiness'
    }
    if ($gpuDivider -and $gpuDivider.StartupRequested) {
        throw 'Cold-start ready transition did not leave the yellow startup palette'
    }
    if ($gpuDivider -and -not $gpuDivider.RecoveryActive) {
        throw 'Cold-start ready transition did not start the green confirmation flash'
    }
    $script:remoteReady = $false

    # Physical/network transport loss must latch red immediately while leaving
    # Desktop Commander's own realtime-channel reconnect loop in control.
    Clear-RemoteFault
    $script:remoteReady = $true
    $script:stopping = $false
    Set-DividerStartupState $true
    Update-RemoteHealthFromLine 'Channel error: channel error: transport failure - socket=closed(-) ch=errored attempt=0'
    if ($gpuDivider -and $gpuDivider.StartupRequested) {
        throw 'Transport fault did not override the yellow startup palette'
    }
    if (-not $script:remoteFaultLatched -or $script:remoteFaultKind -ne 'transport-offline') {
        throw 'Realtime transport failure did not latch the network fault'
    }
    if ($script:remoteReady) { throw 'Realtime transport failure did not clear ready state' }
    if ($script:autoReconnectAt -or $script:remoteConnectDeadline) {
        throw 'Realtime transport failure must not compete with the built-in channel reconnect'
    }
    Update-RemoteHealthFromLine 'Channel subscribed (recovered after 7 attempts)'
    if ($script:remoteReady -or -not $script:remoteFaultLatched) {
        throw 'Channel subscription alone must not establish Remote MCP readiness'
    }
    Update-RemoteHealthFromLine 'Device marked as online'
    if ($script:remoteReady -or -not $script:remoteFaultLatched) {
        throw 'Online status write alone must not establish Remote MCP readiness'
    }
    Update-RemoteHealthFromLine 'Presence tracked (device test-device visible as online)'
    if (-not $script:remoteReady -or $script:remoteFaultLatched) {
        throw 'Presence confirmation did not restore Remote MCP readiness'
    }

    # CLOSED without an earlier CHANNEL_ERROR is still a real transport fault.
    Update-RemoteHealthFromLine 'Channel closed - socket=closed(-) ch=closed attempt=1'
    if (-not $script:remoteFaultLatched -or $script:remoteFaultKind -ne 'transport-offline') {
        throw 'Closed realtime channel did not latch transport fault'
    }
    Update-RemoteHealthFromLine 'Presence tracked (device test-device visible as online)'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Presence did not recover a closed realtime channel'
    }

    # Local executor recovery is separate from realtime transport health.
    Update-RemoteHealthFromLine ' - ❌ Local Desktop Commander MCP went away (stdio closed); will restart on next tool call'
    if (-not $script:remoteFaultLatched -or $script:remoteFaultKind -ne 'local-mcp') {
        throw 'Local MCP loss did not latch executor fault'
    }
    Update-RemoteHealthFromLine 'Connected to Desktop Commander MCP'
    if (-not $script:remoteFaultLatched -or $script:remoteReady) {
        throw 'Local MCP handshake cleared fault before executor verification'
    }
    Update-RemoteHealthFromLine 'Local Desktop Commander MCP restarted; device is online again'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Verified local MCP restart did not restore ready state'
    }

    # Clean shutdown noise must not turn the divider red.
    Clear-RemoteFault
    $script:remoteReady = $true
    $script:stopping = $true
    Update-RemoteHealthFromLine 'Device marked as offline'
    Update-RemoteHealthFromLine 'Channel closed - socket=closed(-) ch=closed attempt=0'
    if ($script:remoteFaultLatched) { throw 'Intentional stop incorrectly latched transport fault' }
    $script:stopping = $false
    $script:remoteReady = $false

    # Tool envelopes/results can contain lifecycle-looking text while inspecting
    # source or logs. Those payload strings must never mutate Remote health.
    Reset-CompactLogSession
    Clear-RemoteFault
    $script:remoteReady = $true
    Process-RemoteLine '🔧 Received tool call health_payload_probe: command contains Channel error: synthetic'
    Process-RemoteLine '{"content":[{"type":"text","text":"Channel error: synthetic tool output"}]}'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Tool payload text falsely triggered Remote transport fault'
    }
    Process-RemoteLine '✅ Tool call health_payload_probe completed:'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Tool payload probe completion corrupted Remote health'
    }

    # A successful end-to-end remote call proves reachability even if upstream
    # does not repeat Presence after its internal reconnect.
    Set-RemoteFault 'transport-offline' 'synthetic reconnect probe' $false
    Process-RemoteLine '🔧 Received tool call transport_recovery_probe: begin'
    Process-RemoteLine '✅ Tool call transport_recovery_probe completed:'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Successful tool call did not clear recoverable transport fault'
    }

    # Restarted shell + adopted already-running Remote MCP: no fresh Presence
    # marker may arrive, so successful tool completion must establish ready.
    Reset-CompactLogSession
    Clear-RemoteFault
    $script:remoteReady = $false
    Process-RemoteLine '🔧 Received tool call adopted_session_probe: begin'
    Process-RemoteLine '✅ Tool call adopted_session_probe completed:'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Successful tool call did not establish readiness for adopted Remote MCP session'
    }
    Reset-CompactLogSession

    # A caller-local $detail string used to shadow the WinForms status label and
    # surface as a modal "property Text not found" exception.
    & {
        $detail = 'shadow probe'
        Set-State 'Проблема связи' 'status-detail probe' ([Drawing.Color]::LightCoral)
    }
    if ($statusDetail.Text -ne 'status-detail probe') {
        throw 'Status detail control is still vulnerable to caller variable shadowing'
    }

    if ($script:activityHoldSeconds -ne 10.0) { throw 'Divider minimum hold must start at 10 seconds' }
    Process-RemoteLine '🔧 Received tool call timeout_probe: begin'
    $script:lastToolMarkerAt = (Get-Date).AddSeconds(-59)
    Refresh-DividerActivitySession
    if ($script:activeToolCalls -ne 1) { throw 'Interrupted tool call faulted before 60 seconds' }
    if ($script:remoteFaultLatched) { throw 'Fault latch engaged before 60 seconds' }

    $script:lastToolMarkerAt = (Get-Date).AddSeconds(-61)
    Refresh-DividerActivitySession
    if ($script:activeToolCalls -ne 0) { throw 'Stale tool activity did not retire after 60 seconds' }
    if ($script:remoteFaultLatched) { throw 'Silence incorrectly entered Remote fault mode' }
    if ($script:activityHoldUntil) { throw 'Stale tool activity left an idle hold behind' }

    Process-RemoteLine '✅ Tool call timeout_probe completed:'
    if ($script:activeToolCalls -ne 0) { throw 'Late completion after stale retirement corrupted activity count' }
    if ($script:remoteFaultLatched) { throw 'Late completion after stale retirement latched fault mode' }

    Clear-RemoteFault
    $script:remoteReady = $false
    Update-RemoteHealthFromLine 'Remote session expired and could not be renewed'
    if (-not $script:remoteFaultLatched -or $script:remoteFaultKind -ne 'session-lost') {
        throw 'Fatal Remote MCP session loss was not latched'
    }
    Update-RemoteHealthFromLine 'Desktop Commander Remote is connected'
    if (-not $script:remoteReady -or $script:remoteFaultLatched) {
        throw 'Remote ready marker did not clear the fault latch'
    }
    if ($gpuDivider -and -not $gpuDivider.RecoveryActive) {
        throw 'Remote recovery did not start the green flash'
    }

    Reset-CompactLogSession
    Clear-RemoteFault
    Process-RemoteLine '🔧 Received tool call failure_probe: begin'
    Process-RemoteLine '❌ Tool call failure_probe failed: synthetic failure'
    if (-not $script:remoteFaultLatched -or $script:remoteFaultKind -ne 'tool-failed') {
        throw 'Failed tool call did not latch fault mode'
    }
    Update-RemoteHealthFromLine 'Presence tracked (device test-device visible as online)'
    if (-not $script:remoteReady) {
        throw 'Presence confirmation did not restore transport readiness after tool failure'
    }
    if (-not $script:remoteFaultLatched -or $script:remoteFaultKind -ne 'tool-failed') {
        throw 'Presence confirmation incorrectly cleared an explicit tool failure'
    }
    Process-RemoteLine '🔧 Received tool call recovery_probe: begin'
    Process-RemoteLine '✅ Tool call recovery_probe completed:'
    if ($script:remoteFaultLatched -or -not $script:remoteReady) {
        throw 'Successful tool call did not clear prior tool failure and restore readiness'
    }
    if ($gpuDivider -and -not $gpuDivider.RecoveryActive) {
        throw 'Successful tool call after failure did not start recovery flash'
    }

    Reset-CompactLogSession
    $script:activityGapEwmaSeconds = 24.0
    $script:lastToolCompletedAt = (Get-Date).AddSeconds(-5)
    Process-RemoteLine '🔧 Received tool call max_hold_probe: begin'
    if ([Math]::Abs($script:activityHoldSeconds - 30.0) -gt 0.01) { throw 'Divider adaptive hold did not clamp at 30 seconds' }
    Process-RemoteLine '✅ Tool call max_hold_probe completed:'
    if (-not $script:activityHoldUntil -or
        ($script:activityHoldUntil - (Get-Date)).TotalSeconds -lt 29.0) {
        throw 'Divider completion hold did not use 30-second maximum'
    }

    Reset-CompactLogSession
    if ($gpuDivider) {
        if ($gpuDivider.GetType().Name -ne 'RdcGpuDividerHost') { throw 'Unexpected GPU divider control type' }
        if (-not $gpuDivider.PassConfigurationValid) { throw 'GPU particle pass configuration is coupled or invalid' }
        $visualMetrics = $gpuDivider.RunVisualSelfTest()
        if ($visualMetrics.StartsWith('offscreen-software-fallback;',[StringComparison]::Ordinal)) {
            Write-Output ('GPU VISUAL SELF TEST SKIPPED: ' + $visualMetrics)
        } else {
            Write-Output ('GPU VISUAL SELF TEST PASSED: ' + $visualMetrics)
        }
        $gpuDivider.SetActivity($false)
        $gpuDivider.SetInteractiveMove($true)
        $gpuDivider.SetInteractiveMove($false)
        Process-RemoteLine '🔧 Received tool call shader_test: begin'
        if ($script:activeToolCalls -ne 1 -or -not $gpuDivider.ActivityRequested) { throw 'GPU activity did not start on Received tool call' }
        Process-RemoteLine '✅ Tool call shader_test completed:'
        if ($script:activeToolCalls -ne 0 -or -not $gpuDivider.ActivityRequested) { throw 'GPU activity hold did not remain active after completion' }
        $script:activityHoldUntil = (Get-Date).AddMilliseconds(-1)
        Refresh-DividerActivitySession
        if ($gpuDivider.ActivityRequested) { throw 'GPU activity did not stop after hold expiry' }

        $gpuDivider.SetFault($true)
        $faultWatch = [Diagnostics.Stopwatch]::StartNew()
        while ($faultWatch.ElapsedMilliseconds -lt 750) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 15
        }
        $faultWatch.Stop()
        if ($gpuDivider.FaultBlend -lt 0.90) { throw 'Fault palette did not fade in smoothly' }

        $gpuDivider.BeginRecoveryFlash()
        $recoveryWatch = [Diagnostics.Stopwatch]::StartNew()
        while ($recoveryWatch.ElapsedMilliseconds -lt 260) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 15
        }
        if ($gpuDivider.RecoveryBlend -lt 0.85) { throw 'Recovery flash did not reach a strong green peak' }
        while ($recoveryWatch.ElapsedMilliseconds -lt 3200) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 15
        }
        $recoveryWatch.Stop()
        if ($gpuDivider.RecoveryActive -or $gpuDivider.RecoveryBlend -gt 0.05) {
            throw 'Recovery flash did not settle back to the normal palette'
        }
        $gpuDivider.SetStopped($true)
        if (-not $gpuDivider.StoppedVisualActive) { throw 'Stopped divider did not become quiet and neutral' }
        $gpuDivider.SetStopped($false)
        $gpuDivider.SimulateVisibilityPauseForTest($true)
        $gpuDivider.BeginRecoveryFlash()
        $gpuDivider.SimulateVisibilityPauseForTest($false)
        if ($gpuDivider.RecoveryActive -or $gpuDivider.RecoveryBlend -gt 0.001) {
            throw 'Restoring window replayed deferred green recovery pulse'
        }
    } else {
        Process-RemoteLine '🔧 Received tool call fallback_test: begin'
        Process-RemoteLine '✅ Tool call fallback_test completed:'
        if ($script:activeToolCalls -ne 0) { throw 'Static divider fallback broke activity state tracking' }
    }

    $shortcutTestRoot = Join-Path $env:TEMP ('RDCRelay-shortcut-selftest-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $shortcutTestRoot -Force | Out-Null
    try {
        $shortcutTestPath = Join-Path $shortcutTestRoot 'RDC Relay.lnk'
        $testShell = New-Object -ComObject WScript.Shell
        $testShortcut = $null
        try {
            $testShortcut = $testShell.CreateShortcut($shortcutTestPath)
            $testShortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
            $testShortcut.Arguments = '-File "' + (Join-Path $root 'remote-window.ps1') + '"'
            $testShortcut.WorkingDirectory = $shortcutTestRoot
            $testShortcut.IconLocation = (Join-Path $env:WINDIR 'notepad.exe') + ',0'
            $testShortcut.Description = 'stale'
            $testShortcut.Save()
        }
        finally {
            if ($testShortcut) {
                try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($testShortcut) } catch {}
            }
            try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($testShell) } catch {}
        }

        if (-not (Sync-RdcShortcuts @($shortcutTestRoot))) {
            throw 'Shortcut synchronization returned failure'
        }

        $verifyShell = New-Object -ComObject WScript.Shell
        $verifyShortcut = $null
        try {
            $verifyShortcut = $verifyShell.CreateShortcut($shortcutTestPath)
            $expectedShortcutTarget = Join-Path (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0') 'powershell.exe'
            $expectedShortcutArgs = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
                (Join-Path $root 'remote-window.ps1') + '"'

            if ($verifyShortcut.TargetPath -ne $expectedShortcutTarget) {
                throw 'Shortcut synchronization target mismatch'
            }
            if ($verifyShortcut.Arguments -ne $expectedShortcutArgs) {
                throw 'Shortcut synchronization arguments mismatch'
            }
            if ($verifyShortcut.IconLocation -notlike ((Join-Path $root ('RDCRelay-v' + $appVersion + '-*.ico')) + ',0')) {
                throw 'Shortcut synchronization icon mismatch'
            }
            if ($verifyShortcut.Description -ne 'RDC Relay') {
                throw 'Shortcut synchronization description mismatch'
            }
            # A portable copy must leave another installation's shortcut intact.
            $verifyShortcut.Arguments = '-File "C:\OtherRdcInstallation\remote-window.ps1"'
            $verifyShortcut.Save()
            $foreignHash = (Get-FileHash -LiteralPath $shortcutTestPath -Algorithm SHA256).Hash
            if (-not (Sync-RdcShortcuts @($shortcutTestRoot))) { throw 'Foreign shortcut check failed' }
            if ((Get-FileHash -LiteralPath $shortcutTestPath -Algorithm SHA256).Hash -ne $foreignHash) {
                throw 'Foreign installation shortcut was modified'
            }
        }
        finally {
            if ($verifyShortcut) {
                try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verifyShortcut) } catch {}
            }
            try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verifyShell) } catch {}
        }
    }
    finally {
        Remove-Item -LiteralPath $shortcutTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $root -Filter ('RDCRelay-v' + $appVersion + '-*.ico') -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Output 'GUI LOGIC SELF TEST PASSED'
    $form.Dispose()
    if ($windowMutex) { $windowMutex.ReleaseMutex(); $windowMutex.Dispose() }
    exit 0
}
if ($OwnerGui) {
    # The exact ORIGINAL product WinForms controls are already constructed.
    # Owner footer starts IDLE. The Owner timer checks the published stable
    # manifest asynchronously and shows the compact read-only notice ONLY
    # for a confirmed newer stable version; never fabricate 1.6.0 RC2.
    # The candidate updater/installer remains deliberately disabled.
    # Only the OwnerGui attach path runs the candidate remote-free IPC viewer.
    . (Join-Path $root 'rc1-owner-gui.ps1')
    Start-RdcOwnerGui
    exit 0
}
if ($Preview) {
    # Safe visual-only demonstration, never queries GitHub or installs anything.
    if ($script:enableUpdateNotice) {
        $previewBase = [Version]$appVersion
        $script:previewUpdateVersion = '{0}.{1}.{2}' -f $previewBase.Major,$previewBase.Minor,($previewBase.Build+1)
        $form.Add_Shown({ Start-RdcUpdateNoticePreview $script:previewUpdateVersion })
    }
    Set-State 'Предпросмотр' 'Анимация обновления повторяется каждые 7 секунд.' ([Drawing.Color]::LightBlue)
    Set-RuntimeDisplay 'Remote не запущен' 'Только предпросмотр' $true

    $previewBanner = @(
        '██████╗ ███████╗███████╗██╗  ██╗████████╗ ██████╗ ██████╗     ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ █████╗ ███╗   ██╗██████╗ ███████╗██████╗',
        '██╔══██╗██╔════╝██╔════╝██║ ██╔╝╚══██╔══╝██╔═══██╗██╔══██╗   ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝██╔══██╗',
        '██║  ██║█████╗  ███████╗█████╔╝    ██║   ██║   ██║██████╔╝   ██║     ██║   ██║██╔████╔██║██╔████╔██║███████║██╔██╗ ██║██║  ██║█████╗  ██████╔╝',
        '██║  ██║██╔══╝  ╚════██║██╔═██╗    ██║   ██║   ██║██╔═══╝    ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗',
        '██████╔╝███████╗███████║██║  ██╗   ██║   ╚██████╔╝██║        ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝███████╗██║  ██║',
        '╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝         ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝'
    )
    $script:startupBlock = [string]::Join($nl,$previewBanner) + $nl +
        'Remote Connection' + $nl +
        'Visual preview for banner line spacing and scroll rendering.'

    $previewLines = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -le 80; $i++) {
        [void]$previewLines.Add(
            ('{0:D2}  Vertical scroll probe  ' -f $i) +
            ('0123456789ABCDEF' * 4)
        )
    }
    Add-CompletedEvent ([string]::Join($nl,$previewLines))

    $wideLines = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -le 8; $i++) {
        [void]$wideLines.Add(
            ('W{0:D2}  Horizontal scroll probe  ' -f $i) +
            ('0123456789ABCDEF' * 24)
        )
    }
    Add-CompletedEvent ([string]::Join($nl,$wideLines))
    Render-CompactLog
    Set-DividerWorkState $true
    $timer.Start()
    try {
        [Windows.Forms.Application]::Run($form)
    }
    finally {
        if ($windowMutex) {
            try { $windowMutex.ReleaseMutex() } catch {}
            $windowMutex.Dispose()
        }
    }
    exit 0
}
$form.Add_Shown({ Start-RuntimeInitialization })
$timer.Start()
try {
    [Windows.Forms.Application]::Run($form)
}
finally {
    if ($windowMutex) {
        try { $windowMutex.ReleaseMutex() } catch {}
        $windowMutex.Dispose()
    }
}



