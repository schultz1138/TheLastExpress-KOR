#!/usr/bin/env python3
"""
Build BG binary patch set from translated BMP files.
"""

import argparse
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

MEM_PAGE_SIZE = 2048
ENTRY_SIZE = 22
PATCH_MAGIC = b"BGPZ"
PAYLOAD_MAGIC = b"BGP2"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_hpf_index(path: Path):
    with path.open("rb") as f:
        head = f.read(4)
        if len(head) != 4:
            raise ValueError(f"{path}: missing entry count")
        count = struct.unpack("<I", head)[0]
        out = {}
        for i in range(count):
            item = f.read(ENTRY_SIZE)
            if len(item) != ENTRY_SIZE:
                raise ValueError(f"{path}: truncated index at {i}")
            name = item[:12].split(b"\x00", 1)[0].decode("ascii", "ignore").upper()
            off = struct.unpack("<I", item[12:16])[0]
            size_pages = struct.unpack("<H", item[16:18])[0]
            if name:
                out[name] = {
                    "offset": off,
                    "size_pages": size_pages,
                }
        return out


def build_entry_map(archives):
    name_map = {}
    for arc in archives:
        idx = read_hpf_index(arc)
        for name, meta in idx.items():
            if name not in name_map:
                name_map[name] = (arc, meta)
    return name_map


def read_entry_bytes(archive_path: Path, entry_meta):
    off = entry_meta["offset"] * MEM_PAGE_SIZE
    size = entry_meta["size_pages"] * MEM_PAGE_SIZE
    with archive_path.open("rb") as f:
        f.seek(off)
        data = f.read(size)
    if len(data) != size:
        raise ValueError(f"{archive_path}: truncated payload read ({len(data)} / {size})")
    return data


def read_bmp_24(path: Path):
    blob = path.read_bytes()
    if len(blob) < 54 or blob[:2] != b"BM":
        raise ValueError(f"not BMP: {path}")

    data_off = struct.unpack_from("<I", blob, 10)[0]
    dib_size = struct.unpack_from("<I", blob, 14)[0]
    if dib_size < 40:
        raise ValueError(f"{path}: unsupported DIB size")

    width = struct.unpack_from("<i", blob, 18)[0]
    height_raw = struct.unpack_from("<i", blob, 22)[0]
    planes = struct.unpack_from("<H", blob, 26)[0]
    bpp = struct.unpack_from("<H", blob, 28)[0]
    compression = struct.unpack_from("<I", blob, 30)[0]
    if width <= 0 or height_raw == 0:
        raise ValueError(f"{path}: invalid size")
    if planes != 1 or bpp != 24 or compression != 0:
        raise ValueError(f"{path}: only uncompressed 24-bit BMP supported")

    top_down = height_raw < 0
    height = abs(height_raw)
    row_size = ((width * 3 + 3) // 4) * 4
    needed = data_off + row_size * height
    if len(blob) < needed:
        raise ValueError(f"{path}: truncated pixel data")

    pixels = []
    for oy in range(height):
        sy = oy if top_down else (height - 1 - oy)
        row_off = data_off + sy * row_size
        for x in range(width):
            b, g, r = struct.unpack_from("<BBB", blob, row_off + x * 3)
            r5 = r >> 3
            g5 = g >> 3
            b5 = b >> 3
            pixels.append((r5 << 10) | (g5 << 5) | b5)
    return width, height, pixels


def read_rect_from_bg(bg_bytes: bytes):
    if len(bg_bytes) < 16:
        raise ValueError("BG too short for rect header")
    x, y, w, h = struct.unpack_from("<4I", bg_bytes, 0)
    return int(x), int(y), int(w), int(h)


def extract_rect_pixels(pixels, sw, sh, x, y, w, h):
    if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > sw or y + h > sh:
        raise ValueError(f"invalid rect ({x},{y} {w}x{h}) for source {sw}x{sh}")
    out = []
    for row in range(y, y + h):
        base = row * sw + x
        out.extend(pixels[base : base + w])
    return out


def encode_run_channel(values):
    out = bytearray()
    i = 0
    n = len(values)
    while i < n:
        value = values[i] & 0x1F
        run = 1
        while i + run < n and run < 4 and (values[i + run] & 0x1F) == value:
            run += 1
        out.append(((run - 1) << 5) | value)
        i += run
    return bytes(out)


def encode_target_bg_from_bmp(bmp_path: Path, rect):
    x, y, w, h = rect
    src_w, src_h, src_pixels = read_bmp_24(bmp_path)
    rect_pixels = extract_rect_pixels(src_pixels, src_w, src_h, x, y, w, h)

    r_vals = [((pix >> 10) & 0x1F) for pix in rect_pixels]
    b_vals = [(pix & 0x1F) for pix in rect_pixels]
    g_vals = [((pix >> 5) & 0x1F) for pix in rect_pixels]

    r_stream = encode_run_channel(r_vals)
    b_stream = encode_run_channel(b_vals)
    g_stream = encode_run_channel(g_vals)

    header = struct.pack(
        "<7I",
        x,
        y,
        w,
        h,
        len(r_stream),
        len(b_stream),
        len(g_stream),
    )
    return header + r_stream + b_stream + g_stream


def build_ops(base: bytes, target: bytes):
    if base == target:
        return []

    min_len = min(len(base), len(target))
    prefix = 0
    while prefix < min_len and base[prefix] == target[prefix]:
        prefix += 1

    max_suffix = min_len - prefix
    suffix = 0
    while suffix < max_suffix:
        if base[len(base) - 1 - suffix] != target[len(target) - 1 - suffix]:
            break
        suffix += 1

    base_mid_end = len(base) - suffix
    target_mid_end = len(target) - suffix

    return [
        {
            "offset": prefix,
            "base_len": base_mid_end - prefix,
            "data": target[prefix:target_mid_end],
        }
    ]


def write_patch(path: Path, target_size: int, ops):
    payload = bytearray()
    payload += PAYLOAD_MAGIC
    payload += struct.pack("<II", target_size, len(ops))
    for op in ops:
        data = op["data"]
        payload += struct.pack("<III", op["offset"], op["base_len"], len(data))
        payload += data

    packed = zlib.compress(bytes(payload), level=9)
    blob = PATCH_MAGIC + struct.pack("<I", len(payload)) + packed
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)


