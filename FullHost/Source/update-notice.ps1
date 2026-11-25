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
    // Owner RC1 uses the actual footer's compact right-hand column for read-only real update notices.
    // Both flags default to false, so stable/legacy updater stays unchanged.
    private bool compactOwner, visualPreviewOnly;
    public bool CompactOwner { get {return compactOwner;} set {compactOwner=value;Invalidate();} }
    public bool VisualPreviewOnly { get {return visualPreviewOnly;} set {visualPreviewOnly=value;TabStop=false;Invalidate();} }
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
        AccessibleRole = visualPreviewOnly ? AccessibleRole.StaticText : AccessibleRole.PushButton;
        AccessibleName = visualPreviewOnly ?
            "Демонстрация обновления RDC Relay v" + offered :
            "Установить RDC Relay v" + offered;
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
    public bool ButtonReady { get { return !visualPreviewOnly && active && Elapsed >= 0.73 && !installing; } }
    // Measure the SAME fonts and strings as OnPaint. For normal RC1 labels
    // retain the accepted 115 -> 295px geometry, but grow rather than clip
    // when either installed or offered version text becomes longer.
    private int TextWidth(string text,Font font) {
        return TextRenderer.MeasureText(text,font,new Size(10000,25),
            TextFormatFlags.NoPadding | TextFormatFlags.SingleLine |
            TextFormatFlags.VerticalCenter).Width;
    }
    public int IdleWidth { get {
        if (!compactOwner) return DefaultWidth;
        return Math.Max(115,TextWidth("v"+installed,Font)+12);
    } }
    public int ExpandedWidth { get {
        if (!compactOwner) return DefaultWidth+ExtraWidth;
        int oldWidth=TextWidth("v"+installed,Font);
        int newWidth=Math.Max(84,TextWidth("v"+offered,buttonFont)+22);
        int contentWidth=6+oldWidth+7+19+7+newWidth+6;
        return Math.Max(IdleWidth+180,contentWidth);
    } }
    public int SuggestedWidth { get {
        int baseWidth=IdleWidth;
        int target=ExpandedWidth;
        return active ? baseWidth+(int)Math.Round((target-baseWidth)*Ease(Elapsed/MoveDuration)) : baseWidth;
    } }
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
        if(compactOwner){
            // The Owner footer has no old terminal hint or orange bullet.
            // Keep the idle version flush right, then shift it toward the
            // arrow/button using a 115 -> 295px expanding column.
            sepX=Width;
            originalVersionX=Width-6-oldWidth;
            buttonX=Width-6-buttonWidth;
            arrowXFinal=buttonX-7-19;
            targetVersionX=arrowXFinal-7-oldWidth;
        }
        double elapsed=active ? Elapsed : 0.0;
        double move=Ease(elapsed/MoveDuration);
        double arrow=Ease((elapsed-ArrowStart)/ArrowDuration);
        double buttonAlpha=Clamp((elapsed-ButtonFadeStart)/ButtonFadeDuration);
        int versionX=originalVersionX-
            (int)Math.Round((originalVersionX-targetVersionX)*move);
        int arrowX=sepX-8-(int)Math.Round((sepX-8-arrowXFinal)*arrow);
        int y=0;
        Color muted=compactOwner ? Color.Silver : Color.FromArgb(128,128,128);
        Color orange=Color.FromArgb(191,118,67);

        // Legacy fixed anchor stays identical. Owner has no close hint/bullet.
        if(!compactOwner){
            TextRenderer.DrawText(g,note,Font,new Rectangle(hintX,y,hintWidth,Height),
                muted,tf);
            TextRenderer.DrawText(g,"•",Font,new Rectangle(sepX,y,sepWidth,Height),
                orange,tf);
        }
        // RC1 Owner optical alignment: only the installed-version glyphs
        // move 1px upward. Keep the arrow, update button, widths, and timing.
        TextRenderer.DrawText(g,oldText,Font,
            new Rectangle(versionX,y-(compactOwner ? 1 : 0),oldWidth,Height),muted,tf);

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

        // Keep text in its original 21px slot; the Owner-only button outline
        // extends one pixel upward without moving or resizing the label.
        // Legacy button geometry remains unchanged.
        Rectangle textBounds=new Rectangle(buttonX,Math.Max(2,(Height-21)/2),buttonWidth,21);
        buttonBounds=compactOwner ? new Rectangle(textBounds.X,textBounds.Y-1,
            textBounds.Width,textBounds.Height+1) : textBounds;
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
                g.DrawString(newText,buttonFont,ink,(RectangleF)textBounds,centered);
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
$script:rdcNoticeControl.CompactOwner=[bool]$script:ownerUpdateDemoMode
$script:rdcNoticeControl.VisualPreviewOnly=[bool]$script:ownerUpdateDemoMode
$script:rdcNoticeControl.Font = if($script:ownerUpdateDemoMode){$form.Font}else{$hint.Font}
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
$script:rdcNoticeControl.Font = if($script:ownerUpdateDemoMode){$form.Font}else{$hint.Font}
if($script:ownerUpdateDemoMode){
    $script:rdcNoticeControl.SetIdle($appVersion,'')
    $bottom.ColumnStyles[1].Width=$script:rdcNoticeControl.IdleWidth
    $tip.SetToolTip($script:rdcNoticeControl,'RDC Relay RC1: проверка опубликованной версии. Автоматическая установка отключена.')
}else{$script:rdcNoticeControl.SetIdle($appVersion,$hint.Text)}
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
        $script:rdcNoticeControl.TabStop = -not $script:rdcNoticeControl.VisualPreviewOnly
        $script:rdcNoticeAnimationTimer.Stop()
    }
})

