import argparse
import os
import struct
import sys
from dataclasses import dataclass

MEM_PAGE_SIZE = 2048
ENTRY_SIZE = 22


@dataclass
class HPFEntry:
    source_path: str
    name: str
    size_bytes: int
    offset_sectors: int = 0
    size_sectors: int = 0
    current_pos: int = 0
    status: int = 0


def ceil_div(n, d):
    return (n + d - 1) // d


def discover_files(input_dir, recursive):
    files = []
    if recursive:
        for root, _, filenames in os.walk(input_dir):
            for fn in filenames:
                files.append(os.path.join(root, fn))
    else:
        for entry in os.scandir(input_dir):
            if entry.is_file():
                files.append(entry.path)
    return files


def normalize_name(filename, uppercase):
    name = os.path.basename(filename)
    if uppercase:
        name = name.upper()

    try:
        name_bytes = name.encode("ascii")
    except UnicodeEncodeError:
        raise ValueError(f"Non-ASCII filename is not supported by HPF: {name}")

    if len(name_bytes) > 12:
        raise ValueError(f"Filename exceeds HPF 12-byte limit: {name}")

    return name


def build_entries(input_dir, recursive=False, uppercase=True):
    if not os.path.isdir(input_dir):
        raise ValueError(f"Input directory not found: {input_dir}")

    paths = discover_files(input_dir, recursive=recursive)
    if not paths:
        raise ValueError(f"No files found in input directory: {input_dir}")

    entries = []
    seen = {}
    for p in paths:
        name = normalize_name(p, uppercase=uppercase)
        key = name.upper()
        if key in seen:
            raise ValueError(
                f"Duplicate filename (case-insensitive) detected: {name} <-> {seen[key]}"
            )
        seen[key] = p

        size_bytes = os.path.getsize(p)
        entries.append(
            HPFEntry(
                source_path=p,
                name=name,
                size_bytes=size_bytes,
            )
        )

    entries.sort(key=lambda e: e.name.upper())
    return entries


def assign_layout(entries):
    table_bytes = 4 + ENTRY_SIZE * len(entries)
    data_start_sector = ceil_div(table_bytes, MEM_PAGE_SIZE)
    current_sector = data_start_sector

    for e in entries:
        e.size_sectors = ceil_div(e.size_bytes, MEM_PAGE_SIZE)
        e.offset_sectors = current_sector
        current_sector += e.size_sectors

    return data_start_sector, current_sector


def write_hpf(entries, output_path, data_start_sector):
    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    with open(output_path, "wb") as out:
        out.write(struct.pack("<I", len(entries)))

        for e in entries:
            name_bytes = e.name.encode("ascii")
            padded_name = name_bytes + b"\x00" * (12 - len(name_bytes))
            out.write(
                struct.pack(
                    "<12sIHHH",
                    padded_name,
                    e.offset_sectors,
                    e.size_sectors,
                    e.current_pos,
                    e.status,
                )
            )

        index_end = out.tell()
        expected_data_start = data_start_sector * MEM_PAGE_SIZE
        if index_end > expected_data_start:
            raise RuntimeError(
                f"Internal layout error: index end ({index_end}) > data start ({expected_data_start})"
            )

        if expected_data_start > index_end:
            out.write(b"\x00" * (expected_data_start - index_end))

        for e in entries:
            if e.size_sectors == 0:
                continue

            with open(e.source_path, "rb") as src:
                payload = src.read()

            if len(payload) != e.size_bytes:
                raise RuntimeError(
                    f"Size mismatch while reading {e.source_path}: expected {e.size_bytes}, got {len(payload)}"
                )

            out.write(payload)

            padded_size = e.size_sectors * MEM_PAGE_SIZE
            if padded_size > e.size_bytes:
                out.write(b"\x00" * (padded_size - e.size_bytes))


def main():
    parser = argparse.ArgumentParser(
        description="Pack files into Last Express HPF archive format"
    )
    parser.add_argument("input_dir", help="Directory containing files to pack")
    parser.add_argument("output_hpf", help="Output HPF path")
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="Include files recursively from subdirectories",
    )
    parser.add_argument(
        "--keep-case",
        action="store_true",
        help="Keep original filename case (default: uppercase)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print packing plan without writing output",
    )
    args = parser.parse_args()

    entries = build_entries(
        args.input_dir,
        recursive=args.recursive,
        uppercase=not args.keep_case,
    )

    data_start_sector, total_sectors = assign_layout(entries)
    total_bytes = total_sectors * MEM_PAGE_SIZE

    print(f"Input dir: {args.input_dir}")
    print(f"Output HPF: {args.output_hpf}")
    print(f"Entries: {len(entries)}")
    print(f"Data start sector: {data_start_sector}")
    print(f"Total sectors: {total_sectors}")
    print(f"Estimated archive size: {total_bytes} bytes")

    preview_count = min(20, len(entries))
    print(f"Preview ({preview_count} entries):")
    for e in entries[:preview_count]:
        print(
            f"  {e.name:<12} offset={e.offset_sectors:<8} sizeSec={e.size_sectors:<6} sizeBytes={e.size_bytes}"
        )
    if len(entries) > preview_count:
        print(f"  ... {len(entries) - preview_count} more")

    if args.dry_run:
        print("Dry run complete. No file written.")
        return 0

    write_hpf(entries, args.output_hpf, data_start_sector)
    print("Pack complete.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
