// RDC Relay 1.6 RC1: kernel-proven Host-owned Windows Job.
// Only a NEW process created suspended by this Host is ever assigned.
// Never imports/adopts, name-kills or terminates a pre-existing Remote.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.ComponentModel;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Shared Host/Job source-path guard. A Portable extracted to the OS Desktop
// may inherit genuine Windows Cloud Files reparse ancestors (OneDrive).
// Only existing OS-reported Desktop ancestors with a verified Cloud Files
// reparse tag are exempt. No child/sibling junction, symlink, or alternate
// OneDrive root is ever trusted; owned runtime state remains in LocalAppData.
internal static class RdcOwnerCloudDesktopPath {
 [StructLayout(LayoutKind.Sequential)]
 struct FileAttributeTagInfo {public uint FileAttributes;public uint ReparseTag;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,
   uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int infoClass,
   out FileAttributeTagInfo info,uint size);
 internal static bool IsWindowsDesktopCloudAncestor(string inspected,string requested){
  string desktop=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
  if(String.IsNullOrEmpty(desktop))return false;
  desktop=Path.GetFullPath(desktop).TrimEnd(Path.DirectorySeparatorChar);
  string full=Path.GetFullPath(requested);
  string parent=Path.GetFullPath(inspected);
  bool within=String.Equals(full,desktop,StringComparison.OrdinalIgnoreCase)||
   full.StartsWith(desktop+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
  bool ancestor=String.Equals(parent,desktop,StringComparison.OrdinalIgnoreCase)||
   desktop.StartsWith(parent.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,
    StringComparison.OrdinalIgnoreCase);
  if(!within||!ancestor||!Directory.Exists(parent))return false;
  using(SafeFileHandle handle=CreateFile(parent,0,7,IntPtr.Zero,3,
    0x02000000u|0x00200000u,IntPtr.Zero)){
   if(handle==null||handle.IsInvalid)return false;
   FileAttributeTagInfo info;
   if(!GetFileInformationByHandleEx(handle,9,out info,8))return false;
   // IO_REPARSE_TAG_CLOUD and its numbered Windows Cloud Files variants.
   // Never accept IO_REPARSE_TAG_MOUNT_POINT or IO_REPARSE_TAG_SYMLINK.
   return (info.ReparseTag & 0xFFFF0FFFu)==0x9000001Au;
  }
 }
 internal static void CheckPath(string path,string refusal){
  string full=Path.GetFullPath(path),cursor=full;
  while(!String.IsNullOrEmpty(cursor)){
   if(File.Exists(cursor)||Directory.Exists(cursor)){
    if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0 &&
       !IsWindowsDesktopCloudAncestor(cursor,full))
     throw new InvalidOperationException(refusal);
   }
   string p=Path.GetDirectoryName(cursor);
   if(String.IsNullOrEmpty(p)||String.Equals(p,cursor,StringComparison.Ordinal))break;
   cursor=p;
  }
 }
}

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
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool GetExitCodeProcess(IntPtr process,out uint exitCode);
 // Capture is opt-in. The caller must continuously drain until EOF; it is
 // not yet used by the production Host. Only the explicit handle list is inherited.
 [StructLayout(LayoutKind.Sequential)]
 struct SECURITY_ATTRIBUTES {public int length;public IntPtr descriptor;[MarshalAs(UnmanagedType.Bool)]public bool inherit;}
 [StructLayout(LayoutKind.Sequential)]
 struct STARTUPINFOEX {public STARTUPINFO info;public IntPtr attributes;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="CreateProcessW")]
 static extern bool CreateProcessCaptured(string application,StringBuilder command,IntPtr procSecurity,
  IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,
  ref STARTUPINFOEX startup,out PROCESS_INFORMATION result);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref SECURITY_ATTRIBUTES sa,uint size);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool SetHandleInformation(IntPtr handle,uint mask,uint flags);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="CreateFileW")]
 static extern IntPtr OpenCaptureInput(string name,uint access,uint share,ref SECURITY_ATTRIBUTES sa,
  uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,int flags,ref IntPtr size);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,
  IntPtr size,IntPtr previous,IntPtr returned);
 [DllImport("kernel32.dll")]
 static extern void DeleteProcThreadAttributeList(IntPtr list);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool PeekNamedPipe(IntPtr pipe,IntPtr buffer,uint size,IntPtr read,out uint available,IntPtr left);
 [DllImport("kernel32.dll",SetLastError=true)]
 static extern bool ReadFile(IntPtr handle,byte[] buffer,uint count,out uint read,IntPtr overlapped);
 IntPtr captureRead=IntPtr.Zero;
 bool captureEof;
 static void CloseCaptureHandle(ref IntPtr h){
  if(h!=IntPtr.Zero&&h!=new IntPtr(-1))CloseHandle(h);
  h=IntPtr.Zero;
 }
 // The parent keeps only the non-inheritable read end. Both output streams
 // share one kernel pipe, preserving the observed merged byte sequence.
 bool CreateCapturedChild(string application,StringBuilder command,string cwd,IntPtr environment,out PROCESS_INFORMATION pi){
  pi=new PROCESS_INFORMATION();
  IntPtr read=IntPtr.Zero,write=IntPtr.Zero,input=IntPtr.Zero,list=IntPtr.Zero,values=IntPtr.Zero;
  bool initialized=false;
  try{
   var sa=new SECURITY_ATTRIBUTES{length=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)),inherit=true};
   if(!CreatePipe(out read,out write,ref sa,65536)||
      !SetHandleInformation(read,1,0))
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_CAPTURE_PIPE");
   input=OpenCaptureInput("NUL",0x80000000u,3,ref sa,3,0,IntPtr.Zero);
   if(input==new IntPtr(-1))throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_CAPTURE_STDIN");
   IntPtr size=IntPtr.Zero;
   InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);
   if(size==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_CAPTURE_ATTRIBUTE_SIZE");
   list=Marshal.AllocHGlobal(size);
   if(!InitializeProcThreadAttributeList(list,1,0,ref size))
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_CAPTURE_ATTRIBUTE_INIT");
   initialized=true;
   values=Marshal.AllocHGlobal(2*IntPtr.Size);
   Marshal.WriteIntPtr(values,0,write);Marshal.WriteIntPtr(values,IntPtr.Size,input);
   if(!UpdateProcThreadAttribute(list,0,new IntPtr(0x00020002),values,
     new IntPtr(2*IntPtr.Size),IntPtr.Zero,IntPtr.Zero))
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_CAPTURE_HANDLE_LIST");
   var sx=new STARTUPINFOEX();
   sx.info.cb=(uint)Marshal.SizeOf(typeof(STARTUPINFOEX));sx.info.dwFlags=0x100;
   sx.info.hStdInput=input;sx.info.hStdOutput=write;sx.info.hStdError=write;sx.attributes=list;
   if(!CreateProcessCaptured(application,command,IntPtr.Zero,IntPtr.Zero,true,
      0x00000004u|0x08000000u|0x00080000u|0x00000400u,environment,cwd,ref sx,out pi))
    throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_CAPTURE_CREATE_PROCESS");
   captureRead=read;read=IntPtr.Zero;
   return true;
  }finally{
   if(initialized)DeleteProcThreadAttributeList(list);
   if(list!=IntPtr.Zero)Marshal.FreeHGlobal(list);
   if(values!=IntPtr.Zero)Marshal.FreeHGlobal(values);
   CloseCaptureHandle(ref read);CloseCaptureHandle(ref write);CloseCaptureHandle(ref input);
  }
 }
 // Single-reader API: no blocking read when no data is available. A zero
 // result is not EOF; caller must distinguish an idle child from closed pipe.
 public int ReadCaptured(byte[] buffer,out bool eof){
  if(buffer==null||buffer.Length==0||buffer.Length>65536)throw new ArgumentException("RC1_CAPTURE_BUFFER");
  if(!started||disposed||captureRead==IntPtr.Zero)throw new InvalidOperationException("RC1_CAPTURE_BOUNDARY");
  eof=captureEof;if(eof)return 0;
  uint available;
  if(!PeekNamedPipe(captureRead,IntPtr.Zero,0,IntPtr.Zero,out available,IntPtr.Zero)){
   int error=Marshal.GetLastWin32Error();
   if(error==109||error==232){eof=captureEof=true;return 0;}
   throw new Win32Exception(error,"RC1_CAPTURE_PEEK");
  }
  if(available==0)return 0;
  uint count;
  if(!ReadFile(captureRead,buffer,Math.Min(available,(uint)buffer.Length),out count,IntPtr.Zero)){
   int error=Marshal.GetLastWin32Error();
   if(error==109||error==232){eof=captureEof=true;return 0;}
   throw new Win32Exception(error,"RC1_CAPTURE_READ");
  }
  return checked((int)count);
 }
 IntPtr job=IntPtr.Zero,process=IntPtr.Zero;
 int pid;long born;int session;
 bool started,disposed,stopRequested;
 public int Pid {get{return pid;}}
 public long BornUtcTicks {get{return born;}}
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
  RdcOwnerCloudDesktopPath.CheckPath(path,"RC1_OWNED_REPARSE_DENIED");
 }
 public void Start(string executable,string arguments,string cwd,string logPath) {
  StartCore(executable,arguments,cwd,logPath,false);
 }
 public void StartCaptured(string executable,string arguments,string cwd){
  StartCore(executable,arguments,cwd,null,true);
 }
 // Use the same already validated runtime for npm's lifecycle subprocesses.
 // The installing process may have inherited PATH before the Node MSI ran.
 // Never modify the Host, user or machine PATH, or log inherited variables.
 static string ChildEnvironment(string executable){
  string dir=Path.GetDirectoryName(executable);
  if(String.IsNullOrEmpty(dir)||dir.IndexOfAny(new[]{';','"','\0'})>=0)
   throw new InvalidOperationException("RC1_OWNED_RUNTIME_PATH_INVALID");
  var variables=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  foreach(DictionaryEntry entry in Environment.GetEnvironmentVariables())
   variables[(string)entry.Key]=(string)entry.Value;
  string oldPath;variables.TryGetValue("PATH",out oldPath);
  variables["PATH"]=dir+(String.IsNullOrEmpty(oldPath)?"":";"+oldPath);
  var block=new StringBuilder();
  foreach(var entry in variables)block.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
  block.Append('\0');
  return block.ToString();
 }
 void StartCore(string executable,string arguments,string cwd,string logPath,bool capture) {
  if(started||disposed)throw new InvalidOperationException("RC1_OWNED_ALREADY_USED");
  executable=Path.GetFullPath(executable);cwd=Path.GetFullPath(cwd);
  SafePath(executable);SafePath(cwd);
  if(!capture){logPath=Path.GetFullPath(logPath);SafePath(logPath);}
  if(!File.Exists(executable)||!Directory.Exists(cwd)||(!capture&&File.Exists(logPath)))
   throw new InvalidOperationException("RC1_OWNED_START_PATH_REFUSED");
  if(arguments==null||arguments.Length>512||
     arguments.IndexOfAny(new char[]{'\r','\n','>','<','|','&'})>=0)
   throw new InvalidOperationException("RC1_OWNED_ARGUMENTS_REFUSED");
  // Only the verified Node npx.cmd shim may be used to start pinned Remote.
  // No arbitrary shell command or user string enters this launcher.
  if(!String.Equals(Path.GetFileName(executable),"npx.cmd",StringComparison.OrdinalIgnoreCase)||
     (arguments!="--yes @wonderwhy-er/desktop-commander@0.2.52 remote" &&
      arguments!="--yes @wonderwhy-er/desktop-commander@0.2.52 remote --logout"))
   throw new InvalidOperationException("RC1_OWNED_PIN_REFUSED");
  if(capture&&arguments!="--yes @wonderwhy-er/desktop-commander@0.2.52 remote")
   throw new InvalidOperationException("RC1_CAPTURE_REMOTE_ONLY");
  string cmdExe=Path.Combine(Environment.SystemDirectory,"cmd.exe");
  SafePath(cmdExe);
  var command=new StringBuilder("\""+cmdExe+"\" /D /S /C \"\""+executable+
   "\" "+arguments+(capture?"\"":" > \""+logPath+"\" 2>&1\""));
  IntPtr handle=CreateJobObjectW(IntPtr.Zero,null);
  if(handle==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_JOB_CREATE");
  var si=new STARTUPINFO();si.cb=(uint)Marshal.SizeOf(typeof(STARTUPINFO));
  var pi=new PROCESS_INFORMATION();
  bool created=false,assigned=false;
  IntPtr environment=IntPtr.Zero;
  try{
   environment=Marshal.StringToHGlobalUni(ChildEnvironment(executable));
   // CREATE_SUSPENDED | CREATE_NO_WINDOW: assignment precedes first instruction,
   // so all descendants inherit the exact private kernel Job membership.
   if(capture){CreateCapturedChild(cmdExe,command,cwd,environment,out pi);}
   else if(!CreateProcessW(cmdExe,command,IntPtr.Zero,IntPtr.Zero,false,
      0x00000004u|0x08000000u|0x00000400u,environment,cwd,ref si,out pi))
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
   if(environment!=IntPtr.Zero)Marshal.FreeHGlobal(environment);
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
   if(!started)CloseCaptureHandle(ref captureRead);
  }
 }
 // A complete command requires both the cmd.exe root's exit status and zero
 // live descendants in its private Job. Never infer success from PID absence.
 public bool TryGetCompletedExitCode(out int exitCode) {
  exitCode=0;
  if(disposed||!started||job==IntPtr.Zero||process==IntPtr.Zero)
   throw new InvalidOperationException("RC1_OWNED_COMPLETION_BOUNDARY");
  JOB_ACCOUNTING a;
  if(!Accounting(out a))throw new InvalidOperationException("RC1_OWNED_JOB_QUERY_FAILED");
  if(a.active>0)return false;
  uint wait=WaitForSingleObject(process,0);
  // Job accounting may reach zero just before the root handle signals.
  // This is pending completion, not proof of exit or a terminal failure.
  if(wait==258)return false;
  if(wait!=0)throw new InvalidOperationException("RC1_OWNED_ROOT_EXIT_UNVERIFIED");
  uint nativeCode;
  if(!GetExitCodeProcess(process,out nativeCode))
   throw new Win32Exception(Marshal.GetLastWin32Error(),"RC1_OWNED_EXIT_CODE_FAILED");
  exitCode=unchecked((int)nativeCode);
  return true;
 }
 // Explicit GUI-confirmed stop: kernel private Job contains only descendants
 // of this newly-created suspended root. No process name, HWND, or PID kill.
 // On failure, report it; never pretend the entire tree exited.
 public bool StopOwnedOnly(int timeoutMs) {
  if(disposed||!started||job==IntPtr.Zero||timeoutMs<1000||timeoutMs>15000)
   throw new InvalidOperationException("RC1_OWNED_STOP_BOUNDARY");
  JOB_ACCOUNTING a;
  if(!Accounting(out a))throw new InvalidOperationException("RC1_OWNED_JOB_QUERY_FAILED");
  // A late Stop on an already empty Job is not a termination request.
  if(a.active==0)return true;
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
  CloseCaptureHandle(ref captureRead);
  if(process!=IntPtr.Zero){CloseHandle(process);process=IntPtr.Zero;}
  if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}
 }
}
