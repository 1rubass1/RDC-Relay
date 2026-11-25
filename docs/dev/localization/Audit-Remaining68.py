#!/usr/bin/env python3
"""Reconcile 68 historically unwired keys against new source bindings (read only except generated indexes)."""
import csv
import io
import subprocess
from collections import Counter
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE="c750f6e"
SOURCE="docs/dev/localization/RESOURCE_KEY_INVENTORY.csv"
def git(*args):
 p=subprocess.run(["git","-C",str(ROOT),*args],capture_output=True)
 if p.returncode:raise RuntimeError("GIT_AUDIT_ERROR "+p.stderr.decode("utf-8","replace")[:200])
 return p.stdout
baseline=list(csv.DictReader(io.StringIO(git("show",BASE+":"+SOURCE).decode("utf-8-sig"))))
with (HERE/"RESOURCE_KEY_INVENTORY.csv").open(encoding="utf-8-sig",newline="") as f:
 current=list(csv.DictReader(f))
original=[x for x in baseline if x["BindingStatus"]=="UNWIRED_PREVIEW"]
assert len(original)==68,("BASELINE_SCOPE_CHANGED",len(original))
idx={x["SemanticKey"]:x for x in current}
assert len(idx)==len(current) and len(current)>=len(baseline)
assert {x["SemanticKey"] for x in baseline}.issubset(set(idx))
decisions=[]
for item in original:
 key=item["SemanticKey"];now=idx[key]
 if key.startswith("installer.maintenance.") or key.startswith("installer.path."):
  group="PUBLIC_RELEASE_SETUP"
  disposition="BOUND_SETUP_DISPLAY_ONLY"
  reason="Native future-release dialog uses embedded standalone RU/EN catalog; no Setup transaction wired"
 elif key.startswith("installer.legacy."):
  group="LEGACY_SETUP_LAUNCHER"
  disposition="DEFER_LEGACY_INSTALLER_REACHABILITY"
  reason="User-facing legacy Setup/Launcher message; confirm active release/migration path"
 elif key.startswith("legacy.gui."):
  group="LEGACY_15_GUI"
  disposition="DEFER_LEGACY_GUI"
  reason="Historical 1.5 GUI and npx messages, not Owner GUI 1.6"
 elif key=="owner.fallback.status.connected":
  group="OWNER_FALLBACK"
  disposition="INTENTIONAL_DUPLICATE"
  reason="Connected maps to Online in the fallback; owner.fallback.status.online is the display key"
 elif key.startswith("owner.fallback."):
  group="OWNER_FALLBACK"
  disposition="BOUND_DISPLAY_ONLY"
  reason="Display-only Owner fallback; renderer marker Remote Connection remains literal"
 elif key.startswith("tray."):
  group="OWNER_TRAY"
  disposition="BOUND_DISPLAY_ONLY"
  reason="Translated NotifyIcon status or fallback title, state/animation stays invariant"
 elif key=="journal.owner.empty":
  group="OWNER_JOURNAL"
  disposition="BOUND_DISPLAY_ONLY"
  reason="Owner-only empty journal uses locale key; 1.5 legacy output unchanged"
 else:raise RuntimeError("UNCLASSIFIED_KEY "+key)
 if disposition in ("BOUND_DISPLAY_ONLY","BOUND_SETUP_DISPLAY_ONLY"):
  assert now["BindingStatus"]=="SOURCE_REFERENCED" and now["SourceRefs"],("EXPECTED_BOUND",key)
 else:
  assert now["BindingStatus"]=="UNWIRED_PREVIEW",("EXPECTED_UNBOUND",key)
 decisions.append({"SemanticKey":key,"Group":group,"Decision":disposition,
  "BaselineStatus":item["BindingStatus"],"CurrentStatus":now["BindingStatus"],
  "SourceRefs":now["SourceRefs"],"Reason":reason})
