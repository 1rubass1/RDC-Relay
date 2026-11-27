param([string]$Reference,[string]$Output)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
public static class RdcWordmarkGenerator {
 public static void Build(string reference,string output){
  Color bg=Color.FromArgb(18,20,23),white=Color.FromArgb(220,220,220);
  Color[] original={Color.FromArgb(123,95,162),Color.FromArgb(191,118,67)};
  Color[] target={original[1],original[0]};
  using(var src=new Bitmap(reference)){
   if(src.Width!=997||src.Height!=74)throw new InvalidDataException("reference geometry changed");
   int w=src.Width,h=src.Height;
   // Reconstruct the reference's pixel-defined geometry, removing subpixel
   // RGB fringes. Each region uses white or the approved word color, with
   // four coverage levels; the background is transparent.
   int[,] map=new int[h,w]; var paths=new StringBuilder[17];
   for(int i=0;i<paths.Length;i++)paths[i]=new StringBuilder();
   for(int y=0;y<h;y++)for(int x=0;x<w;x++){
    Color p=src.GetPixel(x,y);int side=x<420?0:1,best=0;double error=Double.MaxValue;
    for(int k=0;k<=8;k++){
     Color c=k<=4?original[side]:white;double a=k<=4?k/4.0:(k-4)/4.0;
     double dr=p.R-(bg.R+(c.R-bg.R)*a),dg=p.G-(bg.G+(c.G-bg.G)*a),db=p.B-(bg.B+(c.B-bg.B)*a);
     double e=dr*dr+dg*dg+db*db;
     if(e<error){error=e;best=k;}
    }
    map[y,x]=best==0?0:side*8+best;
   }
   for(int y=0;y<h;y++)for(int x=0;x<w;){
    int k=map[y,x],end=x+1;while(end<w&&map[y,end]==k)end++;
    if(k!=0)paths[k].AppendFormat(CultureInfo.InvariantCulture,"M{0} {1}h{2}v1h-{2}z",x,y,end-x);
    x=end;
   }
   Directory.CreateDirectory(output);
   var svg=new StringBuilder("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 997 74\" shape-rendering=\"crispEdges\">\n");
   for(int k=1;k<=16;k++){
    int side=(k-1)/8,j=(k-1)%8+1;Color c=j<=4?target[side]:white;
    double a=(j<=4?j:j-4)/4.0;
    if(paths[k].Length>0)svg.AppendFormat(CultureInfo.InvariantCulture,"<path fill=\"#{0:X2}{1:X2}{2:X2}\" fill-opacity=\"{3}\" d=\"{4}\"/>\n",c.R,c.G,c.B,a,paths[k]);
   }
   svg.Append("</svg>\n");File.WriteAllText(Path.Combine(output,"rdc-wordmark.svg"),svg.ToString(),new UTF8Encoding(false));
   foreach(int dpi in new[]{96,120,144,168,192}){
    int dw=(int)Math.Round(w*dpi/96.0),dh=(int)Math.Round(h*dpi/96.0);
    using(var bmp=new Bitmap(dw,dh,PixelFormat.Format32bppArgb)){
     for(int y=0;y<dh;y++)for(int x=0;x<dw;x++){
      int k=map[Math.Min(h-1,(int)((y+0.5)*h/dh)),Math.Min(w-1,(int)((x+0.5)*w/dw))];
      if(k==0)continue;
      int side=(k-1)/8,j=(k-1)%8+1;Color c=j<=4?target[side]:white;
      bmp.SetPixel(x,y,Color.FromArgb((int)Math.Round(255*(j<=4?j:j-4)/4.0),c));
     }
     bmp.Save(Path.Combine(output,"rdc-wordmark-"+dpi+".png"),ImageFormat.Png);
    }
   }
  }
 }
}
'@
[RdcWordmarkGenerator]::Build($Reference,$Output)
