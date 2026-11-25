// RDC Relay 1.6 release-only maintenance choice. Presentation only.
// The Setup transaction must re-detect the product and confirm the selected
// action before any files, registry keys or shortcuts are modified.
using System;
using System.Drawing;
using System.Windows.Forms;

internal sealed class RdcReleaseMaintenanceDialog : Form {
 internal RdcMaintenanceAction Choice {get;private set;}
 internal readonly RdcMaintenanceDecision Decision;
 readonly string uiLocale;
 static readonly Font HeadingFont=new Font("Segoe UI",15f,FontStyle.Bold);
 internal RdcReleaseMaintenanceDialog(RdcMaintenanceDecision decision)
  :this(decision,null){}
 internal RdcReleaseMaintenanceDialog(RdcMaintenanceDecision decision,string locale){
  if(decision==null)throw new ArgumentNullException("decision");
  if(decision.Kind==RdcMaintenanceKind.Fresh)
   throw new ArgumentException("Fresh installations use the location dialog");
  Decision=decision;
  uiLocale=locale??RdcReleaseUiLanguage.Resolve(true);
  Choice=RdcMaintenanceAction.Cancel;
  Text=U("installer.maintenance.title","RDC Relay — установка");
  Font=new Font("Segoe UI",10f,FontStyle.Regular);
  AutoScaleMode=AutoScaleMode.Font;
  BackColor=SystemColors.Window;
  FormBorderStyle=FormBorderStyle.FixedDialog;
  StartPosition=FormStartPosition.CenterScreen;
  MaximizeBox=false;MinimizeBox=false;
  ClientSize=new Size(620,238);
  Label heading=new Label{Name="RdcMaintenanceHeading",Font=HeadingFont,
    Location=new Point(24,20),Size=new Size(572,42)};
  Label description=new Label{Name="RdcMaintenanceDescription",
    Location=new Point(24,71),Size=new Size(570,85)};
  Panel footer=new Panel{Dock=DockStyle.Bottom,Height=66,BackColor=SystemColors.Control};
  Button cancel=new Button{Name="RdcMaintenanceCancel",Text=U("installer.maintenance.cancel","Отмена"),
    Size=new Size(114,36),Location=new Point(477,14),DialogResult=DialogResult.Cancel};
  footer.Controls.Add(cancel);
  CancelButton=cancel;
  switch(decision.Kind){
   case RdcMaintenanceKind.Upgrade:
    heading.Text=U("installer.maintenance.upgradeHeading","Доступно обновление");
    description.Text=V("installer.maintenance.upgradeDescription","Установлена версия {installedVersion}. Доступна версия {targetVersion}.");
    AddAction(footer,"RdcMaintenancePrimary",U("installer.maintenance.update","Обновить"),RdcMaintenanceAction.Update,218);
    AddAction(footer,"RdcMaintenanceRemove",U("installer.maintenance.uninstall","Удалить"),RdcMaintenanceAction.Uninstall,347);
    break;
   case RdcMaintenanceKind.Repair:
    heading.Text=U("installer.maintenance.installedHeading","RDC Relay уже установлен");
    description.Text=V("installer.maintenance.repairDescription","Установлена версия {installedVersion}. Выберите действие.");
    AddAction(footer,"RdcMaintenancePrimary",U("installer.maintenance.repair","Восстановить"),RdcMaintenanceAction.Repair,218);
    AddAction(footer,"RdcMaintenanceRemove",U("installer.maintenance.uninstall","Удалить"),RdcMaintenanceAction.Uninstall,347);
    break;
   case RdcMaintenanceKind.NewerInstalled:
    heading.Text=U("installer.maintenance.newerHeading","Установлена более новая версия");
    description.Text=V("installer.maintenance.newerDescription","На компьютере уже установлена версия {installedVersion}. Установщик версии {targetVersion} не может её заменить.");
    cancel.Text=U("installer.maintenance.close","Закрыть");
    break;
   default:
    heading.Text=U("installer.maintenance.errorHeading","Не удалось продолжить установку");
    description.Text=decision.Reason=="PILOT_MIGRATION_NOT_VERIFIED"?
     U("installer.maintenance.pilotMigrationBlocked","Обнаружена тестовая версия RDC Relay. Чтобы продолжить установку, завершите переход с тестовой версии."):
     U("installer.maintenance.unverifiedInstall","Не удалось проверить установленную программу. Ничего не изменено.");
    cancel.Text=U("installer.maintenance.close","Закрыть");
    break;
  }
  Controls.Add(heading);
  Controls.Add(description);
  Controls.Add(footer);
 }
 string U(string key,string fallback){
  return RdcReleaseUiLanguage.Text(uiLocale,key,fallback);
 }
 string V(string key,string fallback){
  return RdcReleaseUiLanguage.Format(uiLocale,key,fallback,null,
   Decision.InstalledVersion,Decision.TargetVersion);
 }
 void AddAction(Panel footer,string name,string text,RdcMaintenanceAction choice,int x){
  Button button=new Button{Name=name,Text=text,Size=new Size(120,36),
    Location=new Point(x,14)};
  button.Click+=delegate{Choice=choice;DialogResult=DialogResult.OK;Close();};
  footer.Controls.Add(button);
  if(choice==RdcMaintenanceAction.Update||choice==RdcMaintenanceAction.Repair)
   AcceptButton=button;
 }
 internal static RdcMaintenanceAction Choose(RdcMaintenanceDecision decision){
  return Choose(decision,null);
 }
 // The future Setup policy can explicitly pass the suggested/selected locale.
 // That choice never changes which destructive actions are authorized.
 internal static RdcMaintenanceAction Choose(RdcMaintenanceDecision decision,string locale){
  using(var dialog=new RdcReleaseMaintenanceDialog(decision,locale)){
   dialog.ShowDialog();
   return dialog.Choice;
  }
 }
}