# Owner-only update notice localization. The WinForms painter, motion,
# available-version validation and disabled installer action are unchanged.
function Get-RdcOwnerNoticeText([string]$Key,[string]$Fallback){
    if($OwnerGui -and (Get-Command Get-RdcOwnerUiText -CommandType Function -ErrorAction SilentlyContinue)){
        return Get-RdcOwnerUiText $Key $Fallback
    }
    return $Fallback
}
function Refresh-RdcOwnerUpdateNoticeLanguage {
    if(-not $OwnerGui -or -not $script:rdcNoticeControl){return}
    if($script:rdcNoticeActive){
        $version=[string]$script:rdcNoticeControl.OfferedVersion
        if([string]::IsNullOrWhiteSpace($version)){return}
        $accessible=Get-RdcOwnerNoticeText 'update.owner.availableAccessible' 'Доступна стабильная версия RDC Relay v{version}. Установка из RC1 отключена.'
        $tooltip=Get-RdcOwnerNoticeText 'update.owner.availableTooltip' 'Опубликована стабильная версия v{version}. RC1: автоматическая установка отключена.'
        $script:rdcNoticeControl.AccessibleName=$accessible.Replace('{version}',$version)
        $tip.SetToolTip($script:rdcNoticeControl,$tooltip.Replace('{version}',$version))
    }else{
        $tooltip=Get-RdcOwnerNoticeText 'update.owner.idleTooltip' 'RDC Relay RC1: проверка опубликованной версии. Автоматическая установка отключена.'
        $tip.SetToolTip($script:rdcNoticeControl,$tooltip)
    }
}
# Apply the selected locale to the idle notice once its helper is defined.
if($OwnerGui){Refresh-RdcOwnerUpdateNoticeLanguage}

function Show-RdcUpdateNotice([string]$Version) {
    if (-not $script:enableUpdateNotice -or
        [string]::IsNullOrWhiteSpace($Version)) { return }
    if ($script:rdcNoticeActive -and
        $script:rdcNoticeControl.OfferedVersion -eq $Version) { return }
    $script:rdcNoticeAnimationTimer.Stop()
    $script:rdcNoticeControl.Begin($appVersion,$Version,$(if($script:ownerUpdateDemoMode){''}else{$hint.Text}))
    $script:rdcNoticeActive = $true
    $script:rdcNoticeControl.VisualPreviewOnly= -not (Test-RdcFullHostInstalled)
    if($OwnerGui){
        # Only display attributes are translated. Manifest and installer gates stay invariant.
        Refresh-RdcOwnerUpdateNoticeLanguage
    }
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
    # Pure-mock release-gate tests have no WinForms measured-width property.
    # Real controls always use their text-measured idle geometry.
    $idleWidthProperty=$script:rdcNoticeControl.PSObject.Properties['IdleWidth']
    $bottom.ColumnStyles[1].Width = if($idleWidthProperty){[int]$idleWidthProperty.Value}else{$(if($script:ownerUpdateDemoMode){115}else{440})}
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
    if($SelfTest -or !$OwnerGui -or $script:rdcNoticeInstalling){return}
    Start-RdcFullHostUpdate
})

