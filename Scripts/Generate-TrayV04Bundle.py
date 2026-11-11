"""Reproducibly package owner-approved tray 04 PNGs as one cached Win32 ICO bundle.

One-time offline developer script. No installer/runtime invocation, no network.
Requires Python 3.8+ standard library only (no Pillow dependency).
"""
from __future__ import annotations
import argparse
from pathlib import Path
import hashlib
import os
import struct
import zlib

STATES = ("offline", "connecting-a", "connecting-b", "auth-a", "auth-b", "ready", "working", "fault")
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
LEVELS = (45, 51, 57, 63, 69, 76, 82, 88, 94, 100)
SIGNATURE = b"\x89PNG\r\n\x1a\n"


def chunks(data: bytes):
    if not data.startswith(SIGNATURE):
        raise ValueError("TRAY_V04_NOT_PNG")
    position = len(SIGNATURE)
    while position < len(data):
        if position + 12 > len(data):
            raise ValueError("TRAY_V04_PNG_TRUNCATED")
        size = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        start = position + 8
        stop = start + size
        if stop + 4 > len(data):
            raise ValueError("TRAY_V04_PNG_CHUNK_BOUNDS")
        payload = data[start:stop]
        crc = struct.unpack_from(">I", data, stop)[0]
        if crc != zlib.crc32(kind + payload):
            raise ValueError("TRAY_V04_PNG_BAD_CRC")
        yield kind, payload
        position = stop + 4
        if kind == b"IEND":
            if position != len(data):
                raise ValueError("TRAY_V04_PNG_EXTRA_BYTES")
            return
    raise ValueError("TRAY_V04_PNG_NO_END")


def validate_png(data: bytes, expected_size: int) -> None:
    sequence = list(chunks(data))
    if not sequence or sequence[0][0] != b"IHDR" or len(sequence[0][1]) != 13:
        raise ValueError("TRAY_V04_PNG_HEADER")
    width, height, depth, color, compress, filtering, interlace = struct.unpack(">IIBBBBB", sequence[0][1])
    if (width, height, depth, color, compress, filtering, interlace) != (
        expected_size, expected_size, 8, 6, 0, 0, 0
    ):
        raise ValueError("TRAY_V04_EXPECT_RGBA8")


