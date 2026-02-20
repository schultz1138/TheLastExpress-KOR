#!/usr/bin/env python3
"""
Extract editable subtitle template TSV from a local HPF archive that contains .SBE files.
"""

import argparse
import csv
import struct
import sys
from pathlib import Path


MEM_PAGE_SIZE = 2048
ENTRY_SIZE = 22


def read_hpf_index(path: Path):
    entries = {}
    with path.open("rb") as f:
        head = f.read(4)
        if len(head) != 4:
            raise ValueError(f"{path}: missing entry count")
        count = struct.unpack("<I", head)[0]

        for i in range(count):
            item = f.read(ENTRY_SIZE)
            if len(item) != ENTRY_SIZE:
                raise ValueError(f"{path}: truncated index at entry {i}")

            name = item[:12].split(b"\x00", 1)[0].decode("ascii", "ignore").upper()
            if not name:
                continue

            offset = struct.unpack("<I", item[12:16])[0]
            size_pages = struct.unpack("<H", item[16:18])[0]
            entries[name] = {
                "offset": offset,
                "size_pages": size_pages,
            }
    return entries


def read_entry_bytes(hpf_path: Path, meta):
    off = meta["offset"] * MEM_PAGE_SIZE
    size = meta["size_pages"] * MEM_PAGE_SIZE
    with hpf_path.open("rb") as f:
        f.seek(off)
        data = f.read(size)
    if len(data) != size:
        raise ValueError(f"{hpf_path}: short read ({len(data)} / {size})")
    return data


def decode_char_codes(codes):
    chars = []
    for code in codes:
        if code == 0:
            continue
        try:
            chars.append(chr(code))
        except ValueError:
            chars.append("?")

    text = "".join(chars)
    text = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    text = " ".join(text.split())
    return text


def parse_sbe_rows(blob: bytes):
    if len(blob) < 2:
        return []

    count = struct.unpack_from("<H", blob, 0)[0]
    pos = 2
    rows = []

    for idx in range(count):
        if pos + 8 > len(blob):
            break

        start, end, upper_len, lower_len = struct.unpack_from("<4H", blob, pos)
        pos += 8

        needed = (upper_len + lower_len) * 2
        if pos + needed > len(blob):
            break

        upper = ()
        if upper_len:
            upper = struct.unpack_from(f"<{upper_len}H", blob, pos)
        pos += upper_len * 2

        lower = ()
        if lower_len:
            lower = struct.unpack_from(f"<{lower_len}H", blob, pos)
        pos += lower_len * 2

        upper_text = decode_char_codes(upper)
        lower_text = decode_char_codes(lower)
        if upper_text and lower_text:
            full = f"{upper_text} {lower_text}"
        elif upper_text:
            full = upper_text
        else:
            full = lower_text
        full = " ".join(full.split())

        rows.append(
            {
                "index": idx,
                "start": int(start),
                "end": int(end),
                "full_src": full,
            }
        )

    # Match runtime behavior: if end time is zero, use next entry start.
    for i in range(len(rows) - 1):
        if rows[i]["end"] == 0:
            rows[i]["end"] = rows[i + 1]["start"]

    return rows


def load_translation_map(path: Path):
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        if line.lstrip().startswith("#"):
            continue

        parts = line.split("\t")
        if len(parts) < 3:
            continue
        if not parts[1].isdigit():
            continue

        sbe_name = parts[0].strip().upper()
        idx = int(parts[1])
        if len(parts) >= 6:
            ko = parts[5]
        else:
            ko = "\t".join(parts[2:])

        out[(sbe_name, idx)] = ko
    return out


def main():
    parser = argparse.ArgumentParser(description="Extract editable subtitle TSV from HPF .SBE entries")
    parser.add_argument("--hpf", type=Path, required=True, help="HPF archive path (typically Moded_HD.HPF)")
    parser.add_argument(
        "--out",
        type=Path,
        required=True,
        help="Output TSV path (7 columns: sbe/index/start/end/full-src/full-tr/snd)",
    )
    parser.add_argument(
        "--merge-subko",
        type=Path,
        default=None,
        help="Optional TSV (3-col subko.tsv or 7-col kosubs.tsv) to prefill Korean lines",
    )
    args = parser.parse_args()

    if not args.hpf.exists():
        print(f"[ERROR] HPF not found: {args.hpf}")
        return 2

    tr_map = {}
    if args.merge_subko:
        if not args.merge_subko.exists():
            print(f"[ERROR] merge TSV not found: {args.merge_subko}")
            return 2
        tr_map = load_translation_map(args.merge_subko)

    try:
        index = read_hpf_index(args.hpf)
    except Exception as exc:
        print(f"[ERROR] failed reading HPF index: {exc}")
        return 1

    sbe_names = sorted([name for name in index.keys() if name.endswith(".SBE")])
    if not sbe_names:
        print("[ERROR] no .SBE entries found in archive")
        return 2

    args.out.parent.mkdir(parents=True, exist_ok=True)

    total_rows = 0
    with args.out.open("w", encoding="utf-8", newline="") as wf:
        writer = csv.writer(wf, delimiter="\t", lineterminator="\n")
        writer.writerow(["sbe", "entry-index", "start", "end", "full-src", "full-tr", "SND-Filename"])

        for sbe_name in sbe_names:
            meta = index[sbe_name]
            try:
                blob = read_entry_bytes(args.hpf, meta)
                rows = parse_sbe_rows(blob)
            except Exception as exc:
                print(f"[WARN] failed parsing {sbe_name}: {exc}")
                continue

            snd_name = sbe_name[:-4] + ".SND"
            for row in rows:
                key = (sbe_name, row["index"])
                full_tr = tr_map.get(key, "")
                writer.writerow(
                    [
                        sbe_name,
                        row["index"],
                        row["start"],
                        row["end"],
                        row["full_src"],
                        full_tr,
                        snd_name,
                    ]
                )
                total_rows += 1

    print(f"[OK] wrote: {args.out}")
    print(f"  SBE files: {len(sbe_names)}")
    print(f"  Rows     : {total_rows}")
    if tr_map:
        print(f"  Merge map: {len(tr_map)} entries from {args.merge_subko}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