function Get-RdcAvailableVersionFromManifest([string]$Raw) {
    $script:rdcFullHostOffer=$null
    try{
        $manifest=$Raw.TrimStart([char]0xFEFF)|ConvertFrom-Json -ErrorAction Stop
        if($manifest.schema -isnot [int] -or $manifest.schema -ne 1 -or
           $manifest.architecture -cne 'full-host-gui' -or
           $manifest.ready -isnot [bool] -or !$manifest.ready -or
           [string]$manifest.version -cnotmatch '^\d+\.\d+\.\d+$' -or
           [string]$appVersion -cnotmatch '^\d+\.\d+\.\d+$'){return $null}
        $remote=[Version]$manifest.version
        $local=[Version]$appVersion
        if($local -lt [Version]'1.6.0' -or $remote -le $local -or
           [string]$manifest.tag -cne ('v'+$manifest.version) -or
           [string]$manifest.asset -cne ('RDC.Relay.Setup.v'+$manifest.version+'.exe') -or
           [string]$manifest.sha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or
           ($manifest.bytes -isnot [int] -and $manifest.bytes -isnot [long]) -or
           $manifest.bytes -le 0 -or $manifest.bytes -gt 100MB){return $null}
        $script:rdcFullHostOffer=[pscustomobject]@{
            Version=[string]$manifest.version
            Digest=([string]$manifest.sha256).ToUpperInvariant()
            Bytes=[long]$manifest.bytes
            Uri=[Uri]('https://github.com/1rubass1/RDC-Relay/releases/download/'+$manifest.tag+'/'+$manifest.asset)
        }
        return $script:rdcFullHostOffer.Version
    }catch{return $null}
}

$script:rdcNoticeNextCheck = (Get-Date).AddSeconds(25)
$script:rdcNoticeCheckPhase = ''
$script:rdcNoticeCheckTask = $null
$script:rdcNoticeHttp = $null

function Update-RdcUpdateNoticePolling {
    if($script:rdcFullHostDownload){return}
    # -SkipUpdate skips the startup install, not passive future notifications.
    # The updater restarts a successfully upgraded GUI with -SkipUpdate.
    # Owner runs with the legacy -Preview safety boundary. Permit ONLY this
    # passive stable-version read, never the legacy install/startup route.
    if ($SelfTest -or ($Preview -and -not $OwnerGui) -or
        -not $script:enableUpdateNotice) { return }
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
                $ref = $raw | ConvertFrom-Json -ErrorAction Stop
                $sha = $ref.object.sha
                if ($ref.ref -cne 'refs/heads/stable' -or $ref.object.type -cne 'commit' -or
                    $sha -isnot [string] -or $sha -cnotmatch '\A[0-9a-f]{40}\z') { throw 'Invalid stable ref' }
                $url = 'https://raw.githubusercontent.com/1rubass1/RDC-Relay/' +
                    $sha + '/Source/full-host-update-manifest.json'
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
            $handler = New-Object Net.Http.HttpClientHandler
            $handler.AllowAutoRedirect = $false
            $handler.UseCookies = $false
            $handler.UseDefaultCredentials = $false
            $script:rdcNoticeHttp = New-Object Net.Http.HttpClient($handler)
            $script:rdcNoticeHttp.MaxResponseContentBufferSize = 256KB
            $script:rdcNoticeHttp.Timeout = [TimeSpan]::FromSeconds(8)
            $script:rdcNoticeHttp.DefaultRequestHeaders.UserAgent.ParseAdd('RDCRelayUpdateNotice/1.0')
            $script:rdcNoticeHttp.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
        }
        $url = 'https://api.github.com/repos/1rubass1/RDC-Relay/git/ref/heads/stable'
        $script:rdcNoticeCheckTask = $script:rdcNoticeHttp.GetStringAsync($url)
        $script:rdcNoticeCheckPhase = 'commit'
    } catch {
        try { Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') +
                '] Проверка обновлений: ' + $_.Exception.Message + $nl) } catch {}
    }
}

# Owner RC1 demo: reveal the preview exactly ONCE per GUI launch, then
# leave the static expanded notice visible. It never offers installation.
# The real (non-preview) update notice already animates once per version.
function Start-RdcUpdateNoticePreview([string]$Version) {
    if ((-not $Preview -and -not $script:ownerUpdateDemoMode) -or
        -not $script:enableUpdateNotice) { return }
    if ($script:rdcNoticePreviewShown -or $script:rdcNoticePreviewTimer) { return }
    $script:rdcNoticePreviewVersion = $Version
    $script:rdcNoticePreviewNextAt = (Get-Date).AddSeconds(1.8)
    $script:rdcNoticePreviewTimer = New-Object Windows.Forms.Timer
    $script:rdcNoticePreviewTimer.Interval = 100
    $script:rdcNoticePreviewTimer.Add_Tick({
        if ((Get-Date) -lt $script:rdcNoticePreviewNextAt) { return }
        $script:rdcNoticePreviewShown = $true
        $script:rdcNoticePreviewTimer.Stop()
        $script:rdcNoticePreviewTimer.Dispose()
        $script:rdcNoticePreviewTimer = $null
        Show-RdcUpdateNotice $script:rdcNoticePreviewVersion
    })
    $script:rdcNoticePreviewTimer.Start()
}

