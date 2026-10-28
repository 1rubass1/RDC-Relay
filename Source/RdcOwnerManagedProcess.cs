// RDC Relay 1.6 RC1: kernel-proven Host-owned Windows Job.
// Only a NEW process created suspended by this Host is ever assigned.
// Never imports/adopts, name-kills or terminates a pre-existing Remote.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public sealed class RdcOwnerManagedProcess : IDisposable {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
 struct STARTUPINFO {
  public uint cb; public string lpReserved,lpDesktop,lpTitle;
  public uint dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
  public ushort wShowWindow,cbReserved2;
  public IntPtr lpReserved2,hStdInput,hStdOutput,hStdError;
 }
 [StructLayout(LayoutKind.Sequential)]
 struct PROCESS_INFORMATION {public IntPtr process,thread;public uint pid,threadId;}
 [StructLayout(LayoutKind.Sequential)]
 struct JOB_ACCOUNTING {
  public long totalUserTime,totalKernelTime,periodUserTime,periodKernelTime;
  public uint pageFaults,total,active,terminated;
 }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern bool CreateProcessW(string application,StringBuilder command,IntPtr procSecurity,
  IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,
  ref STARTUPINFO startup,out PROCESS_INFORMATION result);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern IntPtr CreateJobObjectW(IntPtr security,string name);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool answer);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool QueryInformationJobObject(IntPtr job,int info,out JOB_ACCOUNTING value,int length,IntPtr returned);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool TerminateJobObject(IntPtr job,uint code);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern uint ResumeThread(IntPtr thread);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool TerminateProcess(IntPtr process,uint exitCode);
 IntPtr job=IntPtr.Zero,process=IntPtr.Zero;
 int pid;long born;int session;
 bool started,disposed,stopRequested;
 public int Pid {get{return pid;}}
 public long BirthTicks {get{return born;}}
 public int Session {get{return session;}}
 public bool HasStarted {get{return started;}}
 public bool StopRequested {get{return stopRequested;}}
 public bool Running {
  get {
   if(!started||disposed)return false;
   JOB_ACCOUNTING a;return Accounting(out a)&&a.active>0;
  }
 }
 bool Accounting(out JOB_ACCOUNTING a) {
  a=new JOB_ACCOUNTING();
  return job!=IntPtr.Zero && QueryInformationJobObject(job,1,out a,Marshal.SizeOf(typeof(JOB_ACCOUNTING)),IntPtr.Zero);
 }
 static void SafePath(string path) {
  string current=Path.GetFullPath(path);
  while(!String.IsNullOrEmpty(current)){
   if(File.Exists(current)||Directory.Exists(current)){
    if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)
     throw new InvalidOperationException("RC1_OWNED_REPARSE_DENIED");
   }
   string parent=Path.GetDirectoryName(current);
   if(String.IsNullOrEmpty(parent)||parent==current)break;
   current=parent;
  }
 }
 public void Start(string executable,string arguments,string cwd,string logPath) {
  if(started||disposed)throw new InvalidOperationException("RC1_OWNED_ALREADY_USED");
  executable=Path.GetFullPath(executable);cwd=Path.GetFullPath(cwd);
  logPath=Path.GetFullPath(logPath);
  SafePath(executable);SafePath(cwd);SafePath(logPath);
  if(!File.Exists(executable)||!Directory.Exists(cwd)||File.Exists(logPath))
   throw new InvalidOperationException("RC1_OWNED_START_PATH_REFUSED");
  if(arguments==null||arguments.Length>512||
     arguments.IndexOfAny(new char[]{'\r','\n','>','<','|','&'})>=0)
   throw new InvalidOperationException("RC1_OWNED_ARGUMENTS_REFUSED");
  // Only the verified Node npx.cmd shim may be used to start pinned Remote.
  // No arbitrary shell command or user string enters this launcher.
  if(!String.Equals(Path.GetFileName(executable),"npx.cmd",StringComparison.OrdinalIgnoreCase)||
     arguments!="--yes @wonderwhy-er/desktop-commander@0.2.52 remote")
   throw new InvalidOperationException("RC1_OWNED_PIN_REFUSED");
  string cmdExe=Path.Combine(Environment.SystemDirectory,"cmd.exe");
  SafePath(cmdExe);
  var command=new StringBuilder("\""+cmdExe+"\" /D /S /C \"\""+executable+
   "\" "+arguments+" > \""+logPath+"\" 2>&1\"");
  IntPtr handle=CreateJobObjectW(IntPtr.Zero,null);
  if(handle==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_JOB_CREATE");
  var si=new STARTUPINFO();si.cb=(uint)Marshal.SizeOf(typeof(STARTUPINFO));
  var pi=new PROCESS_INFORMATION();
  bool created=false,assigned=false;
  try{
   // CREATE_SUSPENDED | CREATE_NO_WINDOW: assignment precedes first instruction,
   // so all descendants inherit the exact private kernel Job membership.
   if(!CreateProcessW(cmdExe,command,IntPtr.Zero,IntPtr.Zero,false,
      0x00000004u|0x08000000u,IntPtr.Zero,cwd,ref si,out pi))
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_CREATE_PROCESS");
   created=true;
   if(!AssignProcessToJobObject(handle,pi.process))
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_ASSIGN_JOB");
   assigned=true;
   bool member;
   if(!IsProcessInJob(pi.process,handle,out member)||!member)
    throw new InvalidOperationException("RC1_OWNED_JOB_MEMBERSHIP_UNKNOWN");
   if(ResumeThread(pi.thread)==0xffffffffu)
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_RESUME");
   // Record OS identity, not untrusted GUI-provided PID.
   using(Process p=Process.GetProcessById(checked((int)pi.pid))){
    born=p.StartTime.ToUniversalTime().Ticks;session=p.SessionId;
   }
   pid=checked((int)pi.pid);process=pi.process;pi.process=IntPtr.Zero;
   job=handle;handle=IntPtr.Zero;started=true;
  }finally{
   if(pi.thread!=IntPtr.Zero)CloseHandle(pi.thread);
   if(pi.process!=IntPtr.Zero){
    // This handle is ONLY our freshly created process, suspended before its
    // first instruction. Never abandon it running after construction failure.
    if(created){
     if(assigned){TerminateJobObject(handle,1);}
     else{TerminateProcess(pi.process,1);}
     WaitForSingleObject(pi.process,2000);
    }
    CloseHandle(pi.process);
   }
   if(handle!=IntPtr.Zero)CloseHandle(handle);
  }
 }
 // Explicit GUI-confirmed stop: kernel private Job contains only descendants
 // of this newly-created suspended root. No process name, HWND, or PID kill.
 // On failure, report it; never pretend the entire tree exited.
 public bool StopOwnedOnly(int timeoutMs) {
  if(disposed||!started||job==IntPtr.Zero||timeoutMs<1000||timeoutMs>15000)
   throw new InvalidOperationException("RC1_OWNED_STOP_BOUNDARY");
  JOB_ACCOUNTING a;
  if(!Accounting(out a))throw new InvalidOperationException("RC1_OWNED_JOB_QUERY_FAILED");
  if(a.active==0){stopRequested=true;return true;}
  bool member;
  if(process==IntPtr.Zero||!IsProcessInJob(process,job,out member)||!member)
   throw new InvalidOperationException("RC1_OWNED_ROOT_MEMBERSHIP_UNVERIFIED");
  stopRequested=true;
  if(!TerminateJobObject(job,0))
   throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_JOB_STOP_FAILED");
  var timer=Stopwatch.StartNew();
  do{
   if(!Accounting(out a))throw new InvalidOperationException("RC1_OWNED_JOB_RECHECK_FAILED");
   if(a.active==0)return true;
   System.Threading.Thread.Sleep(80);
  }while(timer.ElapsedMilliseconds<timeoutMs);
  return false;
 }
 public void Dispose(){
  if(disposed)return;disposed=true;
  // Do not terminate on dispose: a crash/failure must never guess that
  // leftover Remote descendants are safe to kill. Next Host treats as Adopted.
  if(process!=IntPtr.Zero){CloseHandle(process);process=IntPtr.Zero;}
  if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}
 }
}
