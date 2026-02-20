#!/usr/bin/env python3
"""
Convert Last Express .BG resources to viewable 24-bit BMP images.

The decoder logic mirrors ScummVM's lastexpress GraphicsManager::decomp16 path.
"""

import argparse
import struct
import sys
from pathlib import Path


MEM_PAGE_SIZE = 2048
DEFAULT_CHUNK_PAGES = 8
SCREEN_W = 640
SCREEN_H = 480


def u16le(buf, off):
    return struct.unpack_from("<H", buf, off)[0]


def w16le(buf, off, val):
    struct.pack_into("<H", buf, off, val & 0xFFFF)


class BGDecompressor:
    def __init__(self):
        self.out = bytearray(SCREEN_W * SCREEN_H * 2)  # 16-bit RGB555
        self.flags = 0
        self.last_comp_item = 0
        self.channel_sizes = [0, 0, 0]
        self.out_ptr = 0
        self.rect = {"x": 0, "y": 0, "width": SCREEN_W, "height": SCREEN_H}

    def _decomp_r(self, data):
        remaining = len(data)
        src_i = 0

        while remaining > 0:
            if self.flags & 0x10:
                self.flags &= ~0x10
                cmd = self.last_comp_item
            else:
                cmd = data[src_i]
                src_i += 1
                remaining -= 1

            if cmd & 0x80:
                if remaining == 0:
                    self.flags |= 0x10
                    self.last_comp_item = cmd
                    return

                off_byte = data[src_i]
                src_i += 1
                remaining -= 1

                count = ((cmd & 0x70) >> 4) + 3
                src_ptr = self.out_ptr + 2 * (((cmd & 0x0F) << 8) + off_byte) - 0x2000
                for _ in range(count):
                    self.out[self.out_ptr] = self.out[src_ptr]
                    self.out_ptr += 2
                    src_ptr += 2
            else:
                count = (cmd >> 5) + 1
                value = (cmd & 0x1F) << 2
                for _ in range(count):
                    self.out[self.out_ptr] = value
                    self.out_ptr += 2

    def _decomp_b(self, data):
        remaining = len(data)
        src_i = 0

        while remaining > 0:
            if self.flags & 0x10:
                self.flags &= ~0x10
                cmd = self.last_comp_item
            else:
                cmd = data[src_i]
                src_i += 1
                remaining -= 1

            if cmd & 0x80:
                if remaining == 0:
                    self.flags |= 0x10
                    self.last_comp_item = cmd
                    return

                off_byte = data[src_i]
                src_i += 1
                remaining -= 1

                count = ((cmd & 0x70) >> 4) + 3
                src_ptr = self.out_ptr + 2 * (((cmd & 0x0F) << 8) + off_byte) - 0x2000
                for _ in range(count):
                    self.out[self.out_ptr] = self.out[src_ptr]
                    self.out_ptr += 2
                    src_ptr += 2
            else:
                count = (cmd >> 5) + 1
                value = cmd & 0x1F
                for _ in range(count):
                    self.out[self.out_ptr] = value
                    self.out_ptr += 2

    def _decomp_g(self, data):
        remaining = len(data)
        src_i = 0
        out_ptr = self.out_ptr

        while remaining > 0:
            if self.flags & 0x10:
                self.flags &= ~0x10
                cmd = self.last_comp_item
            else:
                cmd = data[src_i]
                src_i += 1
                remaining -= 1

            if cmd & 0x80:
                if remaining == 0:
                    self.last_comp_item = cmd
                    self.out_ptr = out_ptr
                    self.flags |= 0x10
                    return

                off_byte = data[src_i]
                src_i += 1
                remaining -= 1

                count = ((cmd & 0x70) >> 4) + 3
                src_ptr = out_ptr + 2 * (((cmd & 0x0F) << 8) + off_byte) - 0x2000
                for _ in range(count):
                    pix = u16le(self.out, out_ptr)
                    src_pix = u16le(self.out, src_ptr)
                    pix |= (src_pix & 0x03E0)
                    w16le(self.out, out_ptr, pix)
                    out_ptr += 2
                    src_ptr += 2
            else:
                count = (cmd >> 5) + 1
                gval = 32 * (cmd & 0x1F)
                for _ in range(count):
                    pix = u16le(self.out, out_ptr)
                    pix |= gval
                    w16le(self.out, out_ptr, pix)
                    out_ptr += 2

        self.out_ptr = out_ptr

    def decomp16(self, chunk):
        src = chunk
        src_pos = 0
        eff_size = len(chunk)

        if self.flags == 0:
            if len(src) < 28:
                raise ValueError("BG chunk too short for frame header")

            self.flags = 0x1000
            self.out_ptr = 1  # little-endian: high byte write for red channel
            self.rect["x"] = struct.unpack_from("<I", src, 0)[0]
            self.rect["y"] = struct.unpack_from("<I", src, 4)[0]
            self.rect["width"] = struct.unpack_from("<I", src, 8)[0]
            self.rect["height"] = struct.unpack_from("<I", src, 12)[0]
            self.channel_sizes[0] = struct.unpack_from("<I", src, 16)[0]
            self.channel_sizes[1] = struct.unpack_from("<I", src, 20)[0]
            self.channel_sizes[2] = struct.unpack_from("<I", src, 24)[0]

            src_pos = 28
            eff_size -= 28

        while eff_size > 0:
            channel = self.flags & 3
            remaining_ch = self.channel_sizes[channel]
            chunk_size = eff_size if eff_size < remaining_ch else remaining_ch
            if eff_size >= remaining_ch:
                self.flags |= 0x100

            self.channel_sizes[channel] -= chunk_size
            payload = src[src_pos : src_pos + chunk_size]

            if channel == 0:
                self._decomp_r(payload)
            elif channel == 1:
                self._decomp_b(payload)
            elif channel == 2:
                self._decomp_g(payload)

            src_pos += chunk_size
            eff_size -= chunk_size

            if self.flags & 0x100:
                self.flags &= ~0x100
                self.out_ptr = 0
                self.flags += 1
                if (self.flags & 3) == 3:
                    return False

        return True


