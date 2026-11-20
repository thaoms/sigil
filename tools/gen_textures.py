#!/usr/bin/env python3
"""Rasterise Sigil's artwork into 32-bit TGA textures the game can load.

Usage: python3 tools/gen_textures.py   (needs rsvg-convert on PATH)
Every texture is white on transparent and tinted in game, except the disc.
All halo layers share one 220-unit coordinate system so they overlay exactly.
"""
import math, os, struct, subprocess, sys, tempfile, zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "Sigil", "Media")

HEX = "M24 3 L42 13.5 L42 34.5 L24 45 L6 34.5 L6 13.5 Z"
GLYPHS = {
    "attack": ("M9 39 L31 17 M27 13 L35 21 M12 32 L16 36 M37 6 V11 M42 11 H37 M41 6 L37.5 9.5", False),
    "command": ("M24 10 V37 M17.5 15.5 H30.5 M24 37 L21.5 33.5 M24 37 L26.5 33.5", True),
    "righteousness": ("M24 36.5 C16.5 31 17.5 22.5 24 12 C30.5 22.5 31.5 31 24 36.5 Z M24 31.5 C21.5 29 22 25.5 24 22.5 C26 25.5 26.5 29 24 31.5 Z", True),
    "wisdom": ("M24 12 C19.5 19 17 23 17 27.5 A7 7 0 0 0 31 27.5 C31 23 28.5 19 24 12 Z", True),
    "seal": ("M24 14 V34 M14 24 H34", True),
    "consecration": ("M5 35 A19 6 0 1 0 43 35 A19 6 0 1 0 5 35 M14 35 A10 3 0 1 0 34 35 A10 3 0 1 0 14 35 M24 9 V27 M16.5 15 V25 M31.5 15 V25", False),
    "hoj": ("M14 6 H34 V17 H14 Z M24 17 V31 M24 34 L25.8 38 L30 38.4 L26.8 41.2 L27.8 45.4 L24 43.2 L20.2 45.4 L21.2 41.2 L18 38.4 L22.2 38 Z", False),
    "aura": ("M24 20 A4 4 0 1 0 24 28 A4 4 0 1 0 24 20 M24 13 A11 11 0 1 0 24 35 A11 11 0 1 0 24 13 M24 5 A19 19 0 0 1 43 24 M24 43 A19 19 0 0 1 5 24", False),
    "blessing": ("M24 42 V14 M24 14 L17 22 M24 14 L31 22 M14 30 H34 M24 6 V9", False),
    "drink": ("M19 6 H29 M21 6 V17 L12 36 A5 5 0 0 0 16.5 43 H31.5 A5 5 0 0 0 36 36 L27 17 V6 M15.5 30 H32.5", False),
}


def pt(r, deg, c=110):
    t = math.radians(deg - 90)
    return c + r * math.cos(t), c + r * math.sin(t)


def arc(r, a0, a1):
    x0, y0 = pt(r, a0)
    x1, y1 = pt(r, a1)
    return f"M{x0:.3f} {y0:.3f} A{r} {r} 0 {1 if a1 - a0 > 180 else 0} 1 {x1:.3f} {y1:.3f}"


def svg(body, box=220, size=256):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {box} {box}">{body}</svg>')


def stroke(d, w, cap="round"):
    return f'<path d="{d}" fill="none" stroke="#fff" stroke-width="{w}" stroke-linecap="{cap}" stroke-linejoin="round"/>'


