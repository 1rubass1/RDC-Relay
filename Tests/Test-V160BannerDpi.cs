// Isolated RichEdit layout probe; synthetic art, no live Host or user data.
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.Threading;
public static class TestV160BannerDpi {
 [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
 sealed class ProbeForm:Form {
  protected override bool ShowWithoutActivation {get{return true;}}
  protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x08000000;return p;}}
 }
 static string Art(int columns) {
  string unit="\u2588\u2588\u2557 \u2554\u2550\u255d ";
  var s=new System.Text.StringBuilder("  ");
  while(s.Length<columns)s.Append(unit);
  return s.ToString().Substring(0,columns-1)+"\u2588";
 }
 static void Pump(){for(int i=0;i<15;i++){Application.DoEvents();Thread.Sleep(10);}}
 [STAThread] public static int Main(string[] args){
  if(args.Length==1&&args[0]=="system-aware")Console.WriteLine("SYSTEM_AWARE="+SetProcessDPIAware());
  Application.EnableVisualStyles();
  using(var f=new ProbeForm())using(var box=new RdcLogBox())using(var font=new Font("Consolas",9)){
   f.ShowInTaskbar=false;f.Opacity=0;f.StartPosition=FormStartPosition.Manual;
   f.ClientSize=new Size(1038,600);box.Dock=DockStyle.Fill;box.BorderStyle=BorderStyle.None;
   box.Font=font;box.WordWrap=true;box.ScrollBars=RichTextBoxScrollBars.None;box.OwnerBannerLeadingColumn=true;
   f.Controls.Add(box);f.Show();Pump();
   foreach(Screen screen in Screen.AllScreens){
    f.Location=new Point(screen.WorkingArea.Left+20,screen.WorkingArea.Top+20);Pump();
    foreach(int cols in new[]{110,120,125,130,140}){
     string row=Art(cols);
     box.Text=String.Join("\n",new[]{row,row,row,row,row,row,"","Remote Connection","Ordinary text"});
     box.StyleStartupBanner(Color.FromArgb(191,118,67),Color.FromArgb(123,95,162));
     box.ApplyCompactHeaderLineArtSpacing();box.Select(0,0);box.SetViewPosition(0,0);Pump();
     int wrap=0;int minPitch=999,maxPitch=0;int previous=-1;
     for(int i=0;i<6;i++){
      int start=i*(row.Length+1);
      Point a=box.GetPositionFromCharIndex(start+2),z=box.GetPositionFromCharIndex(start+row.Length-1);
      if(a.Y!=z.Y)wrap++;
      if(previous>=0){int pitch=a.Y-previous;minPitch=Math.Min(minPitch,pitch);maxPitch=Math.Max(maxPitch,pitch);}
      previous=a.Y;
     }
     Console.WriteLine("OBS dpi="+GetDpiForWindow(box.Handle)+" width="+box.ClientSize.Width+" cols="+cols+" wrapped="+wrap+" pitch="+minPitch+"/"+maxPitch+" font="+box.Font.Name+" "+box.Font.Size);
    }
   }
   f.Close();
  }
  return 0;
 }
}
