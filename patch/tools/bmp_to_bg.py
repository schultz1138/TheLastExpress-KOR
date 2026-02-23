#!/usr/bin/env python3
"""
Convert 24-bit BMP images to Last Express .BG resources.

The encoder currently emits run commands only (no back-reference copy commands),
which is sufficient for functional round-trip testing in-game.
"""

import argparse
import struct
import sys
from pathlib import Path


def _read_bmp_24(path: Path):
    blob = path.read_bytes()
    if len(blob) < 54 or blob[:2] != b"BM":
        raise ValueError(f"not a BMP file: {path}")

    data_off = struct.unpack_from("<I", blob, 10)[0]
    dib_size = struct.unpack_from("<I", blob, 14)[0]
    if dib_size < 40:
        raise ValueError("unsupported BMP DIB header (need BITMAPINFOHEADER or newer)")

    width = struct.unpack_from("<i", blob, 18)[0]
    height_raw = struct.unpack_from("<i", blob, 22)[0]
    planes = struct.unpack_from("<H", blob, 26)[0]
    bpp = struct.unpack_from("<H", blob, 28)[0]
    compression = struct.unpack_from("<I", blob, 30)[0]

    if width <= 0 or height_raw == 0:
        raise ValueError("invalid BMP dimensions")
    if planes != 1 or bpp != 24 or compression != 0:
        raise ValueError("only uncompressed 24-bit BMP is supported")

    top_down = height_raw < 0
    height = abs(height_raw)
    row_size = ((width * 3 + 3) // 4) * 4
    needed = data_off + row_size * height
    if len(blob) < needed:
        raise ValueError("BMP pixel data is truncated")

    pixels_555 = []
    for out_y in range(height):
        src_y = out_y if top_down else (height - 1 - out_y)
        row_off = data_off + src_y * row_size
        for x in range(width):
            b, g, r = struct.unpack_from("<BBB", blob, row_off + x * 3)
            r5 = r >> 3
            g5 = g >> 3
            b5 = b >> 3
            pixels_555.append((r5 << 10) | (g5 << 5) | b5)

    return width, height, pixels_555


def _parse_template_rect(template_bg: Path):
    blob = template_bg.read_bytes()
    if len(blob) < 28:
        raise ValueError(f"template BG too short: {template_bg}")
    x, y, w, h = struct.unpack_from("<4I", blob, 0)
    return int(x), int(y), int(w), int(h)


def _extract_rect(pixels, screen_w, screen_h, x, y, w, h):
    if x < 0 or y < 0 or w <= 0 or h <= 0:
        raise ValueError(f"invalid rect: ({x},{y} {w}x{h})")
    if x + w > screen_w or y + h > screen_h:
        raise ValueError(
            f"rect out of bounds: ({x},{y} {w}x{h}) for source {screen_w}x{screen_h}"
        )

    out = []
    for row in range(y, y + h):
        base = row * screen_w + x
        out.extend(pixels[base : base + w])
    return out


def _encode_run_channel(values):
    out = bytearray()
    i = 0
    n = len(values)
    while i < n:
        value = values[i] & 0x1F
        run = 1
        while i + run < n and run < 4 and (values[i + run] & 0x1F) == value:
            run += 1
        cmd = ((run - 1) << 5) | value
        out.append(cmd)
        i += run
    return bytes(out)


def encode_bmp_to_bg(input_bmp: Path, output_bg: Path, x: int, y: int, w: int, h: int):
    src_w, src_h, src_pixels = _read_bmp_24(input_bmp)
    rect_pixels = _extract_rect(src_pixels, src_w, src_h, x, y, w, h)

    r_values = [((pix >> 10) & 0x1F) for pix in rect_pixels]
    b_values = [(pix & 0x1F) for pix in rect_pixels]
    g_values = [((pix >> 5) & 0x1F) for pix in rect_pixels]

    r_stream = _encode_run_channel(r_values)
    b_stream = _encode_run_channel(b_values)
    g_stream = _encode_run_channel(g_values)

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
    payload = header + r_stream + b_stream + g_stream

    output_bg.parent.mkdir(parents=True, exist_ok=True)
    output_bg.write_bytes(payload)

    return {
        "src_w": src_w,
        "src_h": src_h,
        "x": x,
        "y": y,
        "w": w,
        "h": h,
        "pixels": len(rect_pixels),
        "r_size": len(r_stream),
        "b_size": len(b_stream),
        "g_size": len(g_stream),
        "bg_size": len(payload),
    }


def main():
    parser = argparse.ArgumentParser(description="Convert 24-bit BMP to Last Express .BG")
    parser.add_argument("input_bmp", help="Input 24-bit BMP")
    parser.add_argument("output_bg", help="Output .BG path")
    parser.add_argument("--template-bg", default="", help="Read rect (x,y,w,h) from template .BG")
    parser.add_argument("--x", type=int, default=None, help="Rect x")
    parser.add_argument("--y", type=int, default=None, help="Rect y")
    parser.add_argument("--width", type=int, default=None, help="Rect width")
    parser.add_argument("--height", type=int, default=None, help="Rect height")
    args = parser.parse_args()

    input_bmp = Path(args.input_bmp)
    output_bg = Path(args.output_bg)
    if not input_bmp.exists():
        print(f"[ERROR] input not found: {input_bmp}")
        return 2

    x = args.x
    y = args.y
    w = args.width
    h = args.height

    if args.template_bg:
        template = Path(args.template_bg)
        if not template.exists():
            print(f"[ERROR] template BG not found: {template}")
            return 2
        tx, ty, tw, th = _parse_template_rect(template)
        if x is None:
            x = tx
        if y is None:
            y = ty
        if w is None:
            w = tw
        if h is None:
            h = th

    if x is None or y is None or w is None or h is None:
        print("[ERROR] rect is required. Use --template-bg or all of --x --y --width --height.")
        return 2

    try:
        stats = encode_bmp_to_bg(input_bmp, output_bg, x, y, w, h)
    except Exception as exc:
        print(f"[ERROR] {exc}")
        return 1

    print(
        f"[OK] {input_bmp.name} -> {output_bg.name} | "
        f"src={stats['src_w']}x{stats['src_h']} rect=({stats['x']},{stats['y']} {stats['w']}x{stats['h']}) "
        f"pixels={stats['pixels']} sizes(R/B/G)={stats['r_size']}/{stats['b_size']}/{stats['g_size']} "
        f"bg_bytes={stats['bg_size']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
