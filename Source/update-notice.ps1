# RDC Relay optional update-notification feature.
# Disable with $script:enableUpdateNotice = $false in remote-window.ps1.
# No network traffic, updater execution or UI replacement occurs until explicitly enabled.
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public sealed class RdcUpdateNoticeStrip : Control {
    private readonly Stopwatch watch = new Stopwatch();
    private readonly Font buttonFont = new Font("Segoe UI", 9.5f, FontStyle.Bold);
    private const int DefaultWidth = 440;
    private const int ExtraWidth = 150;
    // 300 ms connected move, 280 ms arrow reveal, then 230 ms button fade.
    // Only the -Preview replays the sequence; production plays it once.
    private const double MoveDuration = 0.30;
    private const double ArrowStart = 0.23;
    private const double ArrowDuration = 0.28;
    private const double ButtonFadeStart = 0.48;
    private const double ButtonFadeDuration = 0.23;
    private string installed = "";
    private string offered = "";
    private string note = "Крестик закрывает окно вместе с remote-процессом.";
    private Rectangle buttonBounds = Rectangle.Empty;
    private bool hovered, pressed, installing, forceFinish, active;

    public RdcUpdateNoticeStrip() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque | ControlStyles.Selectable, true);
        SetStyle(ControlStyles.StandardClick | ControlStyles.StandardDoubleClick, false);
        BackColor = Color.FromArgb(29,32,36);
        ForeColor = Color.FromArgb(128,128,128);
        TabStop = false;
        AccessibleRole = AccessibleRole.StaticText;
    }

    // The same control paints both idle and update states. Keeping it attached
    // avoids reparenting/autoscaling text or vertically shifting the footer.
    public void SetIdle(string installedVersion,string normalHint) {
        watch.Reset();
        active = false;
        installed = installedVersion;
        offered = "";
        note = normalHint;
        AccessibleRole = AccessibleRole.StaticText;
        AccessibleName = "RDC Relay v" + installed;
        hovered = false;
        pressed = false;
        installing = false;
        buttonBounds = Rectangle.Empty;
        Cursor = Cursors.Default;
        Invalidate();
    }

    public void Begin(string installedVersion,string offeredVersion,string normalHint) {
        active = true;
        installed = installedVersion;
        offered = offeredVersion;
        note = normalHint;
        installing = false;
        hovered = false;
        pressed = false;
        forceFinish = false;
        AccessibleRole = AccessibleRole.PushButton;
        AccessibleName = "Установить RDC Relay v" + offered;
        watch.Restart();
        Invalidate();
    }

    public void End() {
        watch.Reset();
        active = false;
        AccessibleRole = AccessibleRole.StaticText;
        AccessibleName = "RDC Relay v" + installed;
        forceFinish = false;
        pressed = false;
        hovered = false;
        installing = false;
        buttonBounds = Rectangle.Empty;
        Cursor = Cursors.Default;
        Invalidate();
    }
    public bool IsActive { get { return active; } }
    public bool Installing { get { return installing; } set { installing=value; Invalidate(); } }
    public string OfferedVersion { get { return offered; } }
    public bool AnimationComplete { get { return active && Elapsed >= 0.75; } }
    public bool ButtonReady { get { return active && Elapsed >= 0.73 && !installing; } }
    public int SuggestedWidth { get { return active ? DefaultWidth + (int)Math.Round(ExtraWidth*Ease(Elapsed/MoveDuration)) : DefaultWidth; } }
    public void FinishAnimationForTest() { forceFinish=true; Invalidate(); }
    private double Elapsed { get { return forceFinish ? 1.0 : watch.Elapsed.TotalSeconds; } }
    private static double Clamp(double x) { return Math.Max(0.0,Math.Min(1.0,x)); }
    private static double Ease(double x) { double t=Clamp(x); return 1.0-Math.Pow(1.0-t,3.0); }

    private static GraphicsPath Rounded(Rectangle r,int rad) {
        GraphicsPath p=new GraphicsPath();
        float d=rad*2;
        // Inset the geometric contour by > half the pen width on every side.
        // A centered stroke remains fully inside the 25px footer at any DPI.
        RectangleF rf=new RectangleF(r.Left+1.5f,r.Top+1.5f,r.Width-3f,r.Height-3f);
        p.AddArc(rf.Left,rf.Top,d,d,180,90);
        p.AddArc(rf.Right-d,rf.Top,d,d,270,90);
        p.AddArc(rf.Right-d,rf.Bottom-d,d,d,0,90);
        p.AddArc(rf.Left,rf.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g=e.Graphics;
        g.Clear(BackColor);
        if (Width < 10 || Height < 10) return;
        g.SmoothingMode=SmoothingMode.AntiAlias;
        g.PixelOffsetMode=PixelOffsetMode.HighQuality;
        TextFormatFlags tf=TextFormatFlags.NoPadding |
            TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter;
        int hintWidth=TextRenderer.MeasureText(g,note,Font,new Size(10000,Height),tf).Width;
        int sepWidth=TextRenderer.MeasureText(g,"•",Font,new Size(10000,Height),tf).Width;
        string oldText="v"+installed;
        int oldWidth=TextRenderer.MeasureText(g,oldText,Font,new Size(10000,Height),tf).Width;
        string newText="v"+offered;
        int buttonWidth=Math.Max(84,TextRenderer.MeasureText(g,newText,buttonFont,
            new Size(10000,Height),tf).Width+22);
        int hintX=Width-hintWidth;
        int sepX=hintX-6-sepWidth-6;
        int originalVersionX=sepX-6-oldWidth;
        int buttonX=sepX-7-buttonWidth;
        int arrowXFinal=buttonX-7-19;
        int targetVersionX=arrowXFinal-7-oldWidth;
        double elapsed=active ? Elapsed : 0.0;
        double move=Ease(elapsed/MoveDuration);
        double arrow=Ease((elapsed-ArrowStart)/ArrowDuration);
        double buttonAlpha=Clamp((elapsed-ButtonFadeStart)/ButtonFadeDuration);
        int versionX=originalVersionX-
            (int)Math.Round((originalVersionX-targetVersionX)*move);
        int arrowX=sepX-8-(int)Math.Round((sepX-8-arrowXFinal)*arrow);
        int y=0;
        Color muted=Color.FromArgb(128,128,128);
        Color orange=Color.FromArgb(191,118,67);

        // Fixed anchor: original close hint and orange bullet never move.
        TextRenderer.DrawText(g,note,Font,new Rectangle(hintX,y,hintWidth,Height),
            muted,tf);
        TextRenderer.DrawText(g,"•",Font,new Rectangle(sepX,y,sepWidth,Height),
            orange,tf);
        TextRenderer.DrawText(g,oldText,Font,
            new Rectangle(versionX,y,oldWidth,Height),muted,tf);

        // Arrow emerges from behind the separator; everything is clipped to
        // the separator's left boundary, so the original hint remains untouched.
        if (arrow > 0.001) {
            GraphicsState save=g.Save();
            g.SetClip(new Rectangle(0,0,Math.Max(0,sepX),Height));
            using (SolidBrush b=new SolidBrush(Color.FromArgb(
                (int)(255*arrow),muted))) {
                using (StringFormat fmt=new StringFormat()) {
                    fmt.Alignment=StringAlignment.Near;
                    fmt.LineAlignment=StringAlignment.Center;
                    g.DrawString("→",Font,b,
                        new RectangleF(arrowX,0,23,Height),fmt);
                }
            }
            g.Restore(save);
        }

        // 2px clear margins above and below; no outline clips at control edge.
        buttonBounds=new Rectangle(buttonX,Math.Max(2,(Height-21)/2),buttonWidth,21);
        if (buttonAlpha > 0.001) {
            int alpha=(int)(255*buttonAlpha);
            // Neutral gray surface with a substantial gold border and
            // high-contrast bold gold version number, including hover states.
            Color fill=installing ? Color.FromArgb(50,52,56) :
                pressed ? Color.FromArgb(47,50,55) :
                hovered ? Color.FromArgb(72,75,81) :
                          Color.FromArgb(55,58,64);
            Color gold=installing ? Color.FromArgb(177,143,80) :
                       hovered ? Color.FromArgb(255,210,119) :
                                 Color.FromArgb(235,184,87);
            using (GraphicsPath path=Rounded(buttonBounds,6))
            using (SolidBrush b=new SolidBrush(Color.FromArgb(alpha,fill)))
            using (Pen pen=new Pen(Color.FromArgb(alpha,gold),2.2f)) {
                pen.Alignment=PenAlignment.Center;
                g.FillPath(b,path);
                g.DrawPath(pen,path);
            }
            using (SolidBrush ink=new SolidBrush(Color.FromArgb(alpha,gold)))
            using (StringFormat centered=new StringFormat()) {
                centered.Alignment=StringAlignment.Center;
                centered.LineAlignment=StringAlignment.Center;
                g.DrawString(newText,buttonFont,ink,(RectangleF)buttonBounds,centered);
            }
            if (Focused && ButtonReady && ShowFocusCues) {
                ControlPaint.DrawFocusRectangle(g,Rectangle.Inflate(buttonBounds,-3,-3));
            }
        }
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        bool now=ButtonReady && buttonBounds.Contains(e.Location);
        Cursor=now ? Cursors.Hand : Cursors.Default;
        if (now!=hovered) { hovered=now; Invalidate(); }
        base.OnMouseMove(e);
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered=false; pressed=false; Cursor=Cursors.Default; Invalidate();
        base.OnMouseLeave(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button==MouseButtons.Left && ButtonReady &&
            buttonBounds.Contains(e.Location)) {
            Focus(); pressed=true; Invalidate();
        }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        bool activate=pressed && e.Button==MouseButtons.Left && ButtonReady &&
            buttonBounds.Contains(e.Location);
        pressed=false; Invalidate();
        base.OnMouseUp(e);
        if (activate) OnClick(EventArgs.Empty);
    }
    protected override bool IsInputKey(Keys keyData) {
        Keys key=keyData & Keys.KeyCode;
        if (key==Keys.Enter || key==Keys.Space) return true;
        return base.IsInputKey(keyData);
    }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (ButtonReady && (e.KeyCode==Keys.Enter || e.KeyCode==Keys.Space)) {
            pressed=true; Invalidate(); e.Handled=true; e.SuppressKeyPress=true;
            return;
        }
        base.OnKeyDown(e);
    }
    protected override void OnKeyUp(KeyEventArgs e) {
        if (e.KeyCode==Keys.Enter || e.KeyCode==Keys.Space) {
            bool activate=pressed && ButtonReady;
            pressed=false; Invalidate(); e.Handled=true; e.SuppressKeyPress=true;
            if (activate) OnClick(EventArgs.Empty);
            return;
        }
        base.OnKeyUp(e);
    }
    protected override void OnEnabledChanged(EventArgs e) {
        if (!Enabled) { hovered=false; pressed=false; }
        Invalidate(); base.OnEnabledChanged(e);
    }
    protected override void Dispose(bool disposing) {
        if (disposing) { watch.Stop(); buttonFont.Dispose(); }
        base.Dispose(disposing);
    }
}
'@ -ReferencedAssemblies @('System','System.Core','System.Drawing','System.Windows.Forms')

