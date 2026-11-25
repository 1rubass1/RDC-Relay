#!/usr/bin/env python3
"""Read-only source/resource contract check. Never starts GUI, Host or Remote."""
import json
import re
from collections import defaultdict
from pathlib import Path

root = Path(__file__).resolve().parent.parent
files = [
    root / 'Source/rc1-owner-gui.ps1',
    root / 'Source/remote-window.ps1',
    root / 'Source/RdcOwnerRuntime.cs',
    root / 'Source/RdcUiLanguage.cs',
    root / 'Source/update-notice.ps1',
]
patterns = [
    re.compile(r"Get-RdcOwnerUiText\s+'([^']+)'"),
    re.compile(r"Get-RdcOwnerDialogText\s+'([^']+)'"),
    re.compile(r"Get-Rc1JournalUiText\s+'([^']+)'"),
    re.compile(r"Get-RdcOwnerNoticeText\s+'([^']+)'"),
    re.compile(r'"(tray\.notice\.[A-Za-z0-9]+)"'),
    re.compile(r'RdcUiLanguage\.Text\(\s*catalog\s*,\s*"([^"]+)"'),
]
usages = defaultdict(set)
for filename in files:
    source = filename.read_text(encoding='utf-8-sig')
    for matcher in patterns:
        for match in matcher.finditer(source):
            usages[match.group(1)].add(filename.name)

catalogs = {}
for locale in ('ru-RU', 'en-US'):
    document = json.loads((root / 'Source/lang' / (locale + '.json')).read_text(encoding='utf-8-sig'))
    assert document.get('schema') == 'rdc-relay-i18n-v1'
    assert document.get('status') == 'INTEGRATION_TEST'
    assert document.get('locale') == locale
    assert isinstance(document.get('strings'), dict)
    catalogs[locale] = document['strings']

ru = catalogs['ru-RU']
en = catalogs['en-US']
assert ru.keys() == en.keys(), 'LOCALE_KEY_SET_MISMATCH'
assert len(ru) >= 93, 'UNEXPECTED_SMALL_CATALOG'
missing = sorted(set(usages) - ru.keys())
assert not missing, 'GUI_KEY_MISSING_FROM_RESOURCES: ' + ', '.join(missing)
for key in ru:
    assert re.fullmatch(r'[a-z][a-zA-Z0-9]*(?:\.[a-zA-Z][a-zA-Z0-9]*)+', key), ('BAD_KEY', key)
    rvalue, evalue = ru[key], en[key]
    assert isinstance(rvalue, str) and isinstance(evalue, str) and rvalue and evalue, ('EMPTY_TRANSLATION', key)
    rparams = sorted(re.findall(r'\{[A-Za-z][A-Za-z0-9_]*\}|\{\d+(?::[^{}]+)?\}', rvalue))
    eparams = sorted(re.findall(r'\{[A-Za-z][A-Za-z0-9_]*\}|\{\d+(?::[^{}]+)?\}', evalue))
    assert rparams == eparams, ('ARGUMENT_MISMATCH', key, rparams, eparams)
    assert rvalue.startswith(' ') == evalue.startswith(' '), ('LEADING_SPACE_MISMATCH', key)
    assert rvalue.endswith(' ') == evalue.endswith(' '), ('TRAILING_SPACE_MISMATCH', key)
    assert rvalue.count('\n') == evalue.count('\n'), ('NEWLINE_MISMATCH', key)

protected = {'Remote Connection', 'START', 'STOP', 'GET_SNAPSHOT', 'GET_EVENTS',
             'REMOTE_ACTION', 'OPEN_EXTERNAL', 'AuthPending', 'Ready'}
assert all(not key.startswith('TXT-') for key in ru)
owner_source = (root / 'Source/rc1-owner-gui.ps1').read_text(encoding='utf-8-sig')
for marker in ('Remote Connection', 'GET_SNAPSHOT', 'REMOTE_ACTION', 'AuthPending'):
    # These markers must remain source-side invariant and must not become semantic translation keys.
    assert marker in owner_source, ('PROTOCOL_MARKER_REMOVED', marker)
assert not protected.intersection(ru.keys()), 'MACHINE_VALUE_BECAME_RESOURCE_KEY'
print('PASS: %d resource keys in both languages' % len(ru))
print('PASS: %d referenced GUI/tray/dialog/journal/notification keys present in both catalogs' % len(usages))
print('PASS: format arguments, edge spaces, newlines, semantic key syntax')
print('PASS: invariant machine markers are not resource keys')