def decode_rgba(data: bytes, size: int) -> bytearray:
    validate_png(data, size)
    idat = b"".join(payload for kind, payload in chunks(data) if kind == b"IDAT")
    pixels = zlib.decompress(idat)
    stride = size * 4
    if len(pixels) != (stride + 1) * size:
        raise ValueError("TRAY_V04_BAD_DECOMPRESSED_SIZE")
    result = bytearray(stride * size)
    prev = bytearray(stride)
    pos = 0
    for y in range(size):
        kind = pixels[pos]
        pos += 1
        row = bytearray(pixels[pos:pos + stride])
        pos += stride
        for i in range(stride):
            a = row[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if kind == 1:
                row[i] = (row[i] + a) & 255
            elif kind == 2:
                row[i] = (row[i] + b) & 255
            elif kind == 3:
                row[i] = (row[i] + ((a + b) // 2)) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                predictor = a if pa <= pb and pa <= pc else b if pb <= pc else c
                row[i] = (row[i] + predictor) & 255
            elif kind != 0:
                raise ValueError("TRAY_V04_UNKNOWN_PNG_FILTER")
        result[y * stride:(y + 1) * stride] = row
        prev = row
    return result


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def encode_rgba(pixels: bytearray, size: int) -> bytes:
    stride = size * 4
    raw = b"".join(b"\0" + bytes(pixels[y * stride:(y + 1) * stride]) for y in range(size))
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (SIGNATURE + png_chunk(b"IHDR", header) +
            png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b""))


def pulse_center(source: bytes, size: int, opacity: int) -> bytes:
    if opacity == 100:
        return source
    pixels = decode_rgba(source, size)
    touched = 0
    for pos in range(0, len(pixels), 4):
        red, green, blue, alpha = pixels[pos:pos + 4]
        if alpha > 0 and blue > red + 5 and blue > green + 18:
            pixels[pos + 3] = round(alpha * opacity / 100)
            touched += 1
    if touched < 1:
        raise ValueError(f"TRAY_V04_MISSING_VIOLET_CENTER_{size}")
    return encode_rgba(pixels, size)


def blend_colors(first: bytes, second: bytes, size: int, percent: int) -> bytes:
    """Fade only the two approved colorized halves across the exact PNG geometry."""
    original = decode_rgba(first, size)
    other = decode_rgba(second, size)
    result = bytearray(len(original))
    ratio = percent / 100
    for pos in range(0, len(result), 4):
        # PNGs share accepted geometry and alpha. Premultiplied interpolation
        # avoids edge halos if antialiasing differs between colored phases.
        alpha_a, alpha_b = original[pos + 3], other[pos + 3]
        alpha = round(alpha_a * (1 - ratio) + alpha_b * ratio)
        result[pos + 3] = alpha
        for channel in range(3):
            numer = (original[pos + channel] * alpha_a * (1 - ratio)
                     + other[pos + channel] * alpha_b * ratio)
            result[pos + channel] = round(numer / alpha) if alpha else 0
    return encode_rgba(result, size)


def ico(pictures: list[bytes]) -> bytes:
    if len(pictures) != len(SIZES):
        raise ValueError("TRAY_V04_MISSING_SIZES")
    offsets = []
    position = 6 + 16 * len(SIZES)
    for size, png in zip(SIZES, pictures):
        validate_png(png, size)
        offsets.append(struct.pack("<BBBBHHII",
            0 if size == 256 else size, 0 if size == 256 else size,
            0, 0, 1, 32, len(png), position))
        position += len(png)
    return struct.pack("<HHH", 0, 1, len(SIZES)) + b"".join(offsets) + b"".join(pictures)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", action="store_true", required=True)
    parser.add_argument("--source", type=Path, default=None)
    opts = parser.parse_args()
    # WinPS 5.1 can corrupt Cyrillic argv when invoking native Python.
    # A Win32 wide-character environment value preserves the Desktop path.
    raw_source = opts.source or os.environ.get("RDC_TRAY_SOURCE")
    if raw_source is None:
        raise ValueError("TRAY_V04_APPROVED_SOURCE_ENV_MISSING")
    source = Path(raw_source).resolve(strict=True)
    if source.is_symlink() or source.name != "PNG" or source.parent.name != "Трей":
        raise ValueError("TRAY_V04_APPROVED_SOURCE_PATH")
    expected = {f"{state}-{size}.png" for state in STATES for size in SIZES}
    actual = {f.name for f in source.iterdir()}
    if actual != expected:
        raise ValueError(f"TRAY_V04_WRONG_SET expected={len(expected)} actual={len(actual)}")
    pngs: dict[tuple[str, int], bytes] = {}
    for state in STATES:
        for size in SIZES:
            path = source / f"{state}-{size}.png"
            if path.is_symlink():
                raise ValueError("TRAY_V04_SYMLINK_DENIED")
            data = path.read_bytes()
            validate_png(data, size)
            pngs[state, size] = data
    entries: dict[str, bytes] = {}
    for state in STATES:
        if state != "working":
            entries[state] = ico([pngs[state, size] for size in SIZES])
    for index, percent in enumerate(LEVELS):
        entries[f"work-{index:02d}"] = ico([
            pulse_center(pngs["working", size], size, percent) for size in SIZES
        ])
    # The HTML-approved CSS fades colors over 160ms at 40%-50% and
    # 90%-100% of its 1.6s cycle. Cache 25/50/75% intermediate frames;
    # the WinForms 40ms timer selects the exact 160ms transition.
    for state in ("connecting", "auth"):
        for direction, first, second in (
            ("ab", f"{state}-a", f"{state}-b"),
            ("ba", f"{state}-b", f"{state}-a"),
        ):
            for percent in (25, 50, 75):
                entries[f"{state}-{direction}-{percent:02d}"] = ico([
                    blend_colors(pngs[first, size], pngs[second, size], size, percent)
                    for size in SIZES
                ])
    if len(entries) != 29:
        raise ValueError("TRAY_V04_BUNDLE_WRONG_COUNT")
    data = bytearray(b"RDCTRAY4" + struct.pack("<HB", 1, len(entries)))
    for name, binary in entries.items():
        encoded = name.encode("ascii")
        if not (1 <= len(encoded) <= 40 and 100 <= len(binary) <= 1_048_576):
            raise ValueError("TRAY_V04_BUNDLE_ENTRY_BOUNDARY")
        data += struct.pack("<B", len(encoded)) + encoded + struct.pack("<I", len(binary)) + binary
    if len(data) >= 4_194_304:
        raise ValueError("TRAY_V04_BUNDLE_TOO_BIG")
    destination = Path(__file__).resolve().parent.parent / "Source" / "RdcTrayV04.bin"
    with destination.open("xb") as output:
        output.write(data)
    print("TRAY_V04_FILE=" + str(destination))
    print("TRAY_V04_BYTES=" + str(len(data)))
    print("TRAY_V04_FRAMES=" + str(len(entries)))
    print("TRAY_V04_SHA256=" + hashlib.sha256(data).hexdigest().upper())


if __name__ == "__main__":
    main()