counts=Counter(x["Decision"] for x in decisions)
expected={
 "BOUND_DISPLAY_ONLY":30,
 "BOUND_SETUP_DISPLAY_ONLY":28,
 "DEFER_LEGACY_INSTALLER_REACHABILITY":7,
 "DEFER_LEGACY_GUI":2,
 "INTENTIONAL_DUPLICATE":1
}
assert counts==expected,counts
with (HERE/"REMAINING_68_DECISIONS.csv").open("w",encoding="utf-8-sig",newline="") as f:
 writer=csv.DictWriter(f,fieldnames=list(decisions[0]))
 writer.writeheader();writer.writerows(decisions)
lines=[
 "# RDC Relay 1.6.0 — detailed review of 68 previously unwired locale keys",
 "",
 "Historical baseline: source-key inventory at commit c750f6e; current binding evidence from RESOURCE_KEY_INVENTORY.csv.",
 "",
 "## Classification",
 "",
 "| Category | Count | Decision |",
 "| --- | ---: | --- |",
 "| Owner fallback connection banner | 19 connected, 1 duplicate | Use localized display text after invariant renderer anchor; Connected is already shown as Online |",
 "| Owner tray | 10 connected | Eight semantic tooltip statuses/prefixes and two asset-fallback titles; no icon/animation changes |",
 "| Empty Owner journal | 1 connected | Separate Owner and legacy behavior |",
 "| Release Setup maintenance/path dialogs | 28 bound in prepared UI | Standalone compiled catalog, no installed files needed. Actual transaction still unconnected. |",
 "| Legacy Setup/Launcher | 7 deferred | First establish path reachability in 1.6 and migration |",
 "| Legacy GUI 1.5.x | 2 deferred | Outside Owner GUI 1.6 runtime; separate compatibility stage |",
 "| **Total** | **68** | **58 source-bound (including 28 preparatory Setup), 10 deferred/redundant** |",
 "",
 "## Installer scope",
 "",
 "The two prepared release dialogs now use RdcReleaseUiLanguage and an independently compiled catalog generated from Source/lang. The generator embeds all 35 RU/EN installer keys, of which 28 are bound in release maintenance/path UI. No runtime Source/lang dependency. The 7 legacy Setup/Launcher entries are embedded as staging data but NOT wired into stable 1.5.x Setup, so no destructive installation behavior changes. Public 1.6 Setup, Upgrade/Repair/Uninstall, packaging, rollback and user-facing transaction entrypoints remain INCOMPLETE.",
 "",
 "## Protected behavior",
 "",
 "- The exact Remote Connection marker is not translated, because StyleStartupBanner uses it to find the artwork. When Host supplies its own original startup header, the vendor text remains byte-identical.",
 "- The Connected resource key is an intentional unused duplicate: the code maps validated Ready/Connected to the Online resource key, matching its previous UI. It is retained for editorial traceability.",
 "- NotifyIcon statuses are translated only from validated Host state; no icon frame changes, no animation phase reset, no new Remote action.",
 "- Owner empty-journal text uses its dictionary only in Owner mode, leaving the historical GUI unchanged.",
 "",
 "## Evidence and follow-up",
 "",
 "- Current source/string and resource inventories are reproducible; all 68 keys have explicit rows in REMAINING_68_DECISIONS.csv.",
 "- Native tray tests exercise the translated English and Russian tooltip with the real 49-icon bundle and safe semantic transitions.",
 "- The artificial fallback uses 19 new keys, including the labels of previously validated and sanitized identity values, but is not the vendor startup header.",
 "- Existing Windows Sandbox is a previous immutable revision; it will not hot-reload these changes. New screenshots require a fresh disposable session.",
 "",
 "Prepared release dialog localization is now source-integrated for 28 keys; public installer transaction, rollback and full Remote integration still require separate approval. No release GO.",
 ""
]
(HERE/"REMAINING_68_AUDIT.md").write_text("\n".join(lines),encoding="utf-8")
print("PASS_REMAINING_68_CLASSIFIED="+str(len(decisions)))
for name,count in sorted(counts.items()):print(name,count)
print("CURRENT_UNWIRED="+str(sum(x["BindingStatus"]=="UNWIRED_PREVIEW" for x in current)))