def apply_layout(front_buf, rect):
    x = int(rect["x"])
    y = int(rect["y"])
    w = int(rect["width"])
    h = int(rect["height"])

    if not (0 <= x < SCREEN_W and 0 <= y < SCREEN_H and w > 0 and h > 0):
        raise ValueError(f"invalid BG rect: x={x}, y={y}, w={w}, h={h}")
    if x + w > SCREEN_W or y + h > SCREEN_H:
        raise ValueError(f"BG rect out of bounds: x={x}, y={y}, w={w}, h={h}")

    # Move decompressed compact block into final screen coordinates (same as loadBG memmove loop).
    for row in range(y + h - 1, y - 1, -1):
        dst = (SCREEN_W * row + x) * 2
        src = (w * (row - y)) * 2
        front_buf[dst : dst + w * 2] = front_buf[src : src + w * 2]

    # Clear side bars if viewport is narrower than full width.
    if x:
        left_bytes = x * 2
        right_start = (SCREEN_W - x) * 2
        for row in range(SCREEN_H):
            row_off = row * SCREEN_W * 2
            front_buf[row_off : row_off + left_bytes] = b"\x00" * left_bytes
            front_buf[row_off + right_start : row_off + SCREEN_W * 2] = b"\x00" * left_bytes

    # Clear top/bottom bars if viewport is shorter than full height.
    if y:
        strip_bytes = w * 2
        x_off = x * 2
        for row in range(y):
            row_off = row * SCREEN_W * 2 + x_off
            front_buf[row_off : row_off + strip_bytes] = b"\x00" * strip_bytes
        for row in range(SCREEN_H - y, SCREEN_H):
            row_off = row * SCREEN_W * 2 + x_off
            front_buf[row_off : row_off + strip_bytes] = b"\x00" * strip_bytes


def rgb555_to_rgb888(pixel):
    b5 = pixel & 0x1F
    g5 = (pixel >> 5) & 0x1F
    r5 = (pixel >> 10) & 0x1F
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g5 << 3) | (g5 >> 2)
    b8 = (b5 << 3) | (b5 >> 2)
    return r8, g8, b8


