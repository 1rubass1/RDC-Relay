// Offline production-policy fixture; no OAuth, network, browser, Remote or live cache.
using System;
using System.IO;
using System.Text;
using System.Globalization;
public static class TestV160QuotaRefreshPolicy {
 const string A="alpha@example.org",B="beta@example.org";
 const string Idle="Remote channel unconfirmed; awaiting new connectivity evidence";
 static int pass;
 static void Check(bool yes,string label){
  if(!yes)throw new Exception("FAIL "+label);
  Console.WriteLine("PASS "+label);pass++;
 }
 static string Choose(RdcOwnerQuotaRefreshPolicy p,long now,long open=1,bool enabled=true,string eligible=A,string ready=A,
  string cache="match",bool recent=false,bool vault=true,bool busy=false){
  return p.Decide(now,enabled,eligible,ready,open,cache,recent,vault,busy);
 }
 static void Put(string file,string email,int percent,DateTime utc){
  File.WriteAllText(file,"{\"source\":\"official-remote-who-am-i\",\"accountEmail\":\""+email+
   "\",\"remainingPercent\":"+percent.ToString(CultureInfo.InvariantCulture)+",\"observedAtUtc\":\""+
   utc.ToString("yyyy-MM-ddTHH:mm:ssZ",CultureInfo.InvariantCulture)+"\"}",new UTF8Encoding(false));
 }
 public static int Main(){
  string root=Path.Combine(Path.GetTempPath(),"RDC-V160-QUOTA-QA-"+Guid.NewGuid().ToString("N"));
  string file=Path.Combine(root,"synthetic-cache.json");
  try{
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"Ready","",A,"",true)==A,"verified owned Ready permits consent");
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"Reconnecting",Idle,A,A,false)==A,"idle lease does not invalidate existing quota identity");
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"Reconnecting",Idle,A,A,true)=="","idle lease never permits OAuth consent");
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"Reconnecting",Idle,B,A,false)=="","changed identity cannot borrow idle proof");
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"Reconnecting","Local MCP recovering",A,A,false)=="","actual reconnect not idle");
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"AuthPending",Idle,A,A,false)=="","auth pending denied");
   Check(RdcOwnerQuotaIdentity.Select(true,true,false,false,"Fault",Idle,A,A,false)=="","fault denied");
   Check(RdcOwnerQuotaIdentity.Select(false,true,false,false,"Ready","",A,A,false)==""&&
    RdcOwnerQuotaIdentity.Select(true,false,false,false,"Ready","",A,A,false)==""&&
    RdcOwnerQuotaIdentity.Select(true,true,true,false,"Ready","",A,A,false)==""&&
    RdcOwnerQuotaIdentity.Select(true,true,false,true,"Ready","",A,A,false)=="","external/dead/shutdown/switch denied");
   var p=new RdcOwnerQuotaRefreshPolicy();
   Check(Choose(p,0,ready:"")=="-Poll","stale cache refreshes in quiet owned session");
   Check(Choose(p,15,open:2)==""&&Choose(p,500,busy:true)=="","outstanding worker blocks overlap");
   p.Complete(15,true);
   Check(Choose(p,60,open:3)==""&&Choose(p,299,open:4)=="","reopen cannot bypass five minute gap");
   Check(Choose(p,300,open:4)=="-Poll","pending reopen starts poll when cooldown ends");
   p.Complete(310,true);
   Check(Choose(p,400,recent:true,open:5)==""&&Choose(p,2109,open:5)=="","fresh cache suppresses reopen and normal cadence retained");
   Check(Choose(p,2110,open:5)=="-Poll","periodic refresh works without GUI");
   p.Complete(2120,false);
   Check(Choose(p,2400,open:6)==""&&Choose(p,3019,open:7)=="","reopen cannot bypass failure backoff");
   Check(Choose(p,3020,open:7)=="-Poll","retry after fifteen minute backoff");
   p.Complete(3030,true);
   Check(Choose(p,3040,enabled:false)==""&&Choose(p,3050,enabled:true,cache:"missing",vault:false)=="","opt out/on does not bypass cooldown");
   Check(Choose(p,3320,cache:"missing",vault:false)=="-Authorize","Ready permits original first consent after explicit enable");
   p.Complete(3330,false);
   Check(Choose(p,4230,open:8,cache:"missing",vault:false)=="","failed consent never reopens browser repeatedly");
   var quiet=new RdcOwnerQuotaRefreshPolicy();
   Check(Choose(quiet,0,ready:"",cache:"missing",vault:false)=="","missing grant in idle session never opens browser");
   Check(Choose(quiet,15,ready:"",cache:"other")==""&&Choose(quiet,30,ready:A,cache:"other")=="-Authorize","known other account requires fresh Ready consent");
   quiet.Complete(40,false);
   Check(Choose(quiet,940,cache:"other")=="","wrong-account grant is not repeatedly polled");
   var fresh=new RdcOwnerQuotaRefreshPolicy();
   Check(Choose(fresh,0,recent:true)==""&&Choose(fresh,15,open:2,recent:true)=="","fresh cache at startup or reopen avoids redundant network");
   Check(Choose(fresh,320,open:3)=="-Poll","older cache triggers a bounded reopen refresh");
   fresh.Complete(330,true);
   Check(Choose(fresh,340,eligible:B,ready:B)==""&&Choose(fresh,620,eligible:B,ready:B)=="-Poll","account change respects global gap");
   var missing=new RdcOwnerQuotaRefreshPolicy();
   Check(Choose(missing,0,cache:"unknown")==""&&Choose(missing,15,cache:"missing")=="-Poll","unreadable cache does not trigger consent; missing cache reuses existing vault");
   Directory.CreateDirectory(root);
   DateTime now=new DateTime(2026,11,27,0,0,0,DateTimeKind.Utc);
   Check(RdcOwnerTrayQuotaSnapshot.Inspect(file,A,now).State=="missing","missing file explicit");
   Put(file,A,0,now.AddMinutes(-4));
   var v=RdcOwnerTrayQuotaSnapshot.Inspect(file,A,now);
   Check(v.State=="match"&&v.Fresh(now,5)&&v.Percent==0,"genuine zero and recent observation");
   Check(RdcOwnerTrayQuotaSnapshot.Read(file,B,now)==null&&RdcOwnerTrayQuotaSnapshot.Inspect(file,B,now).State=="other","wrong account never exposes quota");
   Put(file,A,79,now.AddMinutes(-60));
   v=RdcOwnerTrayQuotaSnapshot.Inspect(file,A,now);
   Check(v.State=="match"&&!v.Fresh(now,60)&&RdcOwnerTrayQuotaSnapshot.Read(file,A,now)==null,"expired cache retains identity but not displayed quota");
   Put(file,A,79,now.AddMinutes(3));
   Check(RdcOwnerTrayQuotaSnapshot.Inspect(file,A,now).State=="unknown","future timestamp refused");
   Put(file,A,101,now);
   Check(RdcOwnerTrayQuotaSnapshot.Inspect(file,A,now).State=="unknown","invalid percentage refused");
   File.WriteAllText(file,new string('x',513));
   Check(RdcOwnerTrayQuotaSnapshot.Inspect(file,A,now).State=="unknown","oversized cache refused");
   Check(RdcOwnerTrayQuotaSnapshot.VaultState(file)=="present","vault existence checked without contents");
   File.Delete(file);
   Check(RdcOwnerTrayQuotaSnapshot.VaultState(file)=="missing","missing vault explicit");
   Console.WriteLine("RDC_V160_QUOTA_POLICY_PASS="+pass);return 0;
  }catch(Exception e){Console.WriteLine(e.GetType().Name+": "+e.Message);return 1;}
  finally{
   if(File.Exists(file))File.Delete(file);
   if(Directory.Exists(root)&&Directory.GetFileSystemEntries(root).Length==0)Directory.Delete(root,false);
  }
 }
}
