// Windows Forms path selection for the future FULL Host/GUI 1.6.0 installer.
// No process, registry, shortcut or filesystem mutations occur here.
// This is NOT the existing 1.5.x stable Setup or private RC1 shortcut overlay.
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

internal static class RdcReleaseInstallLocation {
 internal static string SuggestedPath() {
  string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
  if(String.IsNullOrWhiteSpace(local))throw new IOException("RDC_INSTALL_NO_LOCAL_APPDATA");
  return Path.Combine(local,"Programs","RDC Relay");
 }
 static string Canonical(string path) {
  return Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
 }
 static bool Under(string root,string candidate) {
  if(String.IsNullOrWhiteSpace(root))return false;
  string basePath=Canonical(root);
  string target=Canonical(candidate);
  return String.Equals(basePath,target,StringComparison.OrdinalIgnoreCase)||
   target.StartsWith(basePath+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
 }
 // Per-user product install: reject protected locations, network drives,
 // foreign occupied directories and reparse points before any write.
 // Call again immediately before commit; this preflight alone is not a transaction.
 internal static bool TryValidate(string requested,string verifiedCurrentRoot,
  string preservedStableRoot,out string normalized,out string reason) {
  normalized="";reason="";
  try {
   if(String.IsNullOrWhiteSpace(requested)){reason="EMPTY_PATH";return false;}
   string path=requested.Trim();
   if(!Path.IsPathRooted(path)||path.StartsWith(@"\\",StringComparison.Ordinal)||
      path.StartsWith(@"//",StringComparison.Ordinal)||
      path.StartsWith(@"\\?",StringComparison.Ordinal)){
    reason="NOT_LOCAL_ABSOLUTE";return false;
   }
   if(path.IndexOfAny(Path.GetInvalidPathChars())>=0 ||
      path.IndexOfAny(new[]{'*','?','"','<','>','|'})>=0 ||
      path.Length<3 || path[1]!=':' ||
      (path[2]!='\\' && path[2]!='/') ||
      path.IndexOf(':',2)>=0) {
    reason="INVALID_CHARACTER";return false;
   }
   // Windows forbids ambiguous trailing spaces/dots in file name components.
   foreach(string section in path.Split(new[]{'\\','/'},StringSplitOptions.RemoveEmptyEntries)){
    if(section.EndsWith(".",StringComparison.Ordinal)||
       section.EndsWith(" ",StringComparison.Ordinal)||
       section==".."){reason="AMBIGUOUS_COMPONENT";return false;}
   }
   string root=Path.GetPathRoot(path);
   if(String.IsNullOrEmpty(root)){reason="NOT_LOCAL_ABSOLUTE";return false;}
   string full=Canonical(path);
   if(String.Equals(full,Canonical(root),StringComparison.OrdinalIgnoreCase)){
    reason="DRIVE_ROOT";return false;
   }
   if(!String.IsNullOrWhiteSpace(verifiedCurrentRoot)&&
      !String.Equals(full,Canonical(verifiedCurrentRoot),StringComparison.OrdinalIgnoreCase)){
    reason="RELOCATION_REQUIRES_SEPARATE_WORKFLOW";return false;
   }
   if(Under(preservedStableRoot,full)){
    reason="PRESERVED_STABLE_INSTALL";return false;
   }
   if(Under(Path.Combine(Environment.GetFolderPath(
      Environment.SpecialFolder.LocalApplicationData),"RDCRelayOwnerPilot"),full)){
    reason="PILOT_DATA_PATH";return false;
   }
   string[] restricted=new[]{
    Environment.GetFolderPath(Environment.SpecialFolder.Windows),
    Environment.GetFolderPath(Environment.SpecialFolder.System),
    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
    Path.GetTempPath()
   };
   // User profile/AppData may contain an ordinary allowed target below:
   // block the directory itself, not the entire user data subtree.
   for(int i=0;i<restricted.Length;i++){
    string blocked=restricted[i];
    if(String.IsNullOrWhiteSpace(blocked))continue;
    bool recursive=i<=3 || i==7;
    bool conflict=recursive?Under(blocked,full):
      String.Equals(Canonical(blocked),full,StringComparison.OrdinalIgnoreCase);
    if(conflict){reason="PROTECTED_LOCATION";return false;}
   }
   DriveInfo drive=new DriveInfo(root);
   if(drive.DriveType!=DriveType.Fixed){reason="NOT_FIXED_LOCAL_DRIVE";return false;}
   // Only the actual installed release may re-use a nonempty directory.
   if(File.Exists(full)){reason="TARGET_IS_FILE";return false;}
   string cursor=full;
   while(!String.IsNullOrEmpty(cursor)){
    if(File.Exists(cursor)||Directory.Exists(cursor)){
     if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0){
      reason="REPARSE_PATH";return false;
     }
    }
    string parent=Path.GetDirectoryName(cursor);
    if(String.IsNullOrEmpty(parent)||String.Equals(parent,cursor,StringComparison.Ordinal))break;
    cursor=parent;
   }
   if(Directory.Exists(full)&&String.IsNullOrWhiteSpace(verifiedCurrentRoot)){
    using(var entries=Directory.EnumerateFileSystemEntries(full).GetEnumerator()){
     if(entries.MoveNext()){reason="OCCUPIED_UNKNOWN_DIRECTORY";return false;}
    }
   }
   normalized=full;return true;
  }catch(Exception){
   reason="PATH_NOT_VERIFIED";return false;
  }
 }
}

