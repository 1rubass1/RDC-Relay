// Isolated UI geometry probe, not the RDC Relay application.
// Compile with the exact embedded WPF Add-Type C# block from remote-window.ps1.
// Run STA with the four shader paths, on an authorized interactive QA desktop.
// No Host, Remote, credentials, settings, process inspection, or display changes.
// The form is transparent and nonactivating; no visual-appearance assertion.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Threading;
using System.Drawing;
using System.Windows.Forms;
using System.Windows.Media;
using System.Windows.Interop;

public static class TestV160MonitorGeometry {
 [StructLayout(LayoutKind.Sequential)] struct RECT{public int L,T,R,B;}
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out RECT r);
 [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 static string PhysicalBounds(IntPtr handle){
  IntPtr prior=IntPtr.Zero;
  try{
   prior=SetThreadDpiAwarenessContext(new IntPtr(-4));
   RECT r;
   if(prior==IntPtr.Zero||!GetWindowRect(handle,out r))return "unknown";
   return (r.R-r.L)+"x"+(r.B-r.T);
  }catch{return "unknown";}
  finally{if(prior!=IntPtr.Zero)SetThreadDpiAwarenessContext(prior);}
 }
 sealed class ProbeForm:Form{
  protected override bool ShowWithoutActivation {get{return true;}}
  protected override CreateParams CreateParams{
   get{var p=base.CreateParams;p.ExStyle|=0x08000000;return p;}
  }
 }
 static readonly BindingFlags Private=BindingFlags.Instance|BindingFlags.NonPublic;
 static int pass,fail,skip;
 static void Check(bool ok,string name){
  if(ok){Console.WriteLine("PASS "+name);pass++;}
  else{Console.WriteLine("FAIL "+name);fail++;}
 }
 static void Pump(int ms){
  var clock=Stopwatch.StartNew();
  while(clock.ElapsedMilliseconds<ms){Application.DoEvents();Thread.Sleep(10);}
 }
 static object Field(RdcGpuDividerHost host,string field){
  return typeof(RdcGpuDividerHost).GetField(field,Private).GetValue(host);
 }
 static void Move(ProbeForm form,Screen screen,int height){
  Rectangle a=screen.WorkingArea;
  form.Height=Math.Min(height,a.Height);
  form.Location=new Point(a.Left+Math.Max(0,(a.Width-form.Width)/2),a.Top+Math.Max(0,(a.Height-form.Height)/2));
  Pump(250);
 }
 static void Inspect(ProbeForm form,RdcGpuDividerHost host,Screen screen,int height,string label){
  Check(form.Width==1074&&form.Height==Math.Min(height,screen.WorkingArea.Height),label+" window fixed-width and requested height");
  Check(Screen.FromHandle(form.Handle).DeviceName==screen.DeviceName,label+" target monitor");
  Console.WriteLine("PHYSICAL "+label+" form="+PhysicalBounds(form.Handle)+" logical="+form.Width+"x"+form.Height);
  RECT anchor,popup;
  var hwnd=(IntPtr)Field(host,"particlePopupHwnd");
  if(hwnd==IntPtr.Zero||!GetWindowRect(host.Handle,out anchor)||!GetWindowRect(hwnd,out popup)){
   Console.WriteLine("NOT_CHECKED "+label+" popup HWND unavailable");skip++;return;
  }
  uint anchorDpi=0,popupDpi=0;
  try{anchorDpi=GetDpiForWindow(host.Handle);popupDpi=GetDpiForWindow(hwnd);}catch{}
  var root=(System.Windows.FrameworkElement)Field(host,"root");
  var source=System.Windows.PresentationSource.FromVisual(root) as HwndSource;
  double scale=source!=null&&source.CompositionTarget!=null?source.CompositionTarget.TransformToDevice.M11:0;
  double width=root.ActualWidth;
  var shader=(RdcDividerGlowEffect)Field(host,"particleEffect");
  Console.WriteLine("OBS "+label+" anchor="+(anchor.R-anchor.L)+"x"+(anchor.B-anchor.T)+
   " popup="+(popup.R-popup.L)+"x"+(popup.B-popup.T)+" offset="+(popup.L-anchor.L)+","+(popup.T-anchor.T)+
   " dpi="+anchorDpi+"/"+popupDpi+" wpfScale="+scale.ToString(System.Globalization.CultureInfo.InvariantCulture));
  if(anchorDpi==0||popupDpi==0||scale<=0||width<=0){
   Console.WriteLine("NOT_CHECKED "+label+" DPI/layout evidence unavailable");skip++;return;
  }
  // Compare both HWNDs in the SAME caller coordinate space. Centering
  // requires at most one pixel of rounding, irrespective of WPF DPI.
  Check(popup.L==anchor.L&&popup.R-popup.L==anchor.R-anchor.L,
   label+" native popup width and horizontal anchor");
  Check(Math.Abs((long)popup.T+popup.B-anchor.T-anchor.B)<=1,
   label+" native popup vertically centered within one half-pixel");
  Check(Math.Abs(shader.ViewportWidth-width)<1.01,label+" particle viewport matches WPF layout width");
  var caustic=(RdcDividerGlowEffect)Field(host,"causticEffect");
  Check(Math.Abs(caustic.ViewportWidth-width)<1.01,label+" inline viewport matches WPF layout width");
 }
 [STAThread] public static int Main(string[] args){
  if(args.Length!=4)throw new ArgumentException("FOUR_SHADER_PATHS_REQUIRED");
  foreach(string arg in args)if(!File.Exists(arg))throw new FileNotFoundException("SHADER_FIXTURE_MISSING");
  var screens=Screen.AllScreens;
  if(screens.Length<2){Console.WriteLine("NOT_CHECKED multi-monitor desktop required");return 2;}
  foreach(Screen screen in screens)if(screen.WorkingArea.Width<1074||screen.WorkingArea.Height<900){
   Console.WriteLine("NOT_CHECKED work area too small for this exact-size matrix");return 2;
  }
  var foreground=GetForegroundWindow();
  Application.EnableVisualStyles();
  try{
   for(int iteration=0;iteration<2;iteration++){
    using(var form=new ProbeForm()){
     form.Text="RDC isolated geometry probe";
     form.ShowInTaskbar=false;form.Opacity=0;
     form.StartPosition=FormStartPosition.Manual;
     form.FormBorderStyle=FormBorderStyle.Sizable;form.MaximizeBox=false;form.SizeGripStyle=SizeGripStyle.Hide;
     form.Size=new Size(1074,900);form.MinimumSize=new Size(1074,400);form.MaximumSize=new Size(1074,10000);
     form.Font=new Font("Segoe UI",10);
     using(var host=new RdcGpuDividerHost(args[0],args[1],args[2],args[3])){
      host.Height=7;host.Dock=DockStyle.Top;
      form.Controls.Add(host);Move(form,screens[screens.Length-1],900);
      form.Show();Pump(400);
      host.SetStopped(true);Pump(250);
      Console.WriteLine("RENDER_TIER="+(host.RenderTier>>16));
      for(int i=screens.Length-1;i>=0;i--){
       Move(form,screens[i],900);Inspect(form,host,screens[i],900,"round "+iteration+" reverse "+i);
      }
      for(int i=0;i<screens.Length;i++){
       Move(form,screens[i],750);Inspect(form,host,screens[i],750,"round "+iteration+" forward "+i);
      }
      form.Close();Pump(100);
     }
    }
   }
   Console.WriteLine("FOREGROUND_UNCHANGED_AT_END="+(foreground==GetForegroundWindow()));
   Console.WriteLine("RDC_V160_MONITOR_PASS="+pass+" FAIL="+fail+" NOT_CHECKED="+skip);
   return fail!=0?1:skip!=0?2:0;
  }catch(Exception e){Console.WriteLine("PROBE_ERROR="+e.GetType().Name+":"+e.Message);return 3;}
 }
}