def textures():
    t = {}
    for name, (d, framed) in GLYPHS.items():
        body = stroke(d, 2.4)
        if framed:
            body = f'<g opacity="0.55">{stroke(HEX, 2.2)}</g>' + body
        t["glyph_" + name] = svg(body, box=48, size=128)
    t["disc"] = svg(
        '<defs><radialGradient id="g" cx="50%" cy="38%" r="65%">'
        '<stop offset="0" stop-color="#1d2b3d"/><stop offset="1" stop-color="#080c13"/></radialGradient></defs>'
        '<circle cx="110" cy="110" r="72" fill="url(#g)"/>'
        '<circle cx="110" cy="110" r="66" fill="none" stroke="#ece6d6" stroke-opacity="0.13" stroke-width="1"/>')
    # soft dark backing so the thin rings stay readable on bright ground
    t["back"] = svg(
        '<defs><radialGradient id="g" cx="50%" cy="50%" r="50%">'
        '<stop offset="0.80" stop-color="#05080d" stop-opacity="0.62"/><stop offset="1" stop-color="#05080d" stop-opacity="0"/>'
        '</radialGradient></defs><circle cx="110" cy="110" r="110" fill="url(#g)"/>')
    t["disc_edge"] = svg('<circle cx="110" cy="110" r="72" fill="none" stroke="#fff" stroke-width="1.6"/>')
    t["ring_track"] = svg('<circle cx="110" cy="110" r="100" fill="none" stroke="#fff" stroke-width="2.5"/>')
    t["ring_fill"] = svg('<circle cx="110" cy="110" r="100" fill="none" stroke="#fff" stroke-width="3.2"/>')
    t["notch"] = svg('<path d="M110 8 L104.5 1 H115.5 Z" fill="#fff"/>')
    # pre-rendered per position so nothing has to be rotated in game
    for i, (a0, a1) in enumerate([(8, 112), (128, 232), (248, 352)], 1):
        t[f"stack{i}"] = svg(stroke(arc(86, a0, a1), 7))
    t["pulse"] = svg('<circle cx="110" cy="110" r="100" fill="none" stroke="#fff" stroke-width="6"/>'
                     '<circle cx="110" cy="110" r="100" fill="none" stroke="#fff" stroke-opacity="0.22" stroke-width="14"/>')
    t["burst"] = svg('<circle cx="110" cy="110" r="86" fill="none" stroke="#fff" stroke-width="6"/>')
    t["glow"] = svg(
        '<defs><radialGradient id="g" cx="50%" cy="50%" r="50%">'
        '<stop offset="0.55" stop-color="#fff" stop-opacity="0.22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>'
        '</radialGradient></defs><circle cx="110" cy="110" r="110" fill="url(#g)"/>')
    t["orb"] = svg('<circle cx="32" cy="32" r="29" fill="#0b111a"/>', box=64, size=64)
    t["orb_edge"] = svg('<circle cx="32" cy="32" r="29" fill="none" stroke="#fff" stroke-width="1.6"/>', box=64, size=64)
    return t


def read_png(path):
    """Minimal PNG reader: 8-bit RGBA, non-interlaced (what rsvg-convert writes)."""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, w, h = 8, b"", 0, 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and ctype == 6 and interlace == 0, (depth, ctype, interlace)
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride, rows, prev = w * 4, [], bytearray(w * 4)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, rows


def write_tga(path, w, h, rows, white):
    """Uncompressed 32-bit TGA, bottom-left origin (the classic layout), straight alpha."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    out = bytearray(header)
    for line in reversed(rows):
        for x in range(w):
            r, g, b, a = line[x * 4:x * 4 + 4]
            if white:               # keep edges clean: full white, alpha carries the shape
                r = g = b = 255
            out += bytes((b, g, r, a))
    open(path, "wb").write(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, source in textures().items():
            s, p = os.path.join(tmp, name + ".svg"), os.path.join(tmp, name + ".png")
            open(s, "w").write(source)
            subprocess.run(["rsvg-convert", s, "-o", p], check=True)
            w, h, rows = read_png(p)
            assert w == h and w & (w - 1) == 0, (name, w, h)
            write_tga(os.path.join(OUT, name + ".tga"), w, h, rows, white=name not in ("disc", "orb", "back"))
            print(f"{name}.tga {w}x{h}")


if __name__ == "__main__":
    sys.exit(main())
