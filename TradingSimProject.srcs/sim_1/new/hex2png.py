#!/usr/bin/env python3
"""Turn a frame dump (one RGB565 hex value per line, row-major) into a PNG.

    python3 tools/hex2png.py sim/out/ticket_frame.hex out.png [--scale 8] [--size 96x64]

Each OLED pixel becomes a scale x scale block with a 1px dark gap, so single
pixels are easy to count when checking the layout.
"""
import argparse
import sys

from PIL import Image, ImageDraw


def rgb565_to_rgb888(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return (r * 255 // 31, g * 255 // 63, b * 255 // 31)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("hex_in")
    ap.add_argument("png_out")
    ap.add_argument("--scale", type=int, default=8)
    ap.add_argument("--size", default="96x64")
    args = ap.parse_args()

    w, h = (int(n) for n in args.size.lower().split("x"))
    with open(args.hex_in) as f:
        vals = [int(line.strip(), 16) for line in f if line.strip()
                and not line.lstrip().startswith("//")]
    if len(vals) != w * h:
        sys.exit(f"{args.hex_in}: expected {w * h} pixels, found {len(vals)}")

    s = args.scale
    img = Image.new("RGB", (w * s, h * s), (24, 24, 24))
    draw = ImageDraw.Draw(img)
    for i, v in enumerate(vals):
        x, y = i % w, i // w
        draw.rectangle([x * s, y * s, x * s + s - 2, y * s + s - 2], fill=rgb565_to_rgb888(v))
    img.save(args.png_out)
    print(f"wrote {args.png_out} ({w}x{h} at {s}x)")


if __name__ == "__main__":
    main()
