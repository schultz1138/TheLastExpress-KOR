#!/usr/bin/env python3
"""
Check whether identical source lines have inconsistent Korean translations.

Expected input is the 7-column subtitle table (kosubs.tsv / kosubs.user.tsv):
  sbe, entry-index, start, end, full-src, full-tr, SND-Filename
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Row:
    line_no: int
    sbe: str
    entry_index: int
    full_src: str
    full_tr: str


def normalize_source(text: str) -> str:
    text = text.replace("\r", " ").replace("\n", " ")
    return " ".join(text.split())


def normalize_translation(text: str, mode: str) -> str:
    if mode == "none":
        return text
    if mode == "space":
        return " ".join(text.split())
    # mode == "trim"
    return text.strip()


def parse_rows(path: Path) -> tuple[list[Row], int]:
    rows: list[Row] = []
    skipped = 0

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for line_no, parts in enumerate(reader, start=1):
            if not parts:
                continue
            if not any(p.strip() for p in parts):
                continue
            if parts[0].lstrip().startswith("#"):
                continue
            if len(parts) < 6:
                skipped += 1
                continue

            idx_str = parts[1].strip()
            if not idx_str.isdigit():
                # Header row (or malformed row).
                skipped += 1
                continue

            sbe = parts[0].strip().upper()
            full_src = parts[4]
            full_tr = parts[5]
            rows.append(
                Row(
                    line_no=line_no,
                    sbe=sbe,
                    entry_index=int(idx_str),
                    full_src=full_src,
                    full_tr=full_tr,
                )
            )

    return rows, skipped


def shorten(text: str, limit: int = 96) -> str:
    text = text.replace("\t", " ")
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 3)] + "..."


def collect_conflicts(
    rows: list[Row],
    tr_mode: str,
    include_empty: bool,
):
    groups = {}
    for row in rows:
        src_key = normalize_source(row.full_src)
        if not src_key:
            continue
        tr_key = normalize_translation(row.full_tr, tr_mode)
        if not include_empty and tr_key == "":
            continue

        if src_key not in groups:
            groups[src_key] = {
                "source_display": row.full_src.strip() or src_key,
                "variants": defaultdict(list),
            }
        groups[src_key]["variants"][tr_key].append(row)

    conflicts = []
    for src_key, info in groups.items():
        variants = info["variants"]
        if len(variants) <= 1:
            continue
        conflicts.append(
            {
                "src_key": src_key,
                "source_display": info["source_display"],
                "variants": variants,
                "row_count": sum(len(v) for v in variants.values()),
            }
        )

    conflicts.sort(key=lambda item: (-len(item["variants"]), -item["row_count"], item["src_key"]))
    return conflicts, len(groups)


def write_report_tsv(path: Path, conflicts, show_limit: int, location_limit: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(["full-src", "variant-count", "full-tr", "count", "occurrences"])
        for item in conflicts[:show_limit]:
            src = item["source_display"]
            var_count = len(item["variants"])
            for tr_key, rows in sorted(item["variants"].items(), key=lambda kv: (-len(kv[1]), kv[0])):
                locs = [f"{r.sbe}#{r.entry_index}" for r in rows[:location_limit]]
                if len(rows) > location_limit:
                    locs.append(f"...(+{len(rows) - location_limit})")
                writer.writerow([src, var_count, tr_key, len(rows), ", ".join(locs)])


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect inconsistent translations for identical source lines (kosubs TSV)."
    )
    parser.add_argument("--input", type=Path, required=True, help="Input TSV (7 columns, e.g. kosubs.tsv)")
    parser.add_argument(
        "--normalize-translation",
        choices=("trim", "space", "none"),
        default="trim",
        help="How to normalize translation text before comparison (default: trim)",
    )
    parser.add_argument(
        "--include-empty",
        action="store_true",
        help="Include empty translations in conflict detection",
    )
    parser.add_argument(
        "--show-limit",
        type=int,
        default=50,
        help="Max number of conflicting source groups to print (default: 50)",
    )
    parser.add_argument(
        "--location-limit",
        type=int,
        default=6,
        help="Max locations to print per translation variant (default: 6)",
    )
    parser.add_argument(
        "--out-tsv",
        type=Path,
        default=None,
        help="Optional output TSV report path",
    )
    parser.add_argument(
        "--strict-exit",
        action="store_true",
        help="Return exit code 3 when conflicts are found",
    )
    args = parser.parse_args()

    if not args.input.exists():
        print(f"[ERROR] input not found: {args.input}")
        return 2

    rows, skipped = parse_rows(args.input)
    if not rows:
        print("[ERROR] no subtitle rows parsed. Check input format (expected 7-column kosubs TSV).")
        return 2

    conflicts, source_count = collect_conflicts(
        rows=rows,
        tr_mode=args.normalize_translation,
        include_empty=args.include_empty,
    )

    print(f"Input              : {args.input}")
    print(f"Rows parsed        : {len(rows)}")
    print(f"Rows skipped       : {skipped}")
    print(f"Unique source lines: {source_count}")
    print(f"Conflicts found    : {len(conflicts)}")

    if conflicts:
        print("")
        print(f"Top conflicts (max {args.show_limit}):")
        for idx, item in enumerate(conflicts[: args.show_limit], start=1):
            print("")
            print(f"[{idx}] variants={len(item['variants'])}, rows={item['row_count']}")
            print(f"  SRC: {shorten(item['source_display'])}")

            variant_items = sorted(item["variants"].items(), key=lambda kv: (-len(kv[1]), kv[0]))
            for v_idx, (tr_key, variant_rows) in enumerate(variant_items, start=1):
                tr_preview = shorten(tr_key if tr_key else "(empty)")
                print(f"  TR{v_idx}: {tr_preview}  (count={len(variant_rows)})")
                locs = variant_rows[: args.location_limit]
                for loc in locs:
                    print(f"    - {loc.sbe}#{loc.entry_index} (line {loc.line_no})")
                if len(variant_rows) > args.location_limit:
                    print(f"    - ... (+{len(variant_rows) - args.location_limit} more)")

    if args.out_tsv:
        write_report_tsv(
            path=args.out_tsv,
            conflicts=conflicts,
            show_limit=args.show_limit,
            location_limit=args.location_limit,
        )
        print(f"\nReport written     : {args.out_tsv}")

    if conflicts and args.strict_exit:
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