def default_archives(game_dir: Path):
    return [
        game_dir / "HD.HPF",
        game_dir / "CD1.HPF",
        game_dir / "CD2.HPF",
        game_dir / "CD3.HPF",
    ]


def collect_bmps(bmp_dir: Path):
    files = [p for p in bmp_dir.iterdir() if p.is_file() and p.suffix.lower() == ".bmp"]
    files.sort(key=lambda p: p.name.lower())
    return files


def main():
    parser = argparse.ArgumentParser(description="Build BG patchset from translated BMP files")
    parser.add_argument("--game-dir", type=Path, required=True, help="Game folder with HD/CD HPF")
    parser.add_argument("--bmp-dir", type=Path, required=True, help="Directory with translated BMP files")
    parser.add_argument("--out-dir", type=Path, required=True, help="Output patch directory")
    args = parser.parse_args()

    archives = default_archives(args.game_dir)
    for arc in archives:
        if not arc.exists():
            print(f"[ERROR] missing archive: {arc}")
            return 2
    if not args.bmp_dir.exists():
        print(f"[ERROR] bmp dir not found: {args.bmp_dir}")
        return 2

    bmp_files = collect_bmps(args.bmp_dir)
    if not bmp_files:
        print(f"[ERROR] no BMP files in: {args.bmp_dir}")
        return 2

    try:
        name_map = build_entry_map(archives)
    except Exception as exc:
        print(f"[ERROR] failed reading HPF index: {exc}")
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": 1,
        "patch_magic": PATCH_MAGIC.decode("ascii"),
        "payload_magic": PAYLOAD_MAGIC.decode("ascii"),
        "entries": [],
    }

    missing = []
    for bmp in bmp_files:
        bg_name = f"{bmp.stem.upper()}.BG"
        src = name_map.get(bg_name)
        if not src:
            missing.append(bg_name)
            continue

        arc, meta = src
        try:
            base = read_entry_bytes(arc, meta)
            rect = read_rect_from_bg(base)
            target = encode_target_bg_from_bmp(bmp, rect)
            ops = build_ops(base, target)
        except Exception as exc:
            print(f"[ERROR] {bmp.name}: {exc}")
            return 1

        patch_name = f"{bg_name}.BGP"
        patch_path = args.out_dir / patch_name
        write_patch(patch_path, len(target), ops)
        patch_size = patch_path.stat().st_size

        entry = {
            "name": bg_name,
            "source_archive": arc.name,
            "patch_file": patch_name,
            "base_size": len(base),
            "target_size": len(target),
            "patch_size": patch_size,
            "ops": len(ops),
            "base_sha256": sha256_hex(base),
            "target_sha256": sha256_hex(target),
        }
        manifest["entries"].append(entry)
        print(
            f"[OK] {bg_name}: ops={entry['ops']} base={entry['base_size']} "
            f"target={entry['target_size']} patch={entry['patch_size']}"
        )

    manifest["entries"].sort(key=lambda e: e["name"])
    manifest["entry_count"] = len(manifest["entries"])
    manifest_path = args.out_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    if missing:
        print(f"[WARN] missing template BG files: {len(missing)}")
        for name in missing[:30]:
            print(f"  - {name}")
        if len(missing) > 30:
            print(f"  ... {len(missing) - 30} more")
        return 1

    total_patch = sum(e["patch_size"] for e in manifest["entries"])
    print("")
    print("Patchset build complete")
    print(f"  Entries  : {manifest['entry_count']}")
    print(f"  Patch dir: {args.out_dir}")
    print(f"  Manifest : {manifest_path}")
    print(f"  Total    : {total_patch} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
