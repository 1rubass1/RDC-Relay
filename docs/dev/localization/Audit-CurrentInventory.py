#!/usr/bin/env python3
"""Source vs historical index reconciliation + locale resource key inventory. No runtime actions."""
import csv,json,re,runpy
from collections import Counter
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def read_csv(name):
 with (HERE/name).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
old=read_csv('STRING_INVENTORY.csv')
new=read_csv('STRING_INVENTORY_CURRENT.csv')
assert len(old)>2500 and len(new)>3000
a={x['CandidateId']:x for x in old}
b={x['CandidateId']:x for x in new}
assert len(a)==len(old) and len(b)==len(new)
excel=runpy.run_path(str(HERE/'Classify-RemainingCandidates.py'))['workbook_ids'](HERE/'RDC_Relay_UI_Texts.xlsx')
assert len(excel)==360 and excel<=a.keys()
added=set(b)-set(a)
gone=set(a)-set(b)
shared=set(a)&set(b)
review=[b[k] for k in sorted(added) if b[k]['ReviewStatus'].startswith('REVIEW_')]
oldonly=excel-set(b)
loc={}
for language in ('ru-RU','en-US'):
 payload=json.loads((ROOT/'Source'/'lang'/(language+'.json')).read_text(encoding='utf-8-sig'))
 assert payload['locale']==language and payload['status']=='INTEGRATION_TEST'
 loc[language]=payload['strings']
ru,en=loc['ru-RU'],loc['en-US']
assert ru.keys()==en.keys() and len(ru)>=200
sources=[]
for folder,ext in [(ROOT/'Source',{'.cs','.ps1'}),(ROOT/'Installer',{'.cs'})]:
 sources.extend(p for p in folder.iterdir() if p.is_file() and p.suffix in ext and not p.name.endswith('.Generated.cs'))
texts={p.relative_to(ROOT).as_posix():p.read_text(encoding='utf-8-sig') for p in sources}
rows=[]
for key in sorted(ru):
 refs=[name for name,body in texts.items() if ("'"+key+"'") in body or ('"'+key+'"') in body]
 rex=r'\{[A-Za-z][A-Za-z0-9_]*\}|\{\d+(?::[^{}]+)?\}'
 aparams=sorted(re.findall(rex,ru[key]));bparams=sorted(re.findall(rex,en[key]))
 assert aparams==bparams,('PARAM_MISMATCH',key,aparams,bparams)
 rows.append({'SemanticKey':key,'ru-RU':ru[key],'en-US':en[key],
              'Parameters':';'.join(aparams),'SourceRefs':';'.join(refs),
              'BindingStatus':'SOURCE_REFERENCED' if refs else 'UNWIRED_PREVIEW'})
with (HERE/'RESOURCE_KEY_INVENTORY.csv').open('w',encoding='utf-8-sig',newline='') as f:
 writer=csv.DictWriter(f,fieldnames=list(rows[0]))
 writer.writeheader();writer.writerows(rows)
def summary(data,key):
 return ', '.join('%s=%s'%(x,n) for x,n in sorted(Counter(row[key] for row in data).items()))
doc=[
 '# RDC Relay 1.6.0 — refreshed source/resource inventory reconciliation','',
 '**Development audit only; not a release or translation approval.**','',
 '## Source scanner','',
 'Historical immutable STRING_INVENTORY.csv: %d unique literals.'%len(old),
 'Current STRING_INVENTORY_CURRENT.csv: %d unique literals.'%len(new),
 'Shared IDs: %d; added: %d; removed after source changes: %d.'%(len(shared),len(added),len(gone)),
 'New source candidates flagged for review: %d. Areas: %s.'%(len(review),summary(review,'Area') if review else 'none'),
 'Original Excel book: 360 source IDs still resolve in the historical CSV. Current matching IDs: %d; historical-only IDs: %d.'%(360-len(oldonly),len(oldonly)),
 '',
 'CandidateId hashes source path + exact original literal. Refactoring a visible string changes its ID: never rewrite historical Excel IDs in bulk.',
 '',
 '## Runtime semantic key inventory','',
 'RESOURCE_KEY_INVENTORY.csv contains %d RU/EN pairs, named arguments, source refs and binding state.'%len(rows),
 'Bindings: %s.'%summary(rows,'BindingStatus'),
 'Unwired keys are proposals, not production coverage. The PowerShell/C# source scanner does not index JSON; the semantic index fills that blind spot.',
 '',
 '## Open review and verification','',
 'Review %d newly flagged REVIEW_* source strings in context, especially runtime display and legacy paths. Preserve IPC/control names, provider markers and exact Remote Connection renderer anchor.'%len(review),
 'The original historical CSV remains untouched; verify current scan via Build-StringInventory.ps1 -Current -Check. The 117-item historical classification remains valid for the original inventory only.',
 '',
 '## Newly added REVIEW_* snippets (first 50)','',
 '| Area | Source line | Snippet |','| --- | --- | --- |'
]
for item in review[:50]:
 snippet=re.sub(r'\s+',' ',item['Literal']).replace('|','/')[:100]
 doc.append('| %s | %s:%s | %s |'%(item['Area'],item['Source'],item['Lines'].split(';')[0],snippet))
doc.extend(['','No release GO.'])
(HERE/'CURRENT_INVENTORY_AUDIT.md').write_text('\n'.join(doc)+'\n',encoding='utf-8')
print('SOURCE_OLD',len(old),'SOURCE_CURRENT',len(new),'STABLE',len(shared),'NEW',len(added),'REMOVED',len(gone))
print('NEW_REVIEW',len(review),summary(review,'Area') if review else '')
print('EXCEL_CURRENT_MATCHES',360-len(oldonly),'EXCEL_HISTORICAL_ONLY',len(oldonly))
print('RESOURCE_KEYS',len(rows),summary(rows,'BindingStatus'))
print('PASS_RESOURCE_SOURCE_AUDIT')