internal sealed class RdcReleasePathDialog : Form {
 readonly TextBox installPath;
 readonly Button browse;
 readonly Label instruction;
 readonly string currentRoot;
 readonly string legacyRoot;
 readonly string uiLocale;
 internal string SelectedRoot {get;private set;}
 internal RdcReleasePathDialog(string version,string verifiedCurrentRoot,string preservedStableRoot)
  :this(version,verifiedCurrentRoot,preservedStableRoot,null){}
 internal RdcReleasePathDialog(string version,string verifiedCurrentRoot,string preservedStableRoot,string locale) {
  if(String.IsNullOrWhiteSpace(version))throw new ArgumentException("VERSION_REQUIRED");
  currentRoot=verifiedCurrentRoot;
  legacyRoot=preservedStableRoot;
  uiLocale=locale??RdcReleaseUiLanguage.Resolve(!String.IsNullOrWhiteSpace(currentRoot));
  Text=RdcReleaseUiLanguage.Format(uiLocale,"installer.path.windowTitle","Установка RDC Relay {version}",version,null,null);
  Font=new Font("Segoe UI",10f);
  AutoScaleMode=AutoScaleMode.Font;
  StartPosition=FormStartPosition.CenterScreen;
  FormBorderStyle=FormBorderStyle.FixedDialog;
  MinimizeBox=false;MaximizeBox=false;ShowInTaskbar=true;
  BackColor=SystemColors.Window;
  ClientSize=new Size(620,252);
  Padding=new Padding(22);
  SelectedRoot="";
  Label title=new Label{Text=U("installer.path.heading","Выберите папку установки"),Font=new Font("Segoe UI",14f,FontStyle.Bold),
   AutoSize=false,Location=new Point(22,22),Size=new Size(570,34)};
  instruction=new Label{Text=String.IsNullOrWhiteSpace(currentRoot)?
   U("installer.path.freshDescription","Программа будет установлена в выбранную папку."):
   U("installer.path.upgradeDescription","Программа будет обновлена в текущей папке."),
   Location=new Point(22,65),Size=new Size(567,42)};
  Label pathLabel=new Label{Text=U("installer.path.folderLabel","Папка установки"),Location=new Point(22,115),Size=new Size(530,25)};
  installPath=new TextBox{Name="RdcInstallPath",Location=new Point(22,143),Size=new Size(462,26),
   Text=String.IsNullOrWhiteSpace(currentRoot)?RdcReleaseInstallLocation.SuggestedPath():currentRoot,
   ReadOnly=!String.IsNullOrWhiteSpace(currentRoot)};
  browse=new Button{Name="RdcInstallBrowse",Text=U("installer.path.browse","Обзор…"),Location=new Point(493,140),Size=new Size(104,33),
   Enabled=String.IsNullOrWhiteSpace(currentRoot)};
  browse.Click+=delegate{
   using(FolderBrowserDialog picker=new FolderBrowserDialog()){
    picker.Description=U("installer.path.browseTitle","Выберите папку для установки RDC Relay");
    picker.ShowNewFolderButton=true;
    try{
     string proposed=installPath.Text;
     if(Directory.Exists(proposed))picker.SelectedPath=proposed;
     else {
      string parent=Path.GetDirectoryName(proposed);
      if(!String.IsNullOrEmpty(parent)&&Directory.Exists(parent))picker.SelectedPath=parent;
     }
    }catch(ArgumentException){} // Invalid typed path must not prevent Browse.
    if(picker.ShowDialog(this)==DialogResult.OK){
     string selected=Path.GetFullPath(picker.SelectedPath);
     string leaf=Path.GetFileName(selected.TrimEnd(Path.DirectorySeparatorChar));
     installPath.Text=String.Equals(leaf,"RDC Relay",StringComparison.OrdinalIgnoreCase)?
      selected:Path.Combine(selected,"RDC Relay");
    }
   }
  };
  Panel footer=new Panel{Dock=DockStyle.Bottom,Height=60,
   BackColor=SystemColors.Control};
  Button confirm=new Button{Name="RdcInstallConfirm",Text=String.IsNullOrWhiteSpace(currentRoot)?
   U("installer.path.install","Установить"):U("installer.path.continue","Продолжить"),Size=new Size(118,35),
   Location=new Point(298,12)};
  Button cancel=new Button{Name="RdcInstallCancel",Text=U("installer.path.cancel","Отмена"),Size=new Size(118,35),
   Location=new Point(428,12),DialogResult=DialogResult.Cancel};
  confirm.Click+=delegate{
   string full,reason;
   if(!RdcReleaseInstallLocation.TryValidate(installPath.Text,currentRoot,legacyRoot,out full,out reason)){
    string detail=reason=="OCCUPIED_UNKNOWN_DIRECTORY"?
     U("installer.path.nonemptyFolder","В этой папке уже есть файлы. Выберите другую папку."):
     reason=="RELOCATION_REQUIRES_SEPARATE_WORKFLOW"?
     U("installer.path.cannotRelocate","При обновлении папку установки изменить нельзя."):
     U("installer.path.invalidFolder","Не удалось использовать эту папку. Выберите другую.");
    MessageBox.Show(this,detail,U("installer.path.dialogTitle","RDC Relay — путь установки"),MessageBoxButtons.OK,MessageBoxIcon.Warning);
    installPath.Focus();return;
   }
   SelectedRoot=full;
   DialogResult=DialogResult.OK;Close();
  };
  footer.Controls.Add(confirm);footer.Controls.Add(cancel);
  Controls.Add(title);Controls.Add(instruction);Controls.Add(pathLabel);
  Controls.Add(installPath);Controls.Add(browse);Controls.Add(footer);
  AcceptButton=confirm;CancelButton=cancel;
 }
 string U(string key,string fallback){
  return RdcReleaseUiLanguage.Text(uiLocale,key,fallback);
 }
 internal static DialogResult Choose(string version,string currentRoot,string legacyRoot,out string selected){
  return Choose(version,currentRoot,legacyRoot,null,out selected);
 }
 // A future migration installer must pass the actual prior-install mode's
 // selected locale; currentRoot being empty is not proof there was no 1.5.x.
 internal static DialogResult Choose(string version,string currentRoot,string legacyRoot,string locale,out string selected){
  selected="";
  using(var dialog=new RdcReleasePathDialog(version,currentRoot,legacyRoot,locale)){
   DialogResult result=dialog.ShowDialog();
   if(result==DialogResult.OK)selected=dialog.SelectedRoot;
   return result;
  }
 }
}
