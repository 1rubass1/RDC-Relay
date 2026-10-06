param([switch]$SelfTest,[switch]$SkipUpdate,[switch]$Preview)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appVersion = '1.5.6'
$desktopCommanderPackage = '@wonderwhy-er/desktop-commander@0.2.52'
$logPath = Join-Path $root 'remote-session.log'
$iconPath = Join-Path $root 'DesktopCommander.ico'

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
        # A second launcher must never update files or steal focus from the
        # already-running instance. It simply exits.
        $windowMutex.Dispose()
        exit 0
    }
}

# Update only after this instance owns the single-instance mutex. This prevents
# a second launcher from replacing files under a live RDC window.
if (-not $SelfTest -and -not $Preview -and -not $SkipUpdate) {
    $updaterPath = Join-Path $root 'update.ps1'
    if (Test-Path -LiteralPath $updaterPath) {
        try {
            $updateArgs = @(
                '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $updaterPath + '"'),
                '-InstallRoot',('"' + $root + '"'),'-CurrentVersion',$appVersion
            )
            $updateProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $updateArgs -WindowStyle Hidden -Wait -PassThru
            if ($updateProc.ExitCode -eq 42) {
                if ($windowMutex) {
                    try { $windowMutex.ReleaseMutex() } catch {}
                    $windowMutex.Dispose()
                    $windowMutex = $null
                }
                Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                    '-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass',
                    '-File',('"' + (Join-Path $root 'remote-window.ps1') + '"'),'-SkipUpdate'
                ) -WindowStyle Hidden
                exit 0
            }
        } catch {}
    }
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

    public override Color MenuItemSelected { get { return Color.FromArgb(91,67,126); } }
    public override Color MenuItemBorder { get { return Color.FromArgb(123,95,162); } }
    public override Color MenuItemPressedGradientBegin { get { return Color.FromArgb(74,55,103); } }
    public override Color MenuItemPressedGradientMiddle { get { return Color.FromArgb(74,55,103); } }
    public override Color MenuItemPressedGradientEnd { get { return Color.FromArgb(74,55,103); } }
}

public class RdcCircleButton : Control {
    private bool hovered;
    private bool pressed;

    public RdcCircleButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        ForeColor = Color.FromArgb(248,248,248);
        Font = new Font("Segoe UI", 11f, FontStyle.Bold);
        Cursor = Cursors.Hand;
        TabStop = false;
        Size = new Size(36,36);
    }

    protected override void OnMouseEnter(EventArgs e) {
        hovered = true; Invalidate(); base.OnMouseEnter(e);
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) { pressed = true; Invalidate(); }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false; Invalidate(); base.OnMouseUp(e);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        Color fill = pressed ? Color.FromArgb(61,44,87)
                   : hovered ? Color.FromArgb(91,67,126)
                   : Color.FromArgb(74,55,103);
        Color edge = pressed ? Color.FromArgb(139,81,45)
                   : hovered ? Color.FromArgb(207,132,75)
                   : Color.FromArgb(191,118,67);
        RectangleF r = new RectangleF(1.5f,1.5f,Width-3f,Height-3f);
        using (SolidBrush b = new SolidBrush(fill)) e.Graphics.FillEllipse(b,r);
        using (Pen p = new Pen(edge,1f)) e.Graphics.DrawEllipse(p,r);
        TextRenderer.DrawText(
            e.Graphics, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
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
    }

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

public class RdcRoundedButton : Control {
    private bool hovered;
    private bool pressed;
    private RdcButtonGlyph glyph = RdcButtonGlyph.None;

    public RdcButtonGlyph Glyph {
        get { return glyph; }
        set { glyph = value; Invalidate(); }
    }

