#!/usr/bin/env python3
"""Read-only, source-aware classification of inventory candidates excluded from the first Excel shortlist.

The source of truth remains STRING_INVENTORY.csv. Do not rewrite it or the XLSX.
Every excluded REVIEW candidate must be explicitly mapped; a new ID fails closed.
"""
import csv
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXCEL_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
M = "{" + EXCEL_NS + "}"
DECISIONS = {}

def assign(category, scope, action, rationale, ids):
    for ident in ids.split():
        if ident in DECISIONS:
            raise ValueError("DUPLICATE_MANUAL_CLASSIFICATION " + ident)
        DECISIONS[ident] = (category, scope, action, rationale)

# Owner GUI: these exact English strings reach the *sanitized fallback banner*.
# Some also serve as local comparison values: translate only in the output projection.
assign("USER_VISIBLE", "OWNER_GUI_FALLBACK", "ADD_DISPLAY_MAPPING_NOT_SOURCE_REPLACE",
       "Owner GUI fallback startup block renders this value/label; keep existing switch and Host-state comparisons unchanged.",
"""TXT-429382fa05feea35 TXT-5abd528e5bab519c TXT-5e699b9242d03f6d TXT-6856b9d80a9a8e6e
TXT-7ca7ebc097eed835 TXT-807bf466b8b800fd TXT-834846fa563a26f2 TXT-b3fb98321229015a
TXT-b5a0d2c800804a38 TXT-d765fab2437b3cbe TXT-e4488e03b7c8e6d8 TXT-e7bdc4024d529123
TXT-ea8c34976eb286c1""")

# The text is visible but the exact 'Remote Connection' marker is required by StyleStartupBanner.
assign("PROTOCOL_LOCKED", "OWNER_GUI_RENDERER_ANCHOR", "PRESERVE_EXACT_AND_ADD_SEPARATE_CAPTION",
       "Literal is a banner renderer/style parser anchor shared with the original Remote output; do not replace in place.",
"""TXT-fa71a24ba7fc4993""")

assign("PROTOCOL_LOCKED", "OWNER_GUI_EVENT_GRAMMAR", "PRESERVE_EXACT",
       "Literal participates in event parsing, Host status mapping, IPC response matching or guarded semantic branches.",
"""TXT-279939a5a2b9d645 TXT-6245958c0afde0af TXT-67436c52c3c66d0e
TXT-748d6f3ff45bd2af TXT-68dfb889c9dcd4cd TXT-91540c9f7a2afeaa TXT-98db6bff68ea7845
TXT-9b7578b29ddffca6 TXT-a2f2a21b9e88123c TXT-a52368deab9adfd1
TXT-a9e232ab66db616c TXT-ac2f841385423fce TXT-b2dcd80ef98c86ec
TXT-badb8a736f1cb1b4 TXT-bb089a717ddd0e37 TXT-bbf4feb71aae038c
TXT-e2e81e56d7f6e7e4 TXT-fb24b5a29b000b01""")

assign("NOT_APPLICABLE", "OWNER_GUI_INTERNAL", "PRESERVE_INTERNAL",
       "Internal installation path, environment folder or state property name, not a display caption.",
"""TXT-571ede9e50daa171 TXT-8d71efeeb094b8af TXT-9aedc586dc3f1dc4""")

# Tray / Host. A versioned tray title is display copy; app brand/caption remains unchanged.
assign("USER_VISIBLE", "OWNER_TRAY", "ADD_DISPLAY_KEY_KEEP_VERSION",
       "NotifyIcon or dialog caption can be seen by users; retain product name and review version token.",
"""TXT-39a4e58e1358bd25 TXT-419e728099a2c459 TXT-6bf764b23fa810e3""")
assign("NOT_APPLICABLE", "FAKE_ONLY_FIXTURE", "KEEP_FAKE_FIXTURE",
       "Fake-only tray title belongs to isolated candidate tests, not public runtime UI.",
"""TXT-2c84ffd48bd44dfa""")
assign("PROTOCOL_LOCKED", "HOST_INPUT_AND_IPC", "PRESERVE_EXACT",
       "Fixed START/STOP command, identity JSON field, vendor startup allowlist or regular expression.",
"""TXT-18b7ec030243dcb2 TXT-249d8e40e08c2b14 TXT-3701293c361a9639
TXT-76ad1bcc7419b698 TXT-8aa12e1b019c70b1 TXT-b12728b327db1ebe
TXT-c1a189ae74767511 TXT-c9cf5f481442bed8 TXT-faf6ea93ad26f933""")