def write_bmp_24(path, front_buf, width=SCREEN_W, height=SCREEN_H):
    row_raw = width * 3
    row_pad = (4 - (row_raw % 4)) % 4
    pixel_data_size = (row_raw + row_pad) * height
    file_size = 14 + 40 + pixel_data_size

    with path.open("wb") as f:
        # BITMAPFILEHEADER
        f.write(b"BM")
        f.write(struct.pack("<I", file_size))
        f.write(struct.pack("<HH", 0, 0))
        f.write(struct.pack("<I", 14 + 40))

        # BITMAPINFOHEADER
        f.write(struct.pack("<I", 40))          # biSize
        f.write(struct.pack("<i", width))       # biWidth
        f.write(struct.pack("<i", height))      # biHeight (bottom-up)
        f.write(struct.pack("<H", 1))           # biPlanes
        f.write(struct.pack("<H", 24))          # biBitCount
        f.write(struct.pack("<I", 0))           # biCompression (BI_RGB)
        f.write(struct.pack("<I", pixel_data_size))
        f.write(struct.pack("<i", 2835))        # biXPelsPerMeter
        f.write(struct.pack("<i", 2835))        # biYPelsPerMeter
        f.write(struct.pack("<I", 0))           # biClrUsed
        f.write(struct.pack("<I", 0))           # biClrImportant

        pad = b"\x00" * row_pad
        for y in range(height - 1, -1, -1):
            row = bytearray()
            base = y * width * 2
            for x in range(width):
                pix = u16le(front_buf, base + x * 2)
                r, g, b = rgb555_to_rgb888(pix)
                row.extend((b, g, r))
            f.write(row)
            if row_pad:
                f.write(pad)


def decode_bg_file(input_bg, output_bmp, chunk_pages):
    blob = input_bg.read_bytes()
    dec = BGDecompressor()

    pos = 0
    keep_going = True
    chunk_size = chunk_pages * MEM_PAGE_SIZE
    while keep_going and pos < len(blob):
        part = blob[pos : pos + chunk_size]
        keep_going = dec.decomp16(part)
        pos += len(part)

    if keep_going:
        raise ValueError("unexpected EOF before BG frame finished")

    apply_layout(dec.out, dec.rect)
    write_bmp_24(output_bmp, dec.out)
    return dec.rect, pos, len(blob)


def convert_one(input_bg, output_path, chunk_pages):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    rect, consumed, total = decode_bg_file(input_bg, output_path, chunk_pages)
    print(
        f"[OK] {input_bg.name} -> {output_path.name} | "
        f"rect=({rect['x']},{rect['y']} {rect['width']}x{rect['height']}) "
        f"bytes={consumed}/{total}"
    )


def convert_dir(input_dir, output_dir, chunk_pages):
    bg_files = sorted(input_dir.glob("*.BG"))
    if not bg_files:
        raise ValueError(f"no .BG files found in {input_dir}")
    for bg in bg_files:
        out = output_dir / (bg.stem + ".bmp")
        convert_one(bg, out, chunk_pages)


def main():
    parser = argparse.ArgumentParser(description="Convert Last Express .BG to BMP")
    parser.add_argument("input", help="Input .BG file or directory containing .BG files")
    parser.add_argument(
        "output",
        nargs="?",
        default="",
        help="Output .bmp file (for file input) or output directory (for dir input)",
    )
    parser.add_argument(
        "--chunk-pages",
        type=int,
        default=DEFAULT_CHUNK_PAGES,
        help="Pages read per decomp step (default: 8, same as engine loadBG)",
    )
    args = parser.parse_args()

    inp = Path(args.input)
    if not inp.exists():
        print(f"[ERROR] input not found: {inp}")
        return 2
    if args.chunk_pages <= 0:
        print("[ERROR] --chunk-pages must be > 0")
        return 2

    try:
        if inp.is_file():
            if args.output:
                out = Path(args.output)
            else:
                out = inp.with_suffix(".bmp")
            convert_one(inp, out, args.chunk_pages)
        else:
            out_dir = Path(args.output) if args.output else (inp / "_bmp")
            out_dir.mkdir(parents=True, exist_ok=True)
            convert_dir(inp, out_dir, args.chunk_pages)
    except Exception as exc:
        print(f"[ERROR] {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
