#!/usr/bin/env python3
"""
Extract selected entries from one or more Last Express HPF archives.
"""

import argparse
import struct
import sys
from pathlib import Path

MEM_PAGE_SIZE = 2048
ENTRY_SIZE = 22


def load_index(hpf_path: Path):
    with hpf_path.open("rb") as f:
        raw = f.read(4)
        if len(raw) != 4:
            raise ValueError(f"{hpf_path}: missing entry count")
        entry_count = struct.unpack("<I", raw)[0]

        entries = {}
        for i in range(entry_count):
            item = f.read(ENTRY_SIZE)
            if len(item) != ENTRY_SIZE:
                raise ValueError(f"{hpf_path}: truncated index at entry {i}")

            name = item[:12].split(b"\x00", 1)[0].decode("ascii", "ignore").upper()
            offset = struct.unpack("<I", item[12:16])[0]
            size_pages = struct.unpack("<H", item[16:18])[0]

            if not name:
                continue

            entries[name] = {
                "name": name,
                "offset": offset,
                "size_pages": size_pages,
            }

    return entries


def read_names(args):
    names = set()
    for item in args.name:
        n = item.strip().upper()
        if n:
            names.add(n)

    if args.names_file:
        for line in args.names_file.read_text(encoding="utf-8").splitlines():
            n = line.strip().upper()
            if n:
                names.add(n)

    if not names:
        raise ValueError("no entry names provided (use --name or --names-file)")
    return sorted(names)


def build_entry_sources(archives):
    sources = {}
    for arc in archives:
        idx = load_index(arc)
        for name, entry in idx.items():
            if name not in sources:
                sources[name] = (arc, entry)
    return sources


def extract_one(archive_path: Path, entry, out_path: Path):
    byte_off = entry["offset"] * MEM_PAGE_SIZE
    byte_size = entry["size_pages"] * MEM_PAGE_SIZE

    with archive_path.open("rb") as f:
        f.seek(byte_off)
        data = f.read(byte_size)

    if len(data) != byte_size:
        raise ValueError(
            f"{archive_path}: failed reading {entry['name']} ({len(data)} / {byte_size})"
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(data)


def main():
    parser = argparse.ArgumentParser(description="Extract selected files from HPF archives")
    parser.add_argument("output_dir", type=Path, help="Directory to place extracted files")
    parser.add_argument(
        "--archives",
        type=Path,
        nargs="+",
        required=True,
        help="HPF archives to search in order",
    )
    parser.add_argument(
        "--name",
        action="append",
        default=[],
        help="Entry name to extract (repeatable)",
    )
    parser.add_argument(
        "--names-file",
        type=Path,
        default=None,
        help="UTF-8 text file with one entry name per line",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail if any requested entry is missing",
    )
    args = parser.parse_args()

    for arc in args.archives:
        if not arc.exists():
            print(f"[ERROR] archive not found: {arc}")
            return 2

    try:
        names = read_names(args)
        sources = build_entry_sources(args.archives)
    except Exception as exc:
        print(f"[ERROR] {exc}")
        return 2

    extracted = 0
    missing = []
    for name in names:
        src = sources.get(name)
        if not src:
            missing.append(name)
            continue

        arc, entry = src
        out_path = args.output_dir / name
        try:
            extract_one(arc, entry, out_path)
        except Exception as exc:
            print(f"[ERROR] extract failed for {name}: {exc}")
            return 1

        extracted += 1
        print(f"[OK] {name} <- {arc.name}")

    if missing:
        print(f"[WARN] missing entries: {len(missing)}")
        for name in missing[:30]:
            print(f"  - {name}")
        if len(missing) > 30:
            print(f"  ... {len(missing) - 30} more")
        if args.strict:
            return 1

    print(f"done: extracted={extracted}, requested={len(names)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