$script:rdcNoticeActive = $false
$script:rdcNoticeInstalling = $false
$script:rdcNoticeControl = New-Object RdcUpdateNoticeStrip
$script:rdcNoticeControl.BackColor = $form.BackColor
$script:rdcNoticeControl.Font = $hint.Font # match informational text size exactly
# The bottom TableLayoutPanel uses an auto-preferred 100px row even though
# its visible footer is 25px high. Drawing in that 100px vertical center was
# clipped completely. Dock only across the top of the visible inner footer.
$script:rdcNoticeControl.Dock = 'Top'
$script:rdcNoticeControl.Height = 25
$script:rdcNoticeControl.Margin = New-Object Windows.Forms.Padding(0)
$script:rdcNoticeControl.TabStop = $false
# Preserve the exact same renderer, font, parent, right edge and 25px bounds
# from the initial idle frame through every update-animation frame.
# The legacy footer remains untouched when the feature flag is disabled.
$bottom.Controls.Remove($hintHost)
$bottom.Controls.Add($script:rdcNoticeControl,1,0)
$script:rdcNoticeControl.Font = $hint.Font
$script:rdcNoticeControl.SetIdle($appVersion,$hint.Text)
$script:rdcNoticeControl.Visible = $true

$script:rdcNoticeAnimationTimer = New-Object Windows.Forms.Timer
$script:rdcNoticeAnimationTimer.Interval = 33
$script:rdcNoticeAnimationTimer.Add_Tick({
    if (-not $script:rdcNoticeActive) {
        $script:rdcNoticeAnimationTimer.Stop()
        return
    }
    $targetWidth = $script:rdcNoticeControl.SuggestedWidth
    if ([int]$bottom.ColumnStyles[1].Width -ne $targetWidth) {
        $bottom.ColumnStyles[1].Width = $targetWidth
        $bottom.PerformLayout()
    }
    $script:rdcNoticeControl.Invalidate()
    if ($script:rdcNoticeControl.AnimationComplete) {
        $script:rdcNoticeControl.TabStop = $true
        $script:rdcNoticeAnimationTimer.Stop()
    }
})