    public RdcRoundedButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        ForeColor = Color.FromArgb(238,238,238);
        Font = new Font("Segoe UI Semibold", 10f, FontStyle.Regular);
        Cursor = Cursors.Hand;
        TabStop = false;
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
    protected override void OnMouseDown(MouseEventArgs e) {
        if (Enabled && e.Button == MouseButtons.Left) { pressed = true; Invalidate(); }
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
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

        bool activeHover = Enabled && hovered;
        bool activePress = Enabled && pressed;
        Color fill = activePress ? Color.FromArgb(42,46,51)
                   : activeHover ? Color.FromArgb(61,66,72)
                   : Color.FromArgb(49,53,59);
        Color edge = activePress ? Color.FromArgb(139,81,45)
                   : activeHover ? Color.FromArgb(207,132,75)
                   : Enabled ? Color.FromArgb(191,118,67)
                   : Color.FromArgb(95,82,72);
        Color content = Enabled ? ForeColor : Color.FromArgb(132,135,139);

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

public class RdcDividerDragGuide : Control {
    public RdcDividerDragGuide() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.Opaque, true);
        BackColor = Color.FromArgb(18,20,23);
        TabStop = false;
        Enabled = false;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(BackColor);
        int bottom = Math.Max(0,Height-1);
        using (Pen purple = new Pen(Color.FromArgb(123,95,162),1f)) {
            e.Graphics.DrawLine(purple,0,0,Width,0);
            e.Graphics.DrawLine(purple,0,bottom,Width,bottom);
        }
        if (Height >= 5) {
            using (Pen orange = new Pen(Color.FromArgb(191,118,67),1f))
                e.Graphics.DrawLine(orange,0,Height/2,Width,Height/2);
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

    public Brush Input { get { return (Brush)GetValue(InputProperty); } set { SetValue(InputProperty,value); } }
    public double Time { get { return (double)GetValue(TimeProperty); } set { SetValue(TimeProperty,value); } }
    public double ViewportWidth { get { return (double)GetValue(ViewportWidthProperty); } set { SetValue(ViewportWidthProperty,value); } }
    public double Intensity { get { return (double)GetValue(IntensityProperty); } set { SetValue(IntensityProperty,value); } }
    public double Activity { get { return (double)GetValue(ActivityProperty); } set { SetValue(ActivityProperty,value); } }

    public RdcDividerGlowEffect(string shaderPath) {
        PixelShader ps = new PixelShader();
        ps.UriSource = new Uri(shaderPath,UriKind.Absolute);
        PixelShader = ps;
        UpdateShaderValue(InputProperty);
        UpdateShaderValue(TimeProperty);
        UpdateShaderValue(ViewportWidthProperty);
        UpdateShaderValue(IntensityProperty);
        UpdateShaderValue(ActivityProperty);
    }
}

public sealed class RdcGpuDividerHost : ElementHost {
    private readonly Stopwatch watch;
    private readonly System.Windows.Forms.Timer animationTimer;
    private readonly RdcDividerGlowEffect causticEffect;
    private readonly RdcDividerGlowEffect popupCausticEffect;
    private readonly RdcDividerGlowEffect particleEffect;
    private readonly RdcDividerGlowEffect particleEffectB;
    private readonly Popup particlePopup;
    private readonly Rectangle particleSurface;
    private readonly System.Windows.Controls.Grid particleLayer;
    private readonly System.Windows.Controls.Grid root;
    private double activity;
    private double targetActivity;
    private double lastFrameSeconds;
    private bool interactiveMove;
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

    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOZORDER = 0x0004;
    const uint SWP_NOACTIVATE = 0x0010;
    const uint SWP_SHOWWINDOW = 0x0040;
    static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd,int nIndex);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd,int nIndex,int dwNewLong);
    [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hWnd,int nIndex,IntPtr dwNewLong);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd,IntPtr hWndInsertAfter,int X,int Y,int cx,int cy,uint flags);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd,out RECT rect);

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

    private void NormalizePopupZOrder() {
        if (particlePopupHwnd == IntPtr.Zero) return;
        int exStyle = GetWindowLong(particlePopupHwnd,GWL_EXSTYLE);
        if ((exStyle & WS_EX_TOPMOST) != 0)
            SetWindowLong(particlePopupHwnd,GWL_EXSTYLE,exStyle & ~WS_EX_TOPMOST);
        SetWindowPos(particlePopupHwnd,HWND_NOTOPMOST,0,0,0,0,
            SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
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
        SetWindowPos(particlePopupHwnd,IntPtr.Zero,x,y,w,h,
            SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW);
    }

    private void EnsurePopupOpen() {
        if (particlePopup.IsOpen) return;
        particlePopup.Width = Math.Max(1.0,root.ActualWidth);
        particlePopup.IsOpen = true;
    }

    private void ClosePopup() {
        if (!particlePopup.IsOpen) return;
        particlePopup.IsOpen = false;
        particlePopupHwnd = IntPtr.Zero;
        lastPopupX=Int32.MinValue; lastPopupY=Int32.MinValue;
        lastPopupW=-1; lastPopupH=-1;
    }

    private void OwnerGeometryChanged(object sender,EventArgs e) {
        lastPopupX=Int32.MinValue; lastPopupY=Int32.MinValue;
        PositionPopup();
    }

    private void OwnerActivated(object sender,EventArgs e) {
        NormalizePopupZOrder();
        PositionPopup();
    }

    private void OwnerDeactivated(object sender,EventArgs e) {
        NormalizePopupZOrder();
    }

    private void Animate(object sender,EventArgs e) {
        double now = watch.Elapsed.TotalSeconds;
        double dt = Math.Max(0.0,Math.Min(0.12,now-lastFrameSeconds));
        lastFrameSeconds = now;

        double rate = targetActivity > activity ? 5.6 : 3.3;
        double blend = 1.0 - Math.Exp(-rate*dt);
        activity += (targetActivity-activity)*blend;
        if (activity < 0.001 && targetActivity <= 0.0) activity=0.0;
        if (activity > 0.999 && targetActivity >= 1.0) activity=1.0;

        causticEffect.Time = now;

        if (interactiveMove) {
            // A transparent layered WPF Popup does not track WinForms layout
            // synchronously while the splitter is dragged. Keeping it closed
            // during the gesture prevents compositor trails and visible lag.
            return;
        }

        if (targetActivity > 0.0 || activity > 0.002) {
            if (!particlePopup.IsOpen) EnsurePopupOpen();
            particleLayer.Opacity = Math.Min(1.0,Math.Max(0.0,activity*1.15));
            popupCausticEffect.Time = now;
            particleEffect.Time = now;
            particleEffectB.Time = now + 11.37;
            particleEffect.Activity = activity;
            particleEffectB.Activity = activity;
            PositionPopup();
        } else {
            // Keep the layered popup HWND alive between remote tasks. Reopening
            // it for every task can transiently activate its owner.
            particleLayer.Opacity = 0.0;
        }
    }

    public RdcGpuDividerHost(string causticShaderPath,string particleShaderPath) {
        BackColor = System.Drawing.Color.FromArgb(18,20,23);
        TabStop = false;

        causticEffect = new RdcDividerGlowEffect(causticShaderPath);
        causticEffect.Intensity=1.0;

        popupCausticEffect = new RdcDividerGlowEffect(causticShaderPath);
        popupCausticEffect.Intensity=1.0;

        particleEffect = new RdcDividerGlowEffect(particleShaderPath);
        particleEffect.Intensity=0.58;

        particleEffectB = new RdcDividerGlowEffect(particleShaderPath);
        particleEffectB.Intensity=0.581;

        root = new System.Windows.Controls.Grid();
        root.Background = new SolidColorBrush(System.Windows.Media.Color.FromRgb(18,20,23));
        root.IsHitTestVisible=false;
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
        topRail.Fill=new SolidColorBrush(System.Windows.Media.Color.FromRgb(123,95,162));
        topRail.IsHitTestVisible=false;
        root.Children.Add(topRail);

        Rectangle bottomRail = new Rectangle();
        bottomRail.Height=1.0;
        bottomRail.VerticalAlignment=VerticalAlignment.Bottom;
        bottomRail.Fill=new SolidColorBrush(System.Windows.Media.Color.FromRgb(123,95,162));
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

        System.Windows.Controls.Grid popupRails = new System.Windows.Controls.Grid();
        popupRails.Height=7.0;
        popupRails.VerticalAlignment=VerticalAlignment.Center;
        popupRails.Background=Brushes.Transparent;
        popupRails.IsHitTestVisible=false;

        Rectangle popupTopRail = new Rectangle();
        popupTopRail.Height=1.0;
        popupTopRail.VerticalAlignment=VerticalAlignment.Top;
        popupTopRail.Fill=new SolidColorBrush(System.Windows.Media.Color.FromRgb(123,95,162));
        popupRails.Children.Add(popupTopRail);

        Rectangle popupBottomRail = new Rectangle();
        popupBottomRail.Height=1.0;
        popupBottomRail.VerticalAlignment=VerticalAlignment.Bottom;
        popupBottomRail.Fill=new SolidColorBrush(System.Windows.Media.Color.FromRgb(123,95,162));
        popupRails.Children.Add(popupBottomRail);

        particleSource.Children.Add(popupRails);
        particleSource.Effect=particleEffect;

        particleLayer = new System.Windows.Controls.Grid();
        particleLayer.Background=Brushes.Transparent;
        particleLayer.IsHitTestVisible=false;
        particleLayer.Opacity=0.0;
        particleLayer.Children.Add(particleSource);
        particleLayer.Effect=particleEffectB;

        particlePopup = new Popup();
        particlePopup.AllowsTransparency=true;
        particlePopup.StaysOpen=true;
        particlePopup.PopupAnimation=PopupAnimation.None;
        particlePopup.PlacementTarget=null;
        particlePopup.Placement=PlacementMode.AbsolutePoint;
        particlePopup.Height=33.0;
        particlePopup.Child=particleLayer;
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
                if (ownerForm!=null && ownerForm.Handle!=IntPtr.Zero)
                    SetWindowLongPtr(particlePopupHwnd,GWLP_HWNDPARENT,ownerForm.Handle);
                NormalizePopupZOrder();
                lastPopupX=Int32.MinValue; lastPopupY=Int32.MinValue;
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
                ownerForm.VisibleChanged+=OwnerGeometryChanged;
                ownerForm.Activated+=OwnerActivated;
                ownerForm.Deactivate+=OwnerDeactivated;
            }

            // Create the popup once during normal UI startup, then keep the
            // HWND alive for the lifetime of the window. Activity only changes
            // opacity/shader constants and therefore cannot steal foreground.
            EnsurePopupOpen();
        };

        root.SizeChanged += delegate(object sender,SizeChangedEventArgs e) {
            double w=Math.Max(1.0,root.ActualWidth);
            popupCausticEffect.ViewportWidth=w;
            particleEffect.ViewportWidth=w;
            particleEffectB.ViewportWidth=w;
            if (particlePopup.IsOpen) particlePopup.Width=w;
        };

        Child=root;
        activity=0.0;
        targetActivity=0.0;
        lastFrameSeconds=0.0;
        interactiveMove=false;

        watch=Stopwatch.StartNew();
        animationTimer=new System.Windows.Forms.Timer();
        animationTimer.Interval=33;
        animationTimer.Tick+=Animate;
        animationTimer.Start();
    }

    public int RenderTier { get { return RenderCapability.Tier; } }
    public double ActivityLevel { get { return activity; } }
    public bool ActivityRequested { get { return targetActivity > 0.5; } }

    public void SetActivity(bool active) {
        targetActivity=active ? 1.0 : 0.0;
    }

    public void SetInteractiveMove(bool active) {
        if (interactiveMove == active) return;
        interactiveMove=active;

        if (active) {
            // Destroy the overflow HWND once at drag start. The inline 7 px
            // divider remains visible and moves with normal WinForms layout.
            ClosePopup();
        } else {
            EnsurePopupOpen();
            PositionPopup();
            particleLayer.Opacity =
                (targetActivity > 0.0 || activity > 0.002)
                ? Math.Min(1.0,Math.Max(0.0,activity*1.15))
                : 0.0;
        }
    }

    protected override void OnResize(EventArgs e) {
        base.OnResize(e);
        double w=Math.Max(1.0,ClientSize.Width);
        causticEffect.ViewportWidth=w;
        popupCausticEffect.ViewportWidth=w;
        particleEffect.ViewportWidth=w;
        particleEffectB.ViewportWidth=w;
        if (particlePopup.IsOpen) particlePopup.Width=w;
    }

    protected override void Dispose(bool disposing) {
        if (disposing) {
            animationTimer.Stop();
            animationTimer.Tick-=Animate;
            if (ownerForm!=null) {
                ownerForm.LocationChanged-=OwnerGeometryChanged;
                ownerForm.SizeChanged-=OwnerGeometryChanged;
                ownerForm.VisibleChanged-=OwnerGeometryChanged;
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
$particleShaderPath = Join-Path $root 'divider-particles.ps'
$gpuDividerAvailable =
    (Test-Path -LiteralPath $causticShaderPath) -and
    (Test-Path -LiteralPath $particleShaderPath)

[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Remote Desktop Commander'
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
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,325)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$statusDot = New-Object RdcStatusIndicator
$statusDot.Dock = 'Fill'
$statusDot.IndicatorColor = [Drawing.Color]::Gray
$title = New-Object Windows.Forms.Label
$title.Text = 'Remote Desktop Commander'
$title.Dock = 'Fill'
$title.TextAlign = 'MiddleLeft'
$title.Font = New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
$detail = New-Object Windows.Forms.Label
$detail.Dock = 'Fill'
$detail.TextAlign = 'MiddleLeft'
$detail.ForeColor = [Drawing.Color]::Silver
$finish = New-Object RdcRoundedButton
$finish.Text = 'Остановить'
$finish.Glyph = [RdcButtonGlyph]::Stop
$finish.Size = New-Object Drawing.Size(118,36)
$finish.Margin = New-Object Windows.Forms.Padding(8,0,0,0)

$accountButton = New-Object RdcRoundedButton
$accountButton.Text = 'Аккаунт  ▾'
$accountButton.Size = New-Object Drawing.Size(116,36)
$accountButton.Margin = New-Object Windows.Forms.Padding(8,0,0,0)

$helpButton = New-Object RdcCircleButton
$helpButton.Text = '?'
$helpButton.Size = New-Object Drawing.Size(36,36)
$helpButton.Margin = New-Object Windows.Forms.Padding(8,0,0,0)

$actions = New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'
$actions.FlowDirection = 'RightToLeft'
$actions.WrapContents = $false
$actions.Margin = New-Object Windows.Forms.Padding(0)
$actions.Padding = New-Object Windows.Forms.Padding(0,12,5,12)
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
$top.Controls.Add($detail,1,1)
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
# unavailable, the normal painted divider remains fully functional.
$gpuDivider = $null
if ($gpuDividerAvailable) {
    try {
        $gpuDivider = New-Object RdcGpuDividerHost -ArgumentList @($causticShaderPath,$particleShaderPath)
        $gpuDivider.Dock = 'Fill'
        $gpuDivider.Margin = New-Object Windows.Forms.Padding(0)
        $gpuDivider.TabStop = $false
        $gpuDivider.Enabled = $false
        $headerDivider.Controls.Add($gpuDivider)
        $gpuDivider.BringToFront()
    } catch {
        $gpuDivider = $null
    }
}

# During splitter drag, move only this lightweight guide. The real RichEdit
# panes keep their geometry until MouseUp, then resize atomically once.
$dividerDragGuide = New-Object RdcDividerDragGuide
$dividerDragGuide.Visible = $false
$dividerDragGuide.Height = 7
$dividerOriginMask = New-Object Windows.Forms.Panel
$dividerOriginMask.Visible = $false
$dividerOriginMask.Enabled = $false
$dividerOriginMask.Height = 7
$dividerOriginMask.BackColor = [Drawing.Color]::FromArgb(18,20,23)

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
function Position-DividerDragGuide([double]$paneHeight) {
    $clamped = Get-ClampedActivityPaneHeight $paneHeight
    $origin = $form.PointToClient($contentHost.PointToScreen((New-Object Drawing.Point(0,0))))
    $topY = $origin.Y + $contentHost.ClientSize.Height - [int][Math]::Round($clamped) - 7
    $dividerDragGuide.SetBounds($origin.X,$topY,$contentHost.ClientSize.Width,7)
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
    $dividerDragGuide.Visible = $false
    $dividerOriginMask.Visible = $false
    $script:uiInteracting = $false

    Start-LogResizeInteraction
    try {
        Set-ActivityPaneHeight $script:dividerPendingHeight
        Layout-LogScrollbars
    } finally {
        Stop-LogResizeInteraction
    }

    try { $gpuDivider.SetInteractiveMove($false) } catch {}
    $contentHost.Invalidate($true)
    $contentHost.Update()
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
        Position-DividerDragGuide $script:dividerPendingHeight
        $dividerOriginMask.Bounds = $dividerDragGuide.Bounds

        # Keep mouse capture on the real divider, but cover its original pixels
        # so only the lightweight moving guide is visible during the gesture.
        $headerDivider.Capture = $true
        $dividerOriginMask.Visible = $true
        $dividerOriginMask.BringToFront()
        $dividerDragGuide.Visible = $true
        $dividerDragGuide.BringToFront()
    }
})
$headerDivider.Add_MouseMove({
    if ($script:dividerDragging) {
        $nowY = [Windows.Forms.Control]::MousePosition.Y
        $delta = $nowY - $script:dividerStartScreenY
        $script:dividerPendingHeight =
            Get-ClampedActivityPaneHeight ($script:dividerStartPaneHeight - $delta)

        # Only the lightweight guide follows the pointer. RichEdit and both
        # custom scrollbars keep stable geometry until the drag is committed.
        Position-DividerDragGuide $script:dividerPendingHeight
        $dividerDragGuide.Update()
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
$form.Controls.Add($dividerOriginMask)
$form.Controls.Add($dividerDragGuide)
$form.PerformLayout()
Set-ActivityPaneHeight (Get-EffectivePaneMinHeight)
$dividerOriginMask.BringToFront()
$dividerDragGuide.BringToFront()
$script:proc = $null
$script:reader = $null
$script:bannerStyled = $false
$script:startTime = $null
$script:stopping = $false
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
$script:activeToolCalls = 0
$script:lastToolCompletedAt = $null
$script:lastToolMarkerAt = $null
$activityMinHoldSeconds = 10.0
$activityMaxHoldSeconds = 30.0
$activityInterruptedTimeoutSeconds = 60.0
$script:activityHoldUntil = $null
$script:activityGapEwmaSeconds = 3.0
$script:activityHoldSeconds = $activityMinHoldSeconds
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
            $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -eq 'Remote Desktop Commander'
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
    $title.Text = 'Remote Desktop Commander  —  ' + $name
    $detail.Text = $message
}
function Set-FinishButtonMode([bool]$running) {
    if ($running) {
        $finish.Text = 'Остановить'
        $finish.Glyph = [RdcButtonGlyph]::Stop
    } else {
        $finish.Text = 'Запустить'
        $finish.Glyph = [RdcButtonGlyph]::Play
    }
    $finish.Enabled = $true
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
function Refresh-DividerActivitySession {
    $now = Get-Date

    if ($script:activeToolCalls -gt 0 -and $script:lastToolMarkerAt) {
        if (($now - $script:lastToolMarkerAt).TotalSeconds -gt $activityInterruptedTimeoutSeconds) {
            # Missing completion marker: keep the strip alive for up to 60 s,
            # then treat the tool call as interrupted and return to idle.
            $script:activeToolCalls = 0
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
function Set-StartupFromProbe([string]$text) {
    $clean = Convert-ToCleanLogText $text
    if ([string]::IsNullOrWhiteSpace($clean)) { return }
    Update-AccountFromLog $clean

    $markerPos = $clean.IndexOf('Received tool call ',[StringComparison]::Ordinal)
    if ($markerPos -ge 0) {
        $lineStart = $clean.LastIndexOf("`n",$markerPos)
        if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
        $clean = $clean.Substring(0,$lineStart)
    }

    if ($clean.Length -gt $uiStartupMaxChars) { $clean = $clean.Substring(0,$uiStartupMaxChars) }
    $script:startupBlock = $clean.TrimEnd()
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
        Color-LogToken $log '🔧' $accentOrange
        Color-LogToken $log '🚀' $accentOrange
        Color-LogToken $log '✅' $accentPurple
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

        if ($shouldFollow) {
            $vScroll.ScrollToEnd()
            try { $finalY = $log.GetViewPosition().Y } catch {}
        }
        try { $log.SetViewPosition($finalX,$finalY) } catch {}
        $script:lastRenderedText = $display
    } finally {
        $log.EndUpdate()
        try { $log.SetSelectionHidden($false) } catch {}
    }

    try { $log.SetViewPosition($finalX,$finalY) } catch {}
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
    $receivedPos = $line.IndexOf('Received tool call ',[StringComparison]::Ordinal)
    $toolPos = $line.IndexOf('Tool call ',[StringComparison]::Ordinal)
    $isReceived = ($receivedPos -ge 0 -and $receivedPos -le 4)
    $isCompleted = ($toolPos -ge 0 -and $toolPos -le 4 -and $line.IndexOf(' completed:',[StringComparison]::Ordinal) -gt $toolPos)
    $isMarker = $isReceived -or $isCompleted

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
            Set-DividerWorkState $true
        }
    }

    if ($isMarker) {
        if ($script:tailNeedsMarker) { $script:tailNeedsMarker = $false }
        if (-not [string]::IsNullOrWhiteSpace($script:currentEvent)) { Commit-CurrentEvent }
        $script:seenFirstRemoteEvent = $true
        $script:currentEvent = ''
        $script:currentEventTruncated = $false
        Append-CurrentEvent $text
        return
    }

    if ($script:tailNeedsMarker) { return }

    if ($script:seenFirstRemoteEvent) {
        if (-not [string]::IsNullOrWhiteSpace($script:currentEvent)) {
            Append-CurrentEvent $text
        }
        return
    }

    if ($script:startupBlock.Length -lt $uiStartupMaxChars) {
        $remaining = $uiStartupMaxChars - $script:startupBlock.Length
        if ($text.Length -le $remaining) { $script:startupBlock += $text }
        elseif ($remaining -gt 0) { $script:startupBlock += $text.Substring(0,$remaining) }
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
                $script:seenFirstRemoteEvent = $true
                $script:tailNeedsMarker = $true
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
        $script:seenFirstRemoteEvent = $true
        $script:tailNeedsMarker = $true

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
        $existing = Find-ExistingRemote
        if ($existing) {
            Reset-CompactLogSession
            $script:proc = $existing
            $script:startTime = $existing.StartTime
            $script:stopping = $false
            $script:exitHandled = $false
            Set-FinishButtonMode $true
            Set-State 'Работает' 'Подхвачен уже запущенный Remote Desktop Commander.' ([Drawing.Color]::LightGreen)
            Set-RuntimeDisplay ('PID ' + $existing.Id) 'Подхвачен существующий процесс' $true
            Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Найден уже работающий remote-процесс. Перезапуск не требуется.' + $nl)
            return
        }
        $npxPath = Resolve-NpxPath
        if ($script:reader) { $script:reader.Dispose(); $script:reader = $null }
        Reset-CompactLogSession
        if (Test-Path $logPath) { Remove-Item -LiteralPath $logPath -Force }
        $script:stopping = $false
        $script:exitHandled = $false
        $script:startTime = Get-Date
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
    $finish.Enabled = $false
    Set-State 'Завершается…' 'Останавливаю remote-процесс и его дочерние процессы.' ([Drawing.Color]::Khaki)
    Add-Log ($nl + '[' + (Get-Date -Format 'HH:mm:ss') + '] Завершение по команде пользователя…' + $nl)
    try {
        $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $killCmd = '""' + $taskkill + '" /PID ' + $script:proc.Id + ' /T /F"'
        $killer = Start-NoWindowCmd $killCmd
        if ($killer) {
            [void]$killer.WaitForExit(5000)
            $killer.Dispose()
        }
    } catch {
        try { Stop-Process -Id $script:proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
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
function Wait-RemoteStopped([int]$timeoutMs = 5000) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $timeoutMs) {
        if (-not (Find-ExistingRemote)) {
            $watch.Stop()
            return $true
        }
        Start-Sleep -Milliseconds 200
    }
    $watch.Stop()
    return $false
}
function Restart-Remote {
    $answer = [Windows.Forms.MessageBox]::Show(
        'Remote Desktop Commander будет кратковременно отключён и запущен снова под текущим аккаунтом.',
        'Переподключить Remote Desktop Commander',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $timer.Stop()
    try {
        Stop-Remote
        if (-not (Wait-RemoteStopped 5000)) { throw 'Старый remote-процесс не завершился полностью.' }
        Reset-RemoteHandle
        Add-Log ($nl + '[' + (Get-Date -Format 'HH:mm:ss') + '] Переподключение…' + $nl)
        Start-Remote
        Refresh-Window
    } finally {
        $timer.Start()
    }
}
function Switch-RemoteAccount {
    $message = 'Смена аккаунта разорвёт текущее удалённое соединение.' + $nl + $nl +
        'После выхода Remote Desktop Commander запустится снова и попросит авторизоваться в браузере.' + $nl + $nl +
        'ВАЖНО: после входа под другим аккаунтом переподключите Desktop Commander в ChatGPT к ЭТОМУ ЖЕ аккаунту. ' +
        'Если аккаунты на компьютере и в ChatGPT различаются, устройство не появится.' + $nl + $nl +
        'Продолжить?'
    $answer = [Windows.Forms.MessageBox]::Show(
        $message,
        'Сменить аккаунт Desktop Commander',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }

    $timer.Stop()
    $accountButton.Enabled = $false
    try {
        Stop-Remote
        if (-not (Wait-RemoteStopped 5000)) { throw 'Старый remote-процесс не завершился полностью.' }
        Reset-RemoteHandle
        Set-AccountDisplay $null
        Set-State 'Выход из аккаунта…' 'Удаляю текущую авторизацию Desktop Commander.' ([Drawing.Color]::Khaki)
        Add-Log ($nl + '[' + (Get-Date -Format 'HH:mm:ss') + '] Выход из текущего аккаунта…' + $nl)

        $npxPath = Resolve-NpxPath
        $logoutFile = Join-Path $root 'logout-session.log'
        if (Test-Path $logoutFile) { Remove-Item -LiteralPath $logoutFile -Force -ErrorAction SilentlyContinue }
        $logoutCmd = '""' + $npxPath + '" --yes ' + $desktopCommanderPackage + ' remote --logout > "' + $logoutFile + '" 2>&1"'
        $logout = Start-NoWindowCmd $logoutCmd
        if (-not $logout) { throw 'Не удалось запустить команду выхода без консольного окна.' }
        if (-not $logout.WaitForExit(30000)) {
            try {
                $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                $killCmd = '""' + $taskkill + '" /PID ' + $logout.Id + ' /T /F"'
                $killer = Start-NoWindowCmd $killCmd
                if ($killer) { [void]$killer.WaitForExit(5000); $killer.Dispose() }
            } catch {}
            throw 'Команда выхода не завершилась за 30 секунд.'
        }
        if (Test-Path $logoutFile) {
            $logoutText = Get-Content -LiteralPath $logoutFile -Raw -ErrorAction SilentlyContinue
            if ($logoutText) { Add-Log ($logoutText + $nl) }
        }
        if ($logout.ExitCode -ne 0) { throw ('Команда выхода завершилась с кодом ' + $logout.ExitCode) }
        $logout.Dispose()

        Set-State 'Ожидание авторизации…' 'Запускаю Remote Desktop Commander для входа в другой аккаунт.' ([Drawing.Color]::Khaki)
        Add-Log ('[' + (Get-Date -Format 'HH:mm:ss') + '] Авторизация сброшена. Запускаю новый вход…' + $nl)
        Start-Remote
        Refresh-Window
    } catch {
        Set-State 'Ошибка смены аккаунта' $_.Exception.Message ([Drawing.Color]::LightCoral)
        Add-Log ('Ошибка смены аккаунта: ' + $_.Exception.Message + $nl)
        try {
            Reset-RemoteHandle
            Start-Remote
            Refresh-Window
        } catch {}
    } finally {
        $accountButton.Enabled = $true
        $timer.Start()
    }
}
$finish.Add_Click({
    if ($script:proc -and -not $script:proc.HasExited) {
        Stop-Remote
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
        'Remote Desktop Commander v' + $appVersion + $nl + $nl +
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
        'Remote Desktop Commander — справка',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
})

$openLogItem.Add_Click({
    try {
        if (-not (Test-Path $logPath)) {
            [Windows.Forms.MessageBox]::Show(
                'Журнал ещё не создан.',
                'Remote Desktop Commander — журнал',
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
            'Remote Desktop Commander — журнал',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})
function Refresh-Window {
    Apply-SystemFrameTheme

    if ($script:uiInteracting -or $vScroll.IsDragging -or $hScroll.IsDragging) {
        return
    }

    Read-LiveLog
    Refresh-DividerActivitySession

    if ($script:proc) {
        $script:proc.Refresh()
        if (-not $script:proc.HasExited) {
            $elapsed = (Get-Date) - $script:startTime
            Set-RuntimeDisplay ('PID ' + $script:proc.Id) ('Время работы {0:hh\:mm\:ss}' -f $elapsed) $true
            if (-not $script:stopping) {
                Set-State 'Работает' 'Remote Desktop Commander запущен и готов принимать задачи.' ([Drawing.Color]::LightGreen)
            }
        } elseif (-not $script:exitHandled) {
            Read-LiveLog
            $code = $script:proc.ExitCode
            $script:exitHandled = $true
            Set-FinishButtonMode $false
            if ($script:stopping) {
                Set-State 'Завершён' 'Remote-процесс остановлен.' ([Drawing.Color]::Silver)
            } elseif ($code -eq 0) {
                Set-State 'Завершён' 'Remote-процесс завершился штатно.' ([Drawing.Color]::Silver)
            } else {
                Set-State 'Ошибка' ('Remote-процесс завершился с кодом ' + $code + '.') ([Drawing.Color]::LightCoral)
            }
            Set-RuntimeDisplay ('Код завершения: ' + $code)
            Add-Log ($nl + '[' + (Get-Date -Format 'HH:mm:ss') + '] Процесс завершён. Код: ' + $code + $nl)
            $script:freezeViewport = $false
        }
    }
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({ Refresh-Window })

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
    Refresh-Window
})

$form.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) { Stop-Remote }
})
$form.Add_FormClosed({
    $timer.Stop()
    if ($script:reader) { $script:reader.Dispose() }
    if ($script:proc) { $script:proc.Dispose() }
})
if ($SelfTest) {
    Set-State 'Тест' 'Проверка интерфейса без запуска remote.' ([Drawing.Color]::LightBlue)
    Add-Log ('SELF TEST OK' + $nl)
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
    if ($form.Text -ne 'Remote Desktop Commander') { throw 'Window title changed unexpectedly' }
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
    if ($title.Text -notlike 'Remote Desktop Commander*') { throw 'Header title missing' }
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
    if ($dividerDragGuide.GetType().Name -ne 'RdcDividerDragGuide') { throw 'Deferred divider drag guide missing' }
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
    if ($script:activityHoldSeconds -ne 10.0) { throw 'Divider minimum hold must start at 10 seconds' }
    Process-RemoteLine 'Received tool call timeout_probe: begin'
    $script:lastToolMarkerAt = (Get-Date).AddSeconds(-59)
    Refresh-DividerActivitySession
    if ($script:activeToolCalls -ne 1) { throw 'Interrupted tool call expired before 60 seconds' }
    $script:lastToolMarkerAt = (Get-Date).AddSeconds(-61)
    Refresh-DividerActivitySession
    if ($script:activeToolCalls -ne 0) { throw 'Interrupted tool call did not expire after 60 seconds' }

    Reset-CompactLogSession
    $script:activityGapEwmaSeconds = 24.0
    $script:lastToolCompletedAt = (Get-Date).AddSeconds(-5)
    Process-RemoteLine 'Received tool call max_hold_probe: begin'
    if ([Math]::Abs($script:activityHoldSeconds - 30.0) -gt 0.01) { throw 'Divider adaptive hold did not clamp at 30 seconds' }
    Process-RemoteLine 'Tool call max_hold_probe completed:'
    if (-not $script:activityHoldUntil -or
        ($script:activityHoldUntil - (Get-Date)).TotalSeconds -lt 29.0) {
        throw 'Divider completion hold did not use 30-second maximum'
    }

    Reset-CompactLogSession
    if ($gpuDivider) {
        if ($gpuDivider.GetType().Name -ne 'RdcGpuDividerHost') { throw 'Unexpected GPU divider control type' }
        $gpuDivider.SetInteractiveMove($true)
        $gpuDivider.SetInteractiveMove($false)
        Process-RemoteLine 'Received tool call shader_test: begin'
        if ($script:activeToolCalls -ne 1 -or -not $gpuDivider.ActivityRequested) { throw 'GPU activity did not start on Received tool call' }
        Process-RemoteLine 'Tool call shader_test completed:'
        if ($script:activeToolCalls -ne 0 -or -not $gpuDivider.ActivityRequested) { throw 'GPU activity hold did not remain active after completion' }
        $script:activityHoldUntil = (Get-Date).AddMilliseconds(-1)
        Refresh-DividerActivitySession
        if ($gpuDivider.ActivityRequested) { throw 'GPU activity did not stop after hold expiry' }
    } else {
        Process-RemoteLine 'Received tool call fallback_test: begin'
        Process-RemoteLine 'Tool call fallback_test completed:'
        if ($script:activeToolCalls -ne 0) { throw 'Static divider fallback broke activity state tracking' }
    }

    Write-Output 'GUI SELF TEST PASSED'
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
Hide-LegacyRemoteTerminal
Start-Remote
Refresh-Window
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
