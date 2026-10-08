param([switch]$SelfTest,[switch]$SkipUpdate,[switch]$Preview)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appVersion = '1.5.13'
$desktopCommanderPackage = '@wonderwhy-er/desktop-commander@0.2.52'
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
    [void][RdcShellIdentity]::SetCurrentProcessExplicitAppUserModelID('RDCRelay.App')
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
        $key.SetValue('Publisher','UMAS',[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('InstallLocation',$root,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('DisplayIcon',$iconPath,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('URLInfoAbout','https://github.com/1rubass1/RDC-Relay',[Microsoft.Win32.RegistryValueKind]::String)
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
if (-not $SelfTest) {
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
    private GraphicsPath Rounded(RectangleF r, float radius) {
        GraphicsPath p = new GraphicsPath();
        float d = radius * 2f;
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
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

    protected override void OnPaint(PaintEventArgs e) {
        // Opaque controls do not receive the normal background paint pass.
        // Clear the complete client area here so no stale sibling pixels can survive.
        e.Graphics.Clear(BackColor);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

        bool activeHover = Enabled && hovered;
        bool activePress = Enabled && pressed;
        Color fill;
        Color edge;
        Color content;

        if (!Enabled) {
            fill = Color.FromArgb(49,53,59);
            edge = Color.FromArgb(82,84,88);
            content = Color.FromArgb(132,135,139);
        } else {
            fill = activePress ? Color.FromArgb(42,46,51)
                 : activeHover ? Color.FromArgb(61,66,72)
                 : Color.FromArgb(49,53,59);

            if (tone == RdcButtonTone.Neutral) {
                edge = activePress ? Color.FromArgb(139,81,45)
                     : activeHover ? Color.FromArgb(207,132,75)
                     : Color.FromArgb(191,118,67);
            } else {
                edge = activePress ? Color.FromArgb(139,81,45)
                     : activeHover ? Color.FromArgb(207,132,75)
                     : Color.FromArgb(191,118,67);
            }
            content = ForeColor;
        }

        RectangleF r = new RectangleF(1f,1f,Width-2f,Height-2f);
        using (GraphicsPath p = Rounded(r,6f))
        using (SolidBrush b = new SolidBrush(fill))
        using (Pen pen = new Pen(edge,1f)) {
            e.Graphics.FillPath(b,p);
            e.Graphics.DrawPath(pen,p);
        }

        TextFormatFlags flags =
            TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine |
            TextFormatFlags.NoPadding;
        Size textSize = TextRenderer.MeasureText(
            e.Graphics,Text,Font,new Size(Int32.MaxValue,Height),flags);

        if (glyph == RdcButtonGlyph.None) {
            TextRenderer.DrawText(
                e.Graphics,Text,Font,ClientRectangle,content,
                flags | TextFormatFlags.HorizontalCenter);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-5,-5), ForeColor, BackColor);
            return;
        }

        int iconSize = 12;
        int gap = 7;
        int groupWidth = iconSize + gap + textSize.Width;
        int left = Math.Max(5,(Width-groupWidth)/2);
        Rectangle iconRect = new Rectangle(
            left,
            (Height-iconSize)/2,
            iconSize,
            iconSize);
        DrawGlyph(e.Graphics,iconRect,content);

        Rectangle textRect = new Rectangle(
            iconRect.Right + gap,
            0,
            Math.Max(1,Width-(iconRect.Right+gap)-5),
            Height);
        TextRenderer.DrawText(
            e.Graphics,Text,Font,textRect,content,
            flags | TextFormatFlags.Left);
        if (Focused && ShowFocusCues)
            ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-5,-5), ForeColor, BackColor);
    }
}

public class RdcStatusIndicator : Control {
    private Color indicatorColor = Color.Gray;
    public Color IndicatorColor {
        get { return indicatorColor; }
        set { indicatorColor = value; Invalidate(); }
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
        int diameter = 18;
        int x = (Width - diameter) / 2;
        int y = (Height - diameter) / 2;
        using (SolidBrush b = new SolidBrush(indicatorColor))
            e.Graphics.FillEllipse(b, x, y, diameter, diameter);
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

        // Match the real RdcOverlayScrollBar arrow geometry exactly so the
        // switch into/out of drag preview does not visibly change scale.
        using (SolidBrush arrows = new SolidBrush(
            Color.FromArgb(rulerAlpha,112,115,120))) {
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
            e.Graphics.FillPolygon(arrows,down);
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
        if (length <= 0 || !IsHandleCreated) return;

        int oldStart = SelectionStart;
        int oldLength = SelectionLength;
        try {
            float dpiY;
            float linePx;
            using (Graphics g = CreateGraphics()) {
                dpiY = g.DpiY;
                linePx = Math.Max(1f,Font.GetHeight(g)-Math.Max(0f,subtractPixels));
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

    public bool StyleStartupBanner(Color leftColor, Color rightColor) {
        const string marker = "Remote Connection";
        string all = Text;
        int markerIndex = all.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (markerIndex <= 0) return false;

        string prefix = all.Substring(0, markerIndex);
        string[] lines = prefix.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n');
        System.Collections.Generic.List<string> banner = new System.Collections.Generic.List<string>();
        for (int i = 0; i < lines.Length; i++) {
            if (!String.IsNullOrWhiteSpace(lines[i])) banner.Add(lines[i]);
        }
        if (banner.Count < 6) return false;

        string[] target = banner.GetRange(banner.Count - 6, 6).ToArray();
        SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
        try {
            int searchFrom = 0;
            int bannerStart = -1;
            int bannerEnd = -1;
            foreach (string line in target) {
                int start = all.IndexOf(line, searchFrom, StringComparison.Ordinal);
                if (start < 0) continue;
                if (bannerStart < 0) bannerStart = start;
                bannerEnd = Math.Max(bannerEnd,start + line.Length);

                int split = Math.Min(61, line.Length);
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

            if (bannerStart >= 0 && bannerEnd > bannerStart)
                ApplyExactLineSpacing(bannerStart,bannerEnd-bannerStart,1.0f);

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
        Point focusView = new Point(-1,-1);
        if (m.Msg == WM_SETFOCUS && IsHandleCreated) {
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

            if ((keyState & MK_CONTROL) != 0) {
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
        bool restoreView = preserveViewAfterFocusClick;
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
        if (e.Control &&
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
        if (ReadOnly && e.KeyChar != (char)3) {
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

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Color.FromArgb(18,20,23));
        using (Pen p = new Pen(Color.FromArgb(191,118,67),1.4f)) {
            e.Graphics.DrawLine(p,10,15,15,10);
            e.Graphics.DrawLine(p,6,15,15,6);
            e.Graphics.DrawLine(p,2,15,15,2);
        }
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

public class RdcOverlayScrollBar : Control {
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
        using (SolidBrush tb = new SolidBrush(Color.FromArgb(50,52,56)))
            e.Graphics.FillPath(tb,tp);

        Color thumbColor = dragging
            ? Color.FromArgb(166,98,55)
            : hoverThumb
                ? Color.FromArgb(207,132,75)
                : Color.FromArgb(191,118,67);
        using (GraphicsPath hp = Rounded(thumb, Math.Min(7, Math.Min(thumb.Width,thumb.Height)/2)))
        using (SolidBrush hb = new SolidBrush(thumbColor))
            e.Graphics.FillPath(hb,hp);

        using (SolidBrush ab = new SolidBrush(Color.FromArgb(112,115,120))) {
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
    public static readonly DependencyProperty StoppedProperty =
        DependencyProperty.Register("Stopped", typeof(double), typeof(RdcDividerGlowEffect),
            new UIPropertyMetadata(0.0, PixelShaderConstantCallback(8)));
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
        UpdateShaderValue(StoppedProperty);
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

    const int GWL_EXSTYLE = -20;
    const int GWLP_HWNDPARENT = -8;
    const int WS_EX_TOPMOST = 0x00000008;
    const int WS_EX_TRANSPARENT = 0x00000020;
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
                    !IsCloaked(above)) {

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

    private bool ShouldPauseRendering() {
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

        if (renderPaused || interactiveMove) {
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
        if (renderPaused == paused)
            return;

        renderPaused = paused;

        if (paused) {
            animationTimer.Stop();
            popupRoot.Opacity = 0.0;
            return;
        }

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
        if (!particlePopup.IsOpen || particlePopupHwnd == IntPtr.Zero || !IsHandleCreated) return;

        RECT rect;
        if (!GetWindowRect(Handle,out rect)) return;
        int w = Math.Max(1,rect.Right-rect.Left);
        int h = 33;
        int x = rect.Left;
        int y = rect.Top - 13;
        if (x==lastPopupX && y==lastPopupY && w==lastPopupW && h==lastPopupH) return;
        lastPopupX=x; lastPopupY=y; lastPopupW=w; lastPopupH=h;
        SetWindowPos(
            particlePopupHwnd,
            IntPtr.Zero,
            x,y,w,h,
            SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW);
    }

    private void EnsurePopupOpen() {
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
            double w=Math.Max(1.0,root.ActualWidth);
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
            if (particlePopup.IsOpen) particlePopup.Width=w;
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

    public int RenderTier { get { return RenderCapability.Tier; } }
    public double ActivityLevel { get { return activity; } }
    public bool ActivityRequested { get { return targetActivity > 0.5; } }
    public bool FaultRequested { get { return faultMode; } }
    public double FaultBlend { get { return faultBlend; } }
    public bool StartupRequested { get { return startupMode; } }
    public double StartupBlend { get { return startupBlend; } }
    public double RecoveryBlend { get { return recoveryBlend; } }
    public bool RecoveryActive { get { return recoveryActive; } }
    public bool RenderingPaused { get { return renderPaused; } }
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
            targetActivity=0.10;
            activity=Math.Max(activity,0.10);
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

    protected override void OnResize(EventArgs e) {
        base.OnResize(e);
        double w=Math.Max(1.0,ClientSize.Width);
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
        if (particlePopup.IsOpen) particlePopup.Width=w;
    }

    protected override void Dispose(bool disposing) {
        if (disposing) {
            animationTimer.Stop();
            animationTimer.Tick-=Animate;
            visibilityTimer.Stop();
            visibilityTimer.Tick-=VisibilityTimer_Tick;
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

[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'RDC Relay'
$baseWindowWidth = 1074
$baseWindowHeight = 900
$paneMinHeightPreferred = 125
$startupScreen = [Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position)
$startupWorkArea = $startupScreen.WorkingArea
$windowWidth = [Math]::Min($baseWindowWidth,$startupWorkArea.Width)
$windowHeight = [Math]::Min($baseWindowHeight,$startupWorkArea.Height)
$form.Size = New-Object Drawing.Size($windowWidth,$windowHeight)
$preferredMinimumHeight = 78 + 38 + (2 * $paneMinHeightPreferred) + 7 + 48
$minimumWindowHeight = [Math]::Min($windowHeight,$preferredMinimumHeight)
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
$top.Padding = New-Object Windows.Forms.Padding(16,9,16,9)
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
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,304)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$statusDot = New-Object RdcStatusIndicator
$statusDot.Dock = 'Fill'
$statusDot.IndicatorColor = [Drawing.Color]::Gray
$title = New-Object Windows.Forms.Label
$title.Text = 'RDC Relay'
$title.Dock = 'Fill'
$title.TextAlign = 'MiddleLeft'
$title.Font = New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
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

$accountButton = New-Object RdcRoundedButton
$accountButton.BackColor = $form.BackColor
$accountButton.Text = 'Аккаунт ▾'
$accountButton.Tone = [RdcButtonTone]::Neutral
$accountButton.Size = New-Object Drawing.Size(120,36)
$accountButton.Margin = New-Object Windows.Forms.Padding(0)

$helpButton = New-Object RdcCircleButton
$helpButton.BackColor = $form.BackColor
$helpButton.Text = '?'
$helpButton.AccessibleName = 'Справка и журнал'
$finish.TabIndex = 0
$accountButton.TabIndex = 1
$helpButton.TabIndex = 2
$helpButton.Size = New-Object Drawing.Size(36,36)
$helpButton.Margin = New-Object Windows.Forms.Padding(4,0,0,0)

$actions = New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'
$actions.BackColor = $form.BackColor
$actions.FlowDirection = 'RightToLeft'
$actions.WrapContents = $false
$actions.Margin = New-Object Windows.Forms.Padding(0)
$actions.Padding = New-Object Windows.Forms.Padding(0,12,0,12)
$actions.Controls.Add($finish)
$actions.Controls.Add($helpButton)
$actions.Controls.Add($accountButton)

$tip = New-Object Windows.Forms.ToolTip
$tip.SetToolTip($accountButton,'Действия с аккаунтом')
$tip.SetToolTip($helpButton,'Справка и журнал')

$menuColors = New-Object RdcMenuColorTable
$menuRenderer = New-Object Windows.Forms.ToolStripProfessionalRenderer -ArgumentList $menuColors

$accountMenu = New-Object Windows.Forms.ContextMenuStrip
$accountMenu.BackColor = [Drawing.Color]::FromArgb(38,41,46)
$accountMenu.ForeColor = [Drawing.Color]::Gainsboro
$accountMenu.Renderer = $menuRenderer
$switchAccountItem = New-Object Windows.Forms.ToolStripMenuItem
$switchAccountItem.Text = 'Сменить аккаунт…'
$reconnectItem = New-Object Windows.Forms.ToolStripMenuItem
$reconnectItem.Text = 'Переподключить'
$devicesItem = New-Object Windows.Forms.ToolStripMenuItem
$devicesItem.Text = 'Управление устройствами…'
[void]$accountMenu.Items.Add($switchAccountItem)
[void]$accountMenu.Items.Add($reconnectItem)
[void]$accountMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void]$accountMenu.Items.Add($devicesItem)

$top.Controls.Add($statusDot,0,0)
$top.SetRowSpan($statusDot,2)
$top.Controls.Add($title,1,0)
$top.Controls.Add($statusDetail,1,1)
$top.Controls.Add($actions,2,0)
$top.SetRowSpan($actions,2)
$bottom = New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock = 'Bottom'
$bottom.Height = 38
$bottom.BackColor = $form.BackColor
$bottom.Padding = New-Object Windows.Forms.Padding(12,7,12,6)
$bottom.ColumnCount = 2
$bottom.RowCount = 1
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,440)))
$accentOrange = [Drawing.Color]::FromArgb(191,118,67)
$accentPurple = [Drawing.Color]::FromArgb(74,55,103)
$statusGreen = [Drawing.Color]::LightGreen
$accentWait = [Drawing.Color]::Khaki
$accentNetwork = [Drawing.Color]::LightSkyBlue
$accentStorage = [Drawing.Color]::LightSteelBlue
$accentPresence = [Drawing.Color]::Plum
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

$infoHost.Controls.Add($accountInfo)
$infoHost.Controls.Add($accountSep)
$infoHost.Controls.Add($runtimeLeft)
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
$hint.Text = 'Крестик закрывает окно вместе с remote-процессом.'
$hint.ForeColor = [Drawing.Color]::Gray
$hint.Margin = New-Object Windows.Forms.Padding(0,2,0,0)

$hintSep = New-Object Windows.Forms.Label
$hintSep.AutoSize = $true
$hintSep.Text = '•'
$hintSep.ForeColor = $accentOrange
$hintSep.Margin = New-Object Windows.Forms.Padding(6,2,6,0)

$hintVersion = New-Object Windows.Forms.Label
$hintVersion.AutoSize = $true
$hintVersion.Text = 'v' + $appVersion
$hintVersion.ForeColor = [Drawing.Color]::Gray
$hintVersion.Margin = New-Object Windows.Forms.Padding(0,2,0,0)

$hintHost.Controls.Add($hint)
$hintHost.Controls.Add($hintSep)
$hintHost.Controls.Add($hintVersion)

$bottom.Controls.Add($infoHost,0,0)
$bottom.Controls.Add($hintHost,1,0)
$tip.SetToolTip($accountInfo,'Аккаунт Desktop Commander, к которому привязан этот компьютер')

$contentHost = New-Object Windows.Forms.TableLayoutPanel
$contentHost.Dock = 'Fill'
$contentHost.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$contentHost.Margin = New-Object Windows.Forms.Padding(0)
$contentHost.Padding = New-Object Windows.Forms.Padding(0)
$contentHost.ColumnCount = 1
$contentHost.RowCount = 2
$activityDefaultHeight = $paneMinHeightPreferred
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
$headerLog.ReadOnly = $true
$headerLog.TabStop = $false
$headerLog.BackColor = [Drawing.Color]::FromArgb(18,20,23)
$headerLog.ForeColor = [Drawing.Color]::Gainsboro
$headerLog.Font = New-Object Drawing.Font('Consolas',9)
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
        $gpuDivider = $null
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

$headerTextHost.Controls.Add($headerLog,0,0)
$headerTextHost.Controls.Add($headerVScroll,1,0)
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
$log.Font = New-Object Drawing.Font('Consolas',10)
$log.WordWrap = $false
$log.BorderStyle = 'None'
$log.ScrollBars = [Windows.Forms.RichTextBoxScrollBars]::None
$log.DetectUrls = $true
$log.Add_LinkClicked({ try { Start-Process $_.LinkText } catch {} })

$vScroll = New-Object RdcOverlayScrollBar
$vScroll.Target = $log
$vScroll.Vertical = $true
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
    $available = [Math]::Max(1,$contentHost.ClientSize.Height)
    $half = [Math]::Max(48,[int][Math]::Floor($available / 2))
    return [Math]::Min($paneMinHeightPreferred,$half)
}
function Get-ClampedActivityPaneHeight([double]$requestedHeight) {
    $paneMinHeight = Get-EffectivePaneMinHeight
    $maxHeight = [Math]::Max($paneMinHeight,($contentHost.ClientSize.Height - $paneMinHeight))
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
$logHost.Add_Resize({ Layout-LogScrollbars })
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
})
$scrollCorner.Add_MouseCaptureChanged({
    if (-not $scrollCorner.Capture) {
        $script:uiInteracting = $false
        Layout-LogScrollbars
        Stop-LogResizeInteraction
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
    $runtimeSep.Visible = $showSeparator
    $runtimeRight.Visible = -not [string]::IsNullOrWhiteSpace($right)
}
function Set-AccountDisplay([string]$email) {
    if ([string]::IsNullOrWhiteSpace($email)) {
        $script:accountEmail = $null
        $accountInfo.Text = 'не определён'
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
function Update-RemoteHealthFromLine([string]$line) {
    if ($script:manualStopRequested -or $script:stopping) { return }
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    if (
        $line.IndexOf('Desktop Commander Remote is connected',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Presence tracked (device ',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        (
            $script:remoteFaultKind -eq 'local-mcp' -and
            $line.IndexOf('Local Desktop Commander MCP restarted; device is online again',[StringComparison]::OrdinalIgnoreCase) -ge 0
        )
    ) {
        # A joined realtime channel is only half-ready. Upstream considers the
        # device reachable only after Presence/capability publication succeeds
        # and the local executor is healthy.
        Mark-RemoteReady $line
        return
    }

    if (
        $line.IndexOf('Authenticating with Remote MCP server',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('waiting for authentication',[StringComparison]::OrdinalIgnoreCase) -ge 0
    ) {
        $script:remoteInteractiveAuth = $true
        $script:remoteConnectDeadline = $null
        return
    }

    if (
        $line.IndexOf('Remote session expired and could not be renewed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Restart the terminal running Desktop Commander to reconnect',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('This device is now offline for remote calls',[StringComparison]::OrdinalIgnoreCase) -ge 0
    ) {
        Set-RemoteFault 'session-lost' 'Remote MCP потерял сессию и требует перезапуска.' $true
        return
    }

    if ($line.IndexOf('Device startup failed:',[StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Set-RemoteFault 'startup-failed' 'Desktop Commander не смог завершить запуск Remote MCP.' $true
        return
    }

    if (
        $line.IndexOf('Local Desktop Commander MCP went away (',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Could not restart local Desktop Commander MCP:',[StringComparison]::OrdinalIgnoreCase) -ge 0
    ) {
        Set-RemoteFault 'local-mcp' 'Локальный Desktop Commander MCP потерял соединение; ожидаю встроенный перезапуск executor.' $false
        $script:remoteConnectDeadline = $null
        return
    }

    if (
        -not $script:stopping -and (
            $line.IndexOf('Channel error:',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Channel closed',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $line.IndexOf('Device marked as offline',[StringComparison]::OrdinalIgnoreCase) -ge 0
        )
    ) {
        # Realtime transport faults are recoverable inside Desktop Commander.
        # Keep the process alive and stay red until Presence is published again.
        Set-RemoteFault 'transport-offline' 'Сетевой канал Remote MCP потерян; ожидаю встроенное восстановление.' $false
        $script:remoteConnectDeadline = $null
        return
    }

    if (
        $line.IndexOf('Device registered, but NOT reachable',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Realtime channel is not open',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Channel subscription timed out',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Presence track remained unavailable',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $line.IndexOf('Presence published but the device row could not be updated',[StringComparison]::OrdinalIgnoreCase) -ge 0
    ) {
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
    while ($script:eventBlocks.Count -gt 6) { $script:eventBlocks.RemoveAt(0) }
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
function Render-CompactLog {
    if (-not $log -or $log.IsDisposed -or -not $headerLog -or $headerLog.IsDisposed) { return }

    $headerDisplay = if ([string]::IsNullOrWhiteSpace($script:startupBlock)) { '' } else { $script:startupBlock.TrimEnd() }
    if ($script:lastRenderedHeader -cne $headerDisplay) {
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
                $headerLog.SelectionColor = [Drawing.Color]::Gainsboro
            }
            if ($headerDisplay -like '*Remote Connection*') {
                [void]$headerLog.StyleStartupBanner(
                    [Drawing.Color]::FromArgb(123,95,162),
                    $accentOrange
                )
            }
            # Apply the same 1 px RichEdit paragraph tightening that removed the
            # horizontal seams in the startup banner to the entire header text,
            # including Unicode box-drawing blocks such as Next / Commands.
            $headerLog.ApplyCompactLineSpacing()
            Color-HeaderSemantics $headerLog $headerLog.TextLength
            Color-LogToken $headerLog '🔧' $accentOrange
            Color-LogToken $headerLog '🚀' $accentOrange
            Color-LogToken $headerLog '✅' $accentPurple
            Color-LogToken $headerLog '🔌' $statusGreen
            Color-LogToken $headerLog '⏳' $accentWait
            Color-LogToken $headerLog '🌐' $accentNetwork
            Color-LogToken $headerLog '💾' $accentStorage
            Color-LogToken $headerLog '👋' $accentPresence

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
    if ($visible.Count -gt 6) { $visible = $visible[($visible.Count-6)..($visible.Count-1)] }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $visible) {
        if (-not [string]::IsNullOrWhiteSpace($item)) { [void]$parts.Add($item.TrimEnd()) }
    }
    $display = [string]::Join(($nl+$nl),$parts)
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
        Color-LogToken $log '🔧' $accentOrange
        Color-LogToken $log '🚀' $accentOrange
        Color-LogToken $log '✅' $accentPurple
        Color-LogToken $log '❌' ([Drawing.Color]::LightCoral)
        Color-LogToken $log '🔌' $statusGreen
        Color-LogToken $log '⏳' $accentWait
        Color-LogToken $log '🌐' $accentNetwork
        Color-LogToken $log '💾' $accentStorage
        Color-LogToken $log '👋' $accentPresence

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
    $receivedPrefix = '🔧 '
    $completedPrefix = '✅ '
    $failedPrefix = '❌ '
    $isReceived =
        $line.StartsWith($receivedPrefix,[StringComparison]::Ordinal) -and
        $line.IndexOf('Received tool call ',[StringComparison]::Ordinal) -eq $receivedPrefix.Length
    $isCompleted =
        $line.StartsWith($completedPrefix,[StringComparison]::Ordinal) -and
        $line.IndexOf('Tool call ',[StringComparison]::Ordinal) -eq $completedPrefix.Length -and
        $line.IndexOf(' completed:',[StringComparison]::Ordinal) -gt $completedPrefix.Length
    $isFailed =
        $line.StartsWith($failedPrefix,[StringComparison]::Ordinal) -and
        $line.IndexOf('Tool call ',[StringComparison]::Ordinal) -eq $failedPrefix.Length -and
        $line.IndexOf(' failed:',[StringComparison]::Ordinal) -gt $failedPrefix.Length
    $isMarker = $isReceived -or $isCompleted -or $isFailed

    # Health markers must come from Desktop Commander's own lifecycle stream.
    # Tool request envelopes and serialized tool results can legitimately contain
    # strings such as "Channel error:" while inspecting source/logs. Treating
    # those payloads as transport telemetry leaves the UI falsely latched red.
    $healthProbe = $line.TrimStart()
    $isSerializedToolPayload =
        $healthProbe.StartsWith('{',[StringComparison]::Ordinal) -or
        $healthProbe.StartsWith('[',[StringComparison]::Ordinal)
    if (-not $isMarker -and -not $isSerializedToolPayload) {
        Update-RemoteHealthFromLine $line
    }

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
    Open-Reader
    if ($script:reader) {
        Move-ReaderToRecentTailIfBehind
        $chunk = [RdcLogBox]::ReadChunk($script:reader,$logReadChunkChars)
        if ($chunk) { Add-RemoteChunk $chunk }
    }
}
function Find-ExistingRemote {
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
        return ($tail -match '(?i)Cannot find module.*[\\/]@wonderwhy-er[\\/]desktop-commander[\\/]dist/index\\.js')
    } catch { return $false }
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
    if ($script:remoteOperation -or $script:initializing) { return }
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
    $answer = [Windows.Forms.MessageBox]::Show(
        'RDC Relay будет кратковременно отключён и запущен снова под текущим аккаунтом.',
        'Переподключить RDC Relay', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $script:autoReconnectAttempt = 0
    $script:autoReconnectAt = $null
    $script:preserveFaultOnStop = $script:remoteFaultLatched
    Begin-RemoteOperation 'restart'
}

function Switch-RemoteAccount {
    $message = 'Смена аккаунта разорвёт текущее удалённое соединение.' + $nl + $nl +
        'После выхода RDC Relay запустится снова и предложит авторизоваться в браузере.' + $nl + $nl +
        'Войдите в тот же аккаунт Desktop Commander, который подключён в ChatGPT.' + $nl + $nl + 'Продолжить?'
    $answer = [Windows.Forms.MessageBox]::Show($message,'Сменить аккаунт Desktop Commander',
        [Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    Begin-RemoteOperation 'logout'
}

function Start-RuntimeInitialization {
    $script:initializing = $true
    Set-RemoteActionsEnabled $false
    $updaterPath = Join-Path $root 'update.ps1'
    if (-not $SkipUpdate -and (Test-Path -LiteralPath $updaterPath)) {
        try {
            Set-State 'Проверка обновлений…' 'Проверяю установленную версию; окно остаётся доступным.' ([Drawing.Color]::Khaki)
            $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $updaterPath + '"'),'-InstallRoot',('"' + $root + '"'),'-CurrentVersion',$appVersion)
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
    $script:initializing = $false
    Set-RemoteActionsEnabled $true
    if ($script:closeRequested) { $script:allowClose = $true; $form.Close(); return }
    Hide-LegacyRemoteTerminal
    Start-Remote
}

$finish.Add_Click({
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
$accountButton.Add_Click({
    $accountMenu.Show($accountButton,(New-Object Drawing.Point(0,$accountButton.Height)))
})
$switchAccountItem.Add_Click({ Switch-RemoteAccount })
$reconnectItem.Add_Click({ Restart-Remote })
$devicesItem.Add_Click({
    try { Start-Process 'https://mcp.desktopcommander.app/' } catch {}
})
$helpMenu = New-Object Windows.Forms.ContextMenuStrip
$helpMenu.BackColor = [Drawing.Color]::FromArgb(38,41,46)
$helpMenu.ForeColor = [Drawing.Color]::Gainsboro
$helpMenu.Renderer = $menuRenderer

$aboutItem = New-Object Windows.Forms.ToolStripMenuItem
$aboutItem.Text = 'Справка / О программе'

$openLogItem = New-Object Windows.Forms.ToolStripMenuItem
$openLogItem.Text = 'Открыть журнал'

[void]$helpMenu.Items.Add($aboutItem)
[void]$helpMenu.Items.Add($openLogItem)

$helpButton.Add_Click({
    $helpMenu.Show($helpButton,(New-Object Drawing.Point(10,$helpButton.Height)))
})

$aboutItem.Add_Click({
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
        'Пароли и токены эта оболочка не копирует и не хранит.'
    [Windows.Forms.MessageBox]::Show(
        $helpText,
        'RDC Relay — справка',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
})

$openLogItem.Add_Click({
    try {
        if (-not (Test-Path $logPath)) {
            [Windows.Forms.MessageBox]::Show(
                'Журнал ещё не создан.',
                'RDC Relay — журнал',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }
        $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
        Start-Process -FilePath $notepad -ArgumentList ('"' + $logPath + '"')
    } catch {
        [Windows.Forms.MessageBox]::Show(
            ('Не удалось открыть журнал.' + $nl + $nl + $_.Exception.Message),
            'RDC Relay — журнал',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})
function Refresh-Window {
    if ($script:initializing) { Complete-RuntimeInitialization; return }
    if ($script:remoteOperation) { Update-RemoteOperation; return }
    Apply-SystemFrameTheme

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
                        'Завершите вход в браузере; автоматический таймаут приостановлен.'
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
    Layout-LogScrollbars
    try { $log.RefreshViewport() } catch {}
    Refresh-Window
})

$form.Add_FormClosing({
    param($sender,$e)
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
            $runtimeSourceText.IndexOf('$headerLog.ApplyCompactLineSpacing()',[StringComparison]::Ordinal) -lt 0 -or
            $runtimeSourceText.IndexOf('$log.ApplyCompactLineSpacing()',[StringComparison]::Ordinal) -lt 0) {
            throw 'Global RichEdit compact line spacing regressed'
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
    if ($helpButton.Text -ne '?') { throw 'Help button missing' }
    if ($accountMenu.Items.Count -lt 4) { throw 'Account menu missing' }
    if ($reconnectItem.Text -ne 'Переподключить') { throw 'Reconnect account action missing' }
    if ($helpMenu.Items.Count -ne 2) { throw 'Help menu missing' }
    if ($openLogItem.Text -ne 'Открыть журнал') { throw 'Open log action missing' }
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
    if (-not $bannerProbe.StyleStartupBanner([Drawing.Color]::FromArgb(123,95,162),[Drawing.Color]::FromArgb(191,118,67))) { throw 'Startup banner styling failed' }
    $bannerProbe.Select(0,1)
    if ($bannerProbe.SelectionColor.ToArgb() -ne [Drawing.Color]::FromArgb(123,95,162).ToArgb()) { throw 'Startup banner purple color mismatch' }
    $bannerProbe.Select(61,1)
    if ($bannerProbe.SelectionColor.ToArgb() -ne [Drawing.Color]::FromArgb(191,118,67).ToArgb()) { throw 'Startup banner orange color mismatch' }
    $bannerProbe.Dispose()
    if ($hintSep.Text -ne '•') { throw 'Bottom separator missing' }
    if ($runtimeSep.Text -ne '|') { throw 'Runtime separator missing' }
    $npxProbe = Resolve-NpxPath
    if (-not $npxProbe -or -not (Test-Path -LiteralPath $npxProbe)) { throw 'npx resolver failed' }
    if ($desktopCommanderPackage -ne '@wonderwhy-er/desktop-commander@0.2.52') { throw 'Unexpected Desktop Commander package pin' }
    if ($hintSep.ForeColor.ToArgb() -ne $accentOrange.ToArgb()) { throw 'Bottom separator color mismatch' }
    if ($runtimeSep.ForeColor.ToArgb() -ne $accentOrange.ToArgb()) { throw 'Runtime separator color mismatch' }
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
    if (($contentHost.ClientSize.Height - $contentHost.RowStyles[1].Height) -lt ($testPaneMin-1)) { throw 'Header minimum height clamp failed' }
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
    if($log.SelectionColor.ToArgb() -ne $accentPurple.ToArgb()){throw 'Check marker color mismatch'}
    foreach($probe in @(
        @('🔌',$statusGreen,'Plug marker color mismatch'),
        @('⏳',$accentWait,'Wait marker color mismatch'),
        @('🌐',$accentNetwork,'Network marker color mismatch'),
        @('💾',$accentStorage,'Storage marker color mismatch'),
        @('👋',$accentPresence,'Presence marker color mismatch'),
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
if ($Preview) {
    Set-State 'Предпросмотр' 'Dev preview без запуска remote-процесса.' ([Drawing.Color]::LightBlue)

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
