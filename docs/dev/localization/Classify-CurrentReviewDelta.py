#!/usr/bin/env python3
"""Conservative per-source context audit of newly flagged candidates only.

Categories are evidence labels, not a declaration that all strings are localized.
"""
import csv,json,re
from collections import Counter
from pathlib import Path
root=Path(__file__).resolve().parents[3]
folder=Path(__file__).resolve().parent
def load(name):
 with (folder/name).open(encoding='utf-8-sig',newline='') as stream:return list(csv.DictReader(stream))
oldids={x['CandidateId'] for x in load('STRING_INVENTORY.csv')}
current=load('STRING_INVENTORY_CURRENT.csv')
ru=set(json.loads((root/'Source/lang/ru-RU.json').read_text(encoding='utf-8-sig'))['strings'].values())
en=set(json.loads((root/'Source/lang/en-US.json').read_text(encoding='utf-8-sig'))['strings'].values())
sourcefiles={}
for item in current:
 name=item['Source']
 if name not in sourcefiles:sourcefiles[name]=(root/name).read_text(encoding='utf-8-sig').splitlines()
result=[]
for item in current:
 if item['CandidateId'] in oldids or not item['ReviewStatus'].startswith('REVIEW_'):continue
 name=item['Source'];lines=sourcefiles[name];line=int(item['Lines'].split(';')[0])
 context=lines[line-1].strip() if 0<line<=len(lines) else ''
 literal=item['Literal']
 if literal in ('Русский','English'):
  status='FIXED_LOCALE_SELF_NAME'
  reason='Language option is shown in its own language regardless of active display locale'
 elif literal in ('{error}','{version}','{action}'):
  status='LOCKED_TEMPLATE_PARAMETER'
  reason='Named parameter used by validated display substitution, not translated directly'
 elif literal=='RDC Relay':
  status='FIXED_PRODUCT_BRAND'
  reason='Product identity and window brand stay invariant'
 elif any(t in context for t in ('Get-RdcOwnerUiText','Get-RdcOwnerDialogText','Get-Rc1JournalUiText','Get-RdcOwnerNoticeText','RdcUiLanguage.Text','RdcUiLanguage.GuiNotice','UiText(')):
  status='SOURCE_BOUND_FALLBACK'
  reason='Display-only lookup is explicit in source line'
 elif name in ('Installer/RdcReleaseMaintenanceDialog.cs','Installer/RdcReleasePathDialog.cs') and literal.startswith(('installer.maintenance.','installer.path.')):
  status='SOURCE_BOUND_INSTALLER_UI'
  reason='Prepared release Setup dialog uses standalone embedded RU/EN display key; install transaction is not connected'
 elif name=='Installer/Rc1CandidateSetup.cs' and (
   literal in ('Downloading verified Node.js 24 LTS...','Загрузка проверенного Node.js 24 LTS...',
               'Cancelling download...','Отмена загрузки...') and 'label.Text=en?' in context or
   literal.startswith(('Обнаружена неполная, неподдерживаемая или нестандартная установка Node.js.',
                       'Автоматическая установка Node.js пока доступна только для Windows x64.',
                       'Desktop Commander Remote требует Node.js и npm/npx.'))):
  status='SOURCE_BOUND_PILOT_SETUP_UI'
  reason='Reviewed private Setup prerequisite UI uses paired inline RU/EN selection; public release Setup remains separate'
 elif literal in ru or literal in en:
  status='RESOURCE_VALUE_PRESENT'
  reason='Exact text occurs in locale catalog; inspect source use separately'
 elif name=='Source/remote-window.ps1':
  status='REVIEW_LEGACY_OR_OWNER'
  reason='Shared Owner/legacy module; manual reachability review required'
 elif name=='Source/RdcOwnerRuntime.cs':
  status='REVIEW_HOST_TRAY'
  reason='Potential visible tray/Host text or fixed branch key; inspect semantics'
 elif name=='Source/rc1-owner-gui.ps1':
  status='REVIEW_OWNER_GUI'
  reason='Potential GUI status, journal diagnostic, or UI state code'
 else:
  status='REVIEW_SHARED'
  reason='Not linked to an explicit language lookup'
 result.append({**{k:item[k] for k in ('CandidateId','Area','Source','Lines','ReviewStatus','Literal')},
                'Classification':status,'SourceContext':context[:190],'Reason':reason})
assert len(result)>=100
out=folder/'CURRENT_REVIEW_DELTA.csv'
with out.open('w',encoding='utf-8-sig',newline='') as stream:
 writer=csv.DictWriter(stream,fieldnames=list(result[0]))
 writer.writeheader();writer.writerows(result)
print('CURRENT_NEW_REVIEW',len(result))
print('CLASSIFICATION',dict(Counter(row['Classification'] for row in result)))
for row in result:
 if row['Classification'].startswith('REVIEW_'):
  print(row['Classification'],row['Source'],row['Lines'].split(';')[0],repr(row['Literal'][:95]))