# Legacy shared GUI, including former product paths reused by Owner GUI.
assign("USER_VISIBLE", "SHARED_LEGACY_GUI", "REVIEW_REACHABILITY_AND_ADD_DISPLAY_KEY",
       "User-facing header/version/exception message; determine whether current 1.6 Owner or only legacy startup displays it.",
"""TXT-060842c54b3363a0 TXT-7c196ca1443acddf TXT-aaaea4e58baef7ee""")
assign("USER_VISIBLE", "SHARED_LEGACY_GUI_BRAND", "KEEP_BRAND_LITERALLY",
       "Product/window brand text is visible but must not be translated.",
"""TXT-517e2020cc4b8788""")
assign("PROTOCOL_LOCKED", "SHARED_LEGACY_GUI_RENDERER", "PRESERVE_EXACT",
       "Exact Remote Connection banner anchor used by StyleStartupBanner (not just an ornamental label).",
"""TXT-b7ec1868efc78bec""")
assign("PROTOCOL_LOCKED", "SHARED_LEGACY_GUI_RUNTIME", "PRESERVE_EXACT",
       "Shell commandline process matching string, platform/native symbol or fixed output extension.",
"""TXT-d84629e33e0bdf69 TXT-76d55bd07d2c08e6 TXT-c2126501b8eff154 TXT-f8178c08647e59c3 TXT-089c3cae1fc156aa""")
assign("PROTOCOL_LOCKED", "WINFORMS_CONTROL_NAME", "PRESERVE_EXACT",
       "Named accessibility/control selector used by WinForms/test automation, not the UI caption.",
"""TXT-38ea710eec24c485 TXT-4760310b4ce191c3 TXT-8e74a29eab721a28
TXT-9c87d93ab5ec4c1b TXT-a3a9f38231f035b6 TXT-bf73c7b5a9569e9c
TXT-f559f09c957fde68""")
assign("NOT_APPLICABLE", "GUI_SELF_TEST_ONLY", "PRESERVE_TEST_FIXTURE",
       "Literal appears only in self-test assertions, probe data or error messages, not production UI.",
"""TXT-0226ddf32890a5f9 TXT-2a96e9c5d29ad1f1 TXT-31d59d35a17f2859
TXT-439221aaf3df2547 TXT-5581ebc5600740a8 TXT-7ab6df675d88c16d TXT-950cc519ab86bc1b
TXT-9d899c30969ca295 TXT-bfc0e8e128a60db8 TXT-d664d55e8d82a077
TXT-d9c8918b46cd3d3e TXT-ef9e793bb6b20e7a TXT-fc3c221fb2469c1d
TXT-ff5577377046f174""")
assign("NOT_APPLICABLE", "GUI_PREVIEW_OR_SELFTEST", "DEFER_NONPRODUCT_SCREEN",
       "Preview/SelfTest display copy, not in a normal Owner GUI launch.",
"""TXT-120eb55da84c8d7d TXT-6d6d7fc5313baafc TXT-78373202dc04bf02
TXT-8c9a597a48f41416 TXT-a9298e57a4cf537c TXT-c4213f054a64e0b8""")

# Historical Setup/Launcher text is real user-facing copy, not protocol. Must be
# localized if that path is still included in release distribution/migration.
assign("USER_VISIBLE", "LEGACY_SETUP_LAUNCHER", "REVIEW_RELEASE_PATH_AND_LOCALIZE",
       "MessageBox/installer prompt is user-facing in historical Setup/Launcher; verify 1.6 migration reachability.",
"""TXT-073d567b54b0901d TXT-0a44acacbf4417a0 TXT-2bfbc0c3a2e32b4c
TXT-7f35170ae77158cc TXT-8374926e98ca7421 TXT-8535162e1732b29a
TXT-c436bbc93050a1c8 TXT-d4022f82bc114143 TXT-f7ac960510e02b18""")

# RC1 side-by-side pilot installer is visible only when that private installer
# is run, not a public release 1.6 installer UI.
assign("NOT_APPLICABLE", "RC1_PILOT_INSTALLER", "DEFER_TO_PILOT_SCOPE",
       "Real MessageBox in private RC1 Pilot setup, but not public release UI; keep exact behavior unless pilot localizes.",
"""TXT-0dae426da42be305 TXT-16219d0ae50f197b TXT-30badb76c062d0cd
TXT-540bedb293c37432 TXT-544d783f45d9c78f TXT-63a0f252116138fa
TXT-77de028ac058a71a TXT-a8cc19ec417daa1e TXT-b7f6b15bc2d43277
TXT-c441577ab87fc335 TXT-ca5463617e076dc3 TXT-d9c10f4d05ea3139
TXT-fdc24c0930cb10e7 TXT-fde67c62c11f524e""")