function Show-RdcUpdateNotice([string]$Version) {
    if (-not $script:enableUpdateNotice -or
        [string]::IsNullOrWhiteSpace($Version)) { return }
    if ($script:rdcNoticeActive -and
        $script:rdcNoticeControl.OfferedVersion -eq $Version) { return }
    $script:rdcNoticeAnimationTimer.Stop()
    $script:rdcNoticeControl.Begin($appVersion,$Version,$hint.Text)
    $script:rdcNoticeActive = $true
    $script:rdcNoticeControl.TabStop = $false
    $script:rdcNoticeAnimationTimer.Start()
}
function Hide-RdcUpdateNotice {
    $script:rdcNoticeAnimationTimer.Stop()
    if (-not $script:rdcNoticeActive) { return }
    $script:rdcNoticeControl.TabStop = $false
    $script:rdcNoticeActive = $false
    $script:rdcNoticeInstalling = $false
    $script:rdcNoticeControl.End()
    $bottom.ColumnStyles[1].Width = 440
    $bottom.PerformLayout()
}
function Complete-RdcUpdateNoticeInstall([int]$ExitCode) {
    $script:rdcNoticeInstalling = $false
    $script:rdcNoticeControl.Installing = $false
    if ($ExitCode -eq 0) {
        # Another process may already have installed the update.
        $script:rdcNoticeNextCheck = (Get-Date).AddSeconds(20)
    }
}

