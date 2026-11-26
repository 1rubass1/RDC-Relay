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
 static int pass,fail;
 static void Check(bool ok,string label){Console.WriteLine((ok?"PASS ":"FAIL ")+label);if(ok)pass++;else fail++;}
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
     box.Text=String.Join("\n",new[]{row,row,row,row,row,row,"","\U0001f310 Remote Connection","Ordinary text"});
     box.Select(0,box.TextLength);box.SelectionFont=box.Font;box.SelectionColor=Color.Gainsboro;
     string original=box.Text;
     var orange=Color.FromArgb(191,118,67);var purple=Color.FromArgb(123,95,162);
     Check(box.StyleStartupBanner(orange,purple),"six art rows recognized before emoji marker "+cols);
     box.ApplyCompactHeaderLineArtSpacing();box.Select(0,0);box.SetViewPosition(0,0);Pump();
     int wrap=0;int minPitch=999,maxPitch=0;int previous=-1;
     for(int i=0;i<6;i++){
      int start=i*(row.Length+1);
      Point a=box.GetPositionFromCharIndex(start+2),z=box.GetPositionFromCharIndex(start+row.Length-1);
      if(a.Y!=z.Y)wrap++;
      if(previous>=0){int pitch=a.Y-previous;minPitch=Math.Min(minPitch,pitch);maxPitch=Math.Max(maxPitch,pitch);}
      previous=a.Y;
     }
     Check(wrap==0&&minPitch==maxPitch&&minPitch>0,"six unwrapped equally spaced rows "+cols);
     bool colors=true;
     for(int i=0;i<6;i++){
      int start=i*(row.Length+1);
      box.Select(start+2,1);colors&=box.SelectionColor.ToArgb()==orange.ToArgb();
      box.Select(start+63,1);colors&=box.SelectionColor.ToArgb()==purple.ToArgb();
     }
     Check(colors,"all six row colors correct "+cols);
     box.Select(2,1);float fitted=box.SelectionFont.SizeInPoints;
     box.Select(box.Text.IndexOf("Ordinary text",StringComparison.Ordinal),1);
     Check(Math.Abs(box.SelectionFont.SizeInPoints-9)<0.01&&box.Text==original,"ordinary font and art text unchanged "+cols);
     if(cols<=120)Check(Math.Abs(fitted-9)<0.01,"original artwork size retained "+cols);
     Console.WriteLine("FIT="+fitted);
     Console.WriteLine("OBS dpi="+GetDpiForWindow(box.Handle)+" width="+box.ClientSize.Width+" cols="+cols+" wrapped="+wrap+" pitch="+minPitch+"/"+maxPitch+" font="+box.Font.Name+" "+box.Font.Size);
    }
   }
   f.Close();
  }
  Console.WriteLine("RDC_V160_BANNER_PASS="+pass+" FAIL="+fail);
  return fail==0?0:1;
 }
}