function Dispose-RdcUpdateNotice {
    Clear-RdcFullHostDownload
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

# Full Host/GUI update executor. Imported only in the staged numeric build.
# Setup owns the actual activation and cooperative Host handoff.
$script:rdcFullHostDownload=$null
function Test-RdcFullHostInstalled{
 try{
  if(!$OwnerGui -or $SelfTest -or !$script:ownerManagedMode){return $false}
  if(-not ('RdcOwnerStartup' -as [type])){
   Add-Type -Path (Join-Path $root 'RdcOwnerStartup.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Security.dll')
  }
  return [RdcOwnerStartup]::IsActiveSource($root)
 }catch{return $false}
}
function Test-RdcFullHostUpdateIdle{
 try{
  if(!(Test-RdcFullHostInstalled) -or !$script:ownerCanStart -or $script:ownerCanStop -or
     $script:ownerRemoteBornTicks -ne 0 -or $script:ownerQueuedAction){return $false}
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='cmd.exe'" -ErrorAction Stop)){
   if(!$p.CommandLine -or ($p.CommandLine -match '(?i)desktop-commander' -and $p.CommandLine -match '(?i)\bremote\b')){return $false}
  }
  return $true
 }catch{return $false}
}
function Test-RdcFullHostAssetUri([Uri]$uri){
 return ($uri -and $uri.IsAbsoluteUri -and $uri.Scheme -ceq 'https' -and $uri.IsDefaultPort -and !$uri.UserInfo -and
  @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com') -ccontains $uri.DnsSafeHost)
}
function Test-RdcFullHostBytes([byte[]]$bytes,$offer){
 if(!$bytes -or !$offer -or $bytes.Length -ne $offer.Bytes -or $bytes.Length -lt 2 -or $bytes.Length -gt 100MB -or
    $bytes[0] -ne 77 -or $bytes[1] -ne 90 -or $offer.Digest -cnotmatch '^[A-F0-9]{64}$'){return $false}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') -ceq $offer.Digest)}finally{$sha.Dispose()}
}
function Assert-RdcFullHostUpdatePath([string]$path){
 for($p=[IO.Path]::GetFullPath($path);$p;$p=[IO.Path]::GetDirectoryName($p)){
  if(([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) -and ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint)){throw 'RDC_UPDATE_REPARSE'}
 }
}
function Save-RdcFullHostCandidate([byte[]]$bytes,$offer){
 if(!(Test-RdcFullHostBytes $bytes $offer)){throw 'RDC_UPDATE_HASH'}
 if($offer.Version -cnotmatch '^\d+\.\d+\.\d+$'){throw 'RDC_UPDATE_VERSION'}
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('RDC-FullUpdate-'+[Guid]::NewGuid().ToString('N'))
 Assert-RdcFullHostUpdatePath $dir
 if(Test-Path -LiteralPath $dir){throw 'RDC_UPDATE_COLLISION'}
 [void][IO.Directory]::CreateDirectory($dir)
 $path=Join-Path $dir ('RDC.Relay.Setup.v'+$offer.Version+'.exe')
 Assert-RdcFullHostUpdatePath $path
 $f=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 Set-Content -LiteralPath $path -Stream Zone.Identifier -Value @('[ZoneTransfer]','ZoneId=3') -Encoding ASCII -ErrorAction Stop
 return $path
}
function Invoke-RdcFullHostCandidate([string]$path,$offer){
 Assert-RdcFullHostUpdatePath $path
 if(!(Test-RdcFullHostUpdateIdle)){throw 'RDC_UPDATE_REMOTE_ACTIVE'}
 if((Get-Item -LiteralPath $path).Length -ne $offer.Bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $offer.Digest){throw 'RDC_UPDATE_DISK_HASH'}
 if((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw -ErrorAction Stop) -notmatch '(?m)^ZoneId=3\r?$'){throw 'RDC_UPDATE_ZONE'}
 # Interactive Setup validates the installed predecessor and takes its
 # own Host/maintenance leases. No force-kill or old flat updater.
 Start-Process -FilePath $path -ErrorAction Stop -PassThru
}
function Clear-RdcFullHostDownload{
 $d=$script:rdcFullHostDownload
 $script:rdcFullHostDownload=$null
 if($d){
  if($d.Timer){$d.Timer.Stop();$d.Timer.Dispose()}
  if($d.Client){$d.Client.Dispose()}
  if($d.Process){$d.Process.Dispose()}
 }
 $script:rdcNoticeInstalling=$false
 if($script:rdcNoticeControl -and !$script:rdcNoticeControl.IsDisposed){$script:rdcNoticeControl.Installing=$false}
}
function Show-RdcFullUpdateMessage([string]$key,[string]$fallback){
 [void][Windows.Forms.MessageBox]::Show((Get-RdcOwnerNoticeText $key $fallback),'RDC Relay',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
}
function Update-RdcFullHostDownload{
 $d=$script:rdcFullHostDownload
 if(!$d){return}
 try{
  if($d.Process){
   if(!$d.Process.HasExited){return}
   $exit=$d.Process.ExitCode
   Clear-RdcFullHostDownload
   if($exit -ne 0){Show-RdcFullUpdateMessage 'update.owner.failed' 'Update did not complete.'}
   return
  }
  if([DateTime]::UtcNow -ge $d.Deadline){throw 'RDC_UPDATE_TIMEOUT'}
  if(!$d.Task.IsCompleted){return}
  $r=$d.Task.GetAwaiter().GetResult()
  try{
   if([int]$r.StatusCode -in @(301,302,303,307,308)){
    if(!$r.Headers.Location -or $d.Hops -ge 5){throw 'RDC_UPDATE_REDIRECT'}
    $next=[Uri]::new($d.Uri,$r.Headers.Location)
    if(!(Test-RdcFullHostAssetUri $next)){throw 'RDC_UPDATE_REDIRECT'}
    $d.Uri=$next;$d.Hops++;$d.Task=$d.Client.GetAsync($next);return
   }
   [void]$r.EnsureSuccessStatusCode()
   $bytes=$r.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
   $path=Save-RdcFullHostCandidate $bytes $d.Offer
  }finally{$r.Dispose()}
  $d.Process=Invoke-RdcFullHostCandidate $path $d.Offer
 }catch{
  Clear-RdcFullHostDownload
  Show-RdcFullUpdateMessage 'update.owner.failed' 'Update did not complete.'
 }
}
function Start-RdcFullHostUpdate{
 if($script:rdcFullHostDownload -or !$script:rdcFullHostOffer -or !$script:rdcNoticeControl.ButtonReady){return}
 $offer=$script:rdcFullHostOffer
 if($offer.Version -cne $script:rdcNoticeControl.OfferedVersion){return}
 if(!(Test-RdcFullHostUpdateIdle)){
  Show-RdcFullUpdateMessage 'update.owner.stopFirst' 'Stop Remote before updating.'
  return
 }
 $question=(Get-RdcOwnerNoticeText 'update.owner.confirm' 'Install RDC Relay {version}?').Replace('{version}',$offer.Version)
 if([Windows.Forms.MessageBox]::Show($question,'RDC Relay',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2) -ne [Windows.Forms.DialogResult]::Yes){return}
 if(!(Test-RdcFullHostUpdateIdle)){return}
 try{
  Add-Type -AssemblyName System.Net.Http
  if(!(Test-RdcFullHostAssetUri $offer.Uri)){throw 'RDC_UPDATE_URI'}
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $handler=New-Object Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect=$false;$handler.UseCookies=$false;$handler.UseDefaultCredentials=$false
  $client=New-Object Net.Http.HttpClient($handler)
  $client.Timeout=[TimeSpan]::FromSeconds(45)
  $client.MaxResponseContentBufferSize=100MB
  $client.DefaultRequestHeaders.UserAgent.ParseAdd('RDCRelayFullUpdate/1.0')
  $timer=New-Object Windows.Forms.Timer;$timer.Interval=150
  $script:rdcFullHostDownload=[pscustomobject]@{Client=$client;Timer=$timer;Task=$null;Uri=$offer.Uri;Offer=$offer;Hops=0;Deadline=[DateTime]::UtcNow.AddSeconds(90);Process=$null}
  $script:rdcNoticeInstalling=$true;$script:rdcNoticeControl.Installing=$true
  $script:rdcFullHostDownload.Task=$client.GetAsync($offer.Uri)
  $timer.Add_Tick({Update-RdcFullHostDownload});$timer.Start()
 }catch{
  Clear-RdcFullHostDownload
  Show-RdcFullUpdateMessage 'update.owner.failed' 'Update did not complete.'
 }
}