$script:rdcNoticeControl.Add_Click({
    if ($SelfTest -or $Preview -or $script:initializing -or
        $script:remoteOperation -or $script:rdcNoticeInstalling) { return }
    if (-not $script:rdcNoticeControl.ButtonReady) { return }
    $script:rdcNoticeInstalling = $true
    $script:rdcNoticeControl.Installing = $true
    $script:updateInstallRequested = $true
    Start-RuntimeInitialization
})

function Get-RdcAvailableVersionFromManifest([string]$Raw) {
    $manifest = $Raw.TrimStart([char]0xFEFF) | ConvertFrom-Json
    $remote = [Version]([string]$manifest.version)
    $local = [Version]$appVersion
    if ($remote -gt $local) { return [string]$manifest.version }
    return $null
}

$script:rdcNoticeNextCheck = (Get-Date).AddSeconds(25)
$script:rdcNoticeCheckPhase = ''
$script:rdcNoticeCheckTask = $null
$script:rdcNoticeHttp = $null

function Update-RdcUpdateNoticePolling {
    # -SkipUpdate skips the startup install, not passive future notifications.
    # The updater restarts a successfully upgraded GUI with -SkipUpdate.
    if ($SelfTest -or $Preview -or -not $script:enableUpdateNotice) { return }
    $now = Get-Date
    if ($script:rdcNoticeCheckTask) {
        if (-not $script:rdcNoticeCheckTask.IsCompleted) { return }
        $phase = $script:rdcNoticeCheckPhase
        $doneTask = $script:rdcNoticeCheckTask
        $script:rdcNoticeCheckTask = $null
        $script:rdcNoticeCheckPhase = ''
        try {
            $raw = [string]$doneTask.GetAwaiter().GetResult()
            if ($phase -eq 'commit') {
                $sha = [string](($raw | ConvertFrom-Json).sha)
                if ($sha -notmatch '^[0-9a-fA-F]{40}$') { throw 'Invalid stable SHA' }
                $url = 'https://raw.githubusercontent.com/1rubass1/RDC-Relay/' +
                    $sha + '/Source/update-manifest.json'
                $script:rdcNoticeCheckTask = $script:rdcNoticeHttp.GetStringAsync($url)
                $script:rdcNoticeCheckPhase = 'manifest'
                return
            }
            if ($phase -eq 'manifest') {
                $available = Get-RdcAvailableVersionFromManifest $raw
                if ($available) {
                    Show-RdcUpdateNotice $available
                } elseif ($script:rdcNoticeActive) {
                    Hide-RdcUpdateNotice
                }
            }
        } catch {
            # Checking for a release must never fault Remote or show a modal.
            try { Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') +
                    '] Проверка обновлений: ' + $_.Exception.Message + $nl) } catch {}
        }
        return
    }
    if ($now -lt $script:rdcNoticeNextCheck) { return }
    $script:rdcNoticeNextCheck = $now.AddHours(1)
    try {
        if (-not $script:rdcNoticeHttp) {
            Add-Type -AssemblyName System.Net.Http
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $script:rdcNoticeHttp = New-Object Net.Http.HttpClient
            $script:rdcNoticeHttp.Timeout = [TimeSpan]::FromSeconds(8)
            $script:rdcNoticeHttp.DefaultRequestHeaders.UserAgent.ParseAdd('RDCRelayUpdateNotice/1.0')
            $script:rdcNoticeHttp.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
        }
        $url = 'https://api.github.com/repos/1rubass1/RDC-Relay/commits/stable'
        $script:rdcNoticeCheckTask = $script:rdcNoticeHttp.GetStringAsync($url)
        $script:rdcNoticeCheckPhase = 'commit'
    } catch {
        try { Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') +
                '] Проверка обновлений: ' + $_.Exception.Message + $nl) } catch {}
    }
}