assign("PROTOCOL_LOCKED", "RELEASE_INSTALLER", "PRESERVE_IDENTIFIER",
       "Control Name or refusal reason constant, not rendered text.",
"""TXT-0e4dd759beddc612 TXT-2eb1019959b33b6f TXT-9f40a6f32593dc6b
TXT-9f8301c7d5abff78 TXT-40283ea752235b63 TXT-db55e582a9ee2087
TXT-e63396a7a443d1ec""")
assign("NOT_APPLICABLE", "RELEASE_INSTALLER_LAYOUT", "KEEP_FONT_OR_INSTALL_DIRECTORY",
       "Font family or on-disk installation directory component; not a label.",
"""TXT-270d0e0b3a1ce19f TXT-521f3414ede71c82""")


def workbook_ids(path):
    with zipfile.ZipFile(path) as z:
        if z.testzip():
            raise ValueError("WORKBOOK_ZIP_BAD")
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            root = ET.fromstring(z.read("xl/sharedStrings.xml"))
            shared = ["".join(t.text or "" for t in x.iter(M + "t")) for x in root.findall(M + "si")]
        relation_root = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        rels = {item.attrib["Id"]: item.attrib["Target"] for item in relation_root}
        book = ET.fromstring(z.read("xl/workbook.xml"))
        sheet = next(x for x in book.find(M + "sheets") if x.attrib.get("name") == "Тексты")
        rid = sheet.attrib["{" + R_NS + "}id"]
        target = rels[rid].lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        root = ET.fromstring(z.read(target))
        output = set()
        for cell in root.iter(M + "c"):
            if not re.fullmatch(r"G(?:[6-9]|[1-9]\d{1,2})", cell.attrib.get("r", "")):
                continue
            value = cell.find(M + "v")
            if value is None:
                continue
            text = shared[int(value.text)] if cell.attrib.get("t") == "s" else value.text
            output.add(text)
        return output


def main():
    with (HERE / "STRING_INVENTORY.csv").open("r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    original = workbook_ids(HERE / "RDC_Relay_UI_Texts.xlsx")
    selected = [x for x in rows if x["ReviewStatus"] in {"REVIEW_TRANSLATION", "REVIEW_ENGLISH_UI"} and x["CandidateId"] not in original]
    selected_ids = {x["CandidateId"] for x in selected}
    if len(rows) != 2841 or len(original) != 360 or len(selected) != 117:
        raise ValueError(f"SCOPE_CHANGED inventory={len(rows)} workbook={len(original)} excluded={len(selected)}")
    missing = selected_ids - DECISIONS.keys()
    excess = DECISIONS.keys() - selected_ids
    if missing or excess:
        print("UNCLASSIFIED", len(missing), " ".join(sorted(missing)))
        print("OUT_OF_SCOPE_MAPPINGS", len(excess), " ".join(sorted(excess)))
        sys.exit(2)
    columns = ["CandidateId", "Area", "Source", "Lines", "ReviewStatus", "Literal", "Classification",
               "Reachability", "Action", "Rationale"]
    output = HERE / "REMAINING_117_CLASSIFICATION.csv"
    with output.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for item in sorted(selected, key=lambda v: (v["Area"], v["Source"], int(v["Lines"].split(";")[0]))):
            classification, scope, action, rationale = DECISIONS[item["CandidateId"]]
            writer.writerow({**{key: item[key] for key in ("CandidateId", "Area", "Source", "Lines", "ReviewStatus", "Literal")},
                             "Classification": classification, "Reachability": scope, "Action": action, "Rationale": rationale})
    summary = Counter(DECISIONS[i][0] for i in selected_ids)
    print("PASS", len(selected), "exclusively classified review candidates; unchanged original index/workbook")
    print("COUNTS", dict(sorted(summary.items())))
    for area in sorted({x["Area"] for x in selected}):
        print(area, dict(Counter(DECISIONS[x["CandidateId"]][0] for x in selected if x["Area"] == area)))
    print("SAVED", output)


if __name__ == "__main__":
    main()
