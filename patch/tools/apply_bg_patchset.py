#!/usr/bin/env python3
"""
Apply BG binary patch set using user-local HPF archives as base input.
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


def parse_patch(blob: bytes):
    if len(blob) < 8 or blob[:4] != PATCH_MAGIC:
        raise ValueError("invalid patch magic")
    payload_size = struct.unpack_from("<I", blob, 4)[0]
    payload = zlib.decompress(blob[8:])
    if len(payload) != payload_size:
        raise ValueError("payload size mismatch")

    if len(payload) < 12 or payload[:4] != PAYLOAD_MAGIC:
        raise ValueError("invalid payload magic")

    target_size, op_count = struct.unpack_from("<II", payload, 4)
    pos = 12
    ops = []
    for _ in range(op_count):
        if pos + 12 > len(payload):
            raise ValueError("truncated operation header")
        offset, base_len, data_len = struct.unpack_from("<III", payload, pos)
        pos += 12
        if pos + data_len > len(payload):
            raise ValueError("truncated operation data")
        data = payload[pos : pos + data_len]
        pos += data_len
        ops.append((offset, base_len, data))

    if pos != len(payload):
        raise ValueError("unexpected trailing payload bytes")
    return target_size, ops


def apply_ops(base: bytes, target_size: int, ops):
    out = bytearray()
    cursor = 0
    for offset, base_len, data in ops:
        if offset < cursor or offset > len(base):
            raise ValueError(f"invalid op offset: {offset} (cursor={cursor}, base={len(base)})")
        out.extend(base[cursor:offset])
        out.extend(data)
        cursor = offset + base_len
        if cursor > len(base):
            raise ValueError(f"invalid op range: {offset}+{base_len} > {len(base)}")

    out.extend(base[cursor:])
    if len(out) != target_size:
        raise ValueError(f"target size mismatch: built={len(out)} expected={target_size}")
    return bytes(out)


def resolve_archive_path(game_dir: Path, filename: str) -> Path:
    candidates = [
        game_dir / filename,
        game_dir / "data" / filename,
        game_dir / "Data" / filename,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def default_archives(game_dir: Path):
    return [
        resolve_archive_path(game_dir, "HD.HPF"),
        resolve_archive_path(game_dir, "CD1.HPF"),
        resolve_archive_path(game_dir, "CD2.HPF"),
        resolve_archive_path(game_dir, "CD3.HPF"),
    ]


def main():
    parser = argparse.ArgumentParser(description="Apply BG patchset to user-local HPF data")
    parser.add_argument(
        "--game-dir",
        type=Path,
        required=True,
        help="Game folder with HD.HPF and CD1~3.HPF (root or data/Data)",
    )
    parser.add_argument("--patch-dir", type=Path, required=True, help="Patchset directory (manifest + *.BGP)")
    parser.add_argument("--out-dir", type=Path, required=True, help="Directory to write patched BG files")
    parser.add_argument(
        "--strict-hash",
        action="store_true",
        help="Fail if base/target hash in manifest does not match",
    )
    args = parser.parse_args()

    archives = default_archives(args.game_dir)
    for arc in archives:
        if not arc.exists():
            print(f"[ERROR] missing archive (searched root/data/Data): {arc}")
            return 2

    manifest_path = args.patch_dir / "manifest.json"
    if not manifest_path.exists():
        print(f"[ERROR] patch manifest not found: {manifest_path}")
        return 2

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        entries = manifest.get("entries", [])
    except Exception as exc:
        print(f"[ERROR] invalid manifest: {exc}")
        return 2

    if not entries:
        print("[ERROR] manifest has no entries")
        return 2

    try:
        name_map = build_entry_map(archives)
    except Exception as exc:
        print(f"[ERROR] failed reading HPF index: {exc}")
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        name = str(entry.get("name", "")).upper()
        patch_file = entry.get("patch_file")
        if not name or not patch_file:
            print("[ERROR] malformed manifest entry")
            return 1

        src = name_map.get(name)
        if not src:
            print(f"[ERROR] base BG missing in archives: {name}")
            return 1

        arc, meta = src
        try:
            base = read_entry_bytes(arc, meta)
        except Exception as exc:
            print(f"[ERROR] failed reading base {name}: {exc}")
            return 1

        manifest_base_hash = entry.get("base_sha256", "")
        if manifest_base_hash and manifest_base_hash != sha256_hex(base):
            msg = f"base hash mismatch for {name}"
            if args.strict_hash:
                print(f"[ERROR] {msg}")
                return 1
            print(f"[WARN] {msg}")

        patch_path = args.patch_dir / patch_file
        if not patch_path.exists():
            print(f"[ERROR] patch file not found: {patch_path}")
            return 1

        try:
            target_size, ops = parse_patch(patch_path.read_bytes())
            target = apply_ops(base, target_size, ops)
        except Exception as exc:
            print(f"[ERROR] patch apply failed for {name}: {exc}")
            return 1

        manifest_target_hash = entry.get("target_sha256", "")
        if manifest_target_hash and manifest_target_hash != sha256_hex(target):
            msg = f"target hash mismatch for {name}"
            if args.strict_hash:
                print(f"[ERROR] {msg}")
                return 1
            print(f"[WARN] {msg}")

        out_path = args.out_dir / name
        out_path.write_bytes(target)
        print(f"[OK] {name} <- {patch_file} ({arc.name})")

    print("")
    print("Patchset apply complete")
    print(f"  Entries : {len(entries)}")
    print(f"  Output  : {args.out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