# -Preview only: keep the original footer on screen long enough to be seen
# before playing the 3-stage reveal, then reset and replay every ~7 seconds.
# In production this timer does not exist; a real update animates just once.
function Start-RdcUpdateNoticePreview([string]$Version) {
    if (-not $Preview -or -not $script:enableUpdateNotice) { return }
    if ($script:rdcNoticePreviewTimer) { return }
    $script:rdcNoticePreviewVersion = $Version
    $script:rdcNoticePreviewShown = $false
    $script:rdcNoticePreviewNextAt = (Get-Date).AddSeconds(1.8)
    $script:rdcNoticePreviewTimer = New-Object Windows.Forms.Timer
    $script:rdcNoticePreviewTimer.Interval = 100
    $script:rdcNoticePreviewTimer.Add_Tick({
        $now = Get-Date
        if ($now -lt $script:rdcNoticePreviewNextAt) { return }
        if ($script:rdcNoticePreviewShown) {
            Hide-RdcUpdateNotice
            $script:rdcNoticePreviewShown = $false
            $script:rdcNoticePreviewNextAt = $now.AddSeconds(1.4)
        } else {
            Show-RdcUpdateNotice $script:rdcNoticePreviewVersion
            $script:rdcNoticePreviewShown = $true
            $script:rdcNoticePreviewNextAt = $now.AddSeconds(5.8)
        }
    })
    $script:rdcNoticePreviewTimer.Start()
}

function Dispose-RdcUpdateNotice {
    if ($script:rdcNoticePreviewTimer) {
        $script:rdcNoticePreviewTimer.Stop()
        $script:rdcNoticePreviewTimer.Dispose()
        $script:rdcNoticePreviewTimer = $null
    }
    if ($script:rdcNoticeAnimationTimer) {
        $script:rdcNoticeAnimationTimer.Stop()
        $script:rdcNoticeAnimationTimer.Dispose()
    }
    if ($script:rdcNoticeHttp) { $script:rdcNoticeHttp.Dispose() }
    if ($script:rdcNoticeControl -and -not $script:rdcNoticeControl.IsDisposed) {
        $script:rdcNoticeControl.Dispose()
    }
}
