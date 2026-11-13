"""Compile the owner-approved tray v04-final 49-frame ICO kit into a cached Host bundle.

Offline, deterministic, standard library only. The canonical sources and manifest
are committed under Assets/TrayV04Final. This tool never touches the live tray,
installed application, network, process state, or user's desktop resources.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "Assets" / "TrayV04Final"
DEST = ROOT / "Source" / "RdcTrayV04.bin"
MANIFEST_SHA256 = "27DA99E8E1F8AFC9373AE28345EBB15CC12A90FB503EE7330F5CFF83BF2A733A"
SIZES = (16, 20, 24, 32, 40, 48, 64)
NAMES = (
    "disconnected", "connecting-a", "connecting-b",
    "authorization-a", "authorization-b", "ready",
    "working-static", "connection-error",
    "connecting-mix-25", "connecting-mix-50", "connecting-mix-75",
    "authorization-mix-25", "authorization-mix-50", "authorization-mix-75",
) + tuple(f"working-{i:02d}" for i in range(1, 36))
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def verify_png(png: bytes, size: int) -> None:
    if not png.startswith(PNG_SIGNATURE):
        raise ValueError("TRAY_FINAL_PNG_SIGNATURE")
    offset = 8
    ihdr = False
    ended = False
    while offset + 12 <= len(png):
        length = struct.unpack_from(">I", png, offset)[0]
        end = offset + 12 + length
        if end > len(png):
            raise ValueError("TRAY_FINAL_PNG_LENGTH")
        kind = png[offset + 4:offset + 8]
        data = png[offset + 8:offset + 8 + length]
        expected = struct.unpack_from(">I", png, offset + 8 + length)[0]
        if zlib.crc32(kind + data) != expected:
            raise ValueError("TRAY_FINAL_PNG_CRC")
        if kind == b"IHDR":
            if ihdr or len(data) != 13:
                raise ValueError("TRAY_FINAL_IHDR")
            w, h, depth, color, comp, filtering, interlace = struct.unpack(">IIBBBBB", data)
            if (w, h, depth, color, comp, filtering, interlace) != (
                size, size, 8, 6, 0, 0, 0
            ):
                raise ValueError("TRAY_FINAL_PNG_FORMAT")
            ihdr = True
        offset = end
        if kind == b"IEND":
            ended = True
            break
    if not ihdr or not ended or offset != len(png):
        raise ValueError("TRAY_FINAL_PNG_INCOMPLETE")


def verify_ico(data: bytes) -> None:
    if len(data) < 6 + 16 * len(SIZES):
        raise ValueError("TRAY_FINAL_ICO_SHORT")
    reserved, kind, count = struct.unpack_from("<HHH", data)
    if (reserved, kind, count) != (0, 1, len(SIZES)):
        raise ValueError("TRAY_FINAL_ICO_HEADER")
    last = 6 + 16 * len(SIZES)
    for i, size in enumerate(SIZES):
        width, height, colors, unused, planes, depth, length, offset = struct.unpack_from(
            "<BBBBHHII", data, 6 + 16 * i
        )
        if (width, height, colors, unused, planes, depth) != (
            size, size, 0, 0, 1, 32
        ):
            raise ValueError("TRAY_FINAL_ICO_FRAME")
        if offset != last or length < 50 or offset + length > len(data):
            raise ValueError("TRAY_FINAL_ICO_FRAME_BOUNDS")
        verify_png(data[offset:offset + length], size)
        last = offset + length
    if last != len(data):
        raise ValueError("TRAY_FINAL_ICO_EXTRA_BYTES")


def build_bundle() -> bytes:
    manifest_file = KIT / "manifest.json"
    if manifest_file.is_symlink() or sha256(manifest_file.read_bytes()) != MANIFEST_SHA256:
        raise ValueError("TRAY_FINAL_MANIFEST_NOT_APPROVED")
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    if manifest.get("version") != "04-final" or len(manifest.get("assets", [])) != 49:
        raise ValueError("TRAY_FINAL_MANIFEST_FORMAT")
    assets = {a["name"]: a for a in manifest["assets"]}
    if len(assets) != 49 or set(assets) != set(NAMES):
        raise ValueError("TRAY_FINAL_MANIFEST_ASSETS")
    ico_directory = KIT / "ICO"
    if ico_directory.is_symlink() or {
        p.name for p in ico_directory.iterdir()
    } != {name + ".ico" for name in NAMES}:
        raise ValueError("TRAY_FINAL_ICO_DIRECTORY")
    for key, ms in (("connecting", 1600), ("authorization", 1600), ("working", 1800)):
        a = manifest["animations"][key]
        if a["periodMs"] != ms or sum(s["durationMs"] for s in a["sequence"]) != ms:
            raise ValueError("TRAY_FINAL_ANIMATION_DURATION_" + key)
    if (
        manifest["animations"]["connecting"]["staticFallback"] != "ICO/connecting-a.ico"
        or manifest["animations"]["authorization"]["staticFallback"] != "ICO/authorization-a.ico"
        or manifest["animations"]["working"]["staticFallback"] != "ICO/working-static.ico"
    ):
        raise ValueError("TRAY_FINAL_STATIC_FALLBACK")
    expected_connect = (
        ["connecting-a"] + [f"connecting-mix-{i}" for i in (25, 50, 75)]
        + ["connecting-b"] + [f"connecting-mix-{i}" for i in (75, 50, 25)]
    )
    expected_auth = [s.replace("connecting", "authorization") for s in expected_connect]
    expected_work = ["working-static"] + [f"working-{i:02d}" for i in range(1, 36)]
    for key, sequence, duration in (
        ("connecting", expected_connect, (680, 40, 40, 40, 680, 40, 40, 40)),
        ("authorization", expected_auth, (680, 40, 40, 40, 680, 40, 40, 40)),
        ("working", expected_work, (50,) * 36),
    ):
        rows = manifest["animations"][key]["sequence"]
        if [p["file"] for p in rows] != ["ICO/" + n + ".ico" for n in sequence] or tuple(
            p["durationMs"] for p in rows
        ) != duration:
            raise ValueError("TRAY_FINAL_SEQUENCE_MISMATCH_" + key)

    result = bytearray(b"RDCTRAY4" + struct.pack("<HB", 1, len(NAMES)))
    for name in NAMES:
        entry = assets[name]
        if entry.get("ico") != "ICO/" + name + ".ico":
            raise ValueError("TRAY_FINAL_ASSET_PATH")
        path = ico_directory / (name + ".ico")
        if path.is_symlink() or not path.is_file():
            raise ValueError("TRAY_FINAL_ICO_LINK_OR_MISSING")
        binary = path.read_bytes()
        if sha256(binary) != entry["sha256"].upper():
            raise ValueError("TRAY_FINAL_ASSET_SHA_" + name)
        verify_ico(binary)
        encoded = name.encode("ascii")
        result.extend(struct.pack("<B", len(encoded)))
        result.extend(encoded)
        result.extend(struct.pack("<I", len(binary)))
        result.extend(binary)
    if len(result) >= 4_194_304:
        raise ValueError("TRAY_FINAL_BUNDLE_TOO_BIG")
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--build", action="store_true")
    action.add_argument("--verify", action="store_true")
    opts = parser.parse_args()
    data = build_bundle()
    if DEST.is_symlink():
        raise ValueError("TRAY_FINAL_DEST_SYMLINK")
    if opts.verify:
        if not DEST.is_file() or DEST.read_bytes() != data:
            raise ValueError("TRAY_FINAL_BUILD_NOT_REPRODUCIBLE")
    else:
        DEST.write_bytes(data)
    print("TRAY_V04_FINAL_FRAMES=" + str(len(NAMES)))
    print("TRAY_V04_FINAL_BYTES=" + str(len(data)))
    print("TRAY_V04_FINAL_SHA256=" + sha256(data))
    print("TRAY_V04_FINAL_" + ("VERIFY" if opts.verify else "BUILD") + "=PASS")


if __name__ == "__main__":
    main()
