import argparse
import os
import struct
import sys

MEM_PAGE_SIZE = 2048
ENTRY_SIZE = 22


def read_hpf_index(path):
    with open(path, "rb") as f:
        header = f.read(4)
        if len(header) != 4:
            raise ValueError(f"{path}: file too short (missing entry count)")

        entry_count = struct.unpack("<I", header)[0]
        entries = []
        for i in range(entry_count):
            raw = f.read(ENTRY_SIZE)
            if len(raw) != ENTRY_SIZE:
                raise ValueError(f"{path}: truncated entry table at index {i}")

            name_raw = raw[:12]
            offset = struct.unpack("<I", raw[12:16])[0]
            size = struct.unpack("<H", raw[16:18])[0]
            current_pos = struct.unpack("<H", raw[18:20])[0]
            status = struct.unpack("<H", raw[20:22])[0]

            if b"\x00" in name_raw:
                nul_idx = name_raw.index(b"\x00")
                name_raw = name_raw[:nul_idx]
            try:
                name = name_raw.decode("ascii")
            except UnicodeDecodeError:
                name = ""

            entries.append(
                {
                    "index": i,
                    "name": name,
                    "offset": offset,
                    "size": size,
                    "current_pos": current_pos,
                    "status": status,
                }
            )

        f.seek(0, os.SEEK_END)
        file_size = f.tell()

    return entries, file_size


def validate_hpf(path):
    entries, archive_bytes = read_hpf_index(path)
    problems = []
    warnings = []

    names = []
    for e in entries:
        idx = e["index"]
        name = e["name"]

        if not name:
            problems.append(f"entry {idx}: invalid or non-ASCII name")
            continue

        if len(name.encode("ascii")) > 12:
            problems.append(f"entry {idx}: name exceeds 12 bytes: {name}")

        if e["size"] == 0:
            warnings.append(f"entry {idx}: zero-size file: {name}")

        start = e["offset"] * MEM_PAGE_SIZE
        end = start + e["size"] * MEM_PAGE_SIZE
        if start > archive_bytes:
            problems.append(
                f"entry {idx}: offset beyond archive end ({name}, offset={e['offset']})"
            )
        elif end > archive_bytes:
            problems.append(
                f"entry {idx}: range exceeds archive end ({name}, end={end}, archive={archive_bytes})"
            )

        names.append(name)

    if names != sorted(names, key=lambda s: s.upper()):
        problems.append(
            "entry table is not sorted by uppercase name (binary search compatibility risk)"
        )

    seen = set()
    duplicates = set()
    for n in names:
        key = n.upper()
        if key in seen:
            duplicates.add(n)
        seen.add(key)
    if duplicates:
        problems.append(
            "duplicate names (case-insensitive): " + ", ".join(sorted(duplicates))
        )

    return entries, archive_bytes, problems, warnings


def compare_with_base(korean_entries, base_entries):
    base_set = {e["name"].upper() for e in base_entries if e["name"]}
    ko_set = {e["name"].upper() for e in korean_entries if e["name"]}

    overrides = sorted(ko_set & base_set)
    only_in_overlay = sorted(ko_set - base_set)
    return overrides, only_in_overlay


def main():
    parser = argparse.ArgumentParser(
        description="Validate Last Express HPF archive format for KOREAN.HPF overlay use"
    )
    parser.add_argument("korean_hpf", help="Path to KOREAN.HPF")
    parser.add_argument(
        "--base-hpf",
        default=None,
        help="Optional base archive (e.g., HD.HPF) for override analysis",
    )
    args = parser.parse_args()

    try:
        ko_entries, ko_bytes, problems, warnings = validate_hpf(args.korean_hpf)
    except Exception as e:
        print(f"[ERROR] {e}")
        return 2

    print(f"KOREAN archive: {args.korean_hpf}")
    print(f"Total bytes: {ko_bytes}")
    print(f"Entries: {len(ko_entries)}")

    if warnings:
        print(f"Warnings: {len(warnings)}")
        for w in warnings[:30]:
            print(f"  - {w}")
        if len(warnings) > 30:
            print(f"  ... {len(warnings) - 30} more warnings")

    if args.base_hpf:
        try:
            base_entries, _, _, _ = validate_hpf(args.base_hpf)
            overrides, only_in_overlay = compare_with_base(ko_entries, base_entries)
            print(f"Overrides in base archive: {len(overrides)}")
            print(f"Overlay-only entries: {len(only_in_overlay)}")

            if only_in_overlay:
                print("  Overlay-only sample:")
                for n in only_in_overlay[:20]:
                    print(f"    - {n}")
                if len(only_in_overlay) > 20:
                    print(f"    ... {len(only_in_overlay) - 20} more")
        except Exception as e:
            print(f"[WARN] Could not compare with base HPF: {e}")

    if problems:
        print(f"Validation FAILED: {len(problems)} issue(s)")
        for p in problems:
            print(f"  - {p}")
        return 1

    print("Validation OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
