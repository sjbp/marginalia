#!/usr/bin/env python3
"""Marginalia brand mark: a text column with a note in the margin.
Three text strokes, a hairline column edge, a short connector, and one solid note.
Generates the macOS icon (.icns), an SVG of the bare mark, and a 2x PNG. Pure Python, no dependencies.
Usage: Scripts/make-icon.py [out-dir]   (default: Resources)"""
import os, struct, subprocess, sys, zlib, tempfile

CANVAS = (247, 246, 243)   # warm paper
INK = (26, 26, 26)         # text strokes
RULE = (186, 186, 186)     # column edge
NOTE = (74, 37, 170)       # the margin note

# Geometry in unit coordinates (0..1 of the icon). Tuned so the mark reads at 16 px and at 1024 px.
STROKES = [(0.21, 0.330, 0.34, 0.052), (0.21, 0.474, 0.27, 0.052), (0.21, 0.618, 0.31, 0.052)]  # x, y, w, h
RULE_X, RULE_Y0, RULE_Y1, RULE_W = 0.610, 0.285, 0.715, 0.012
CONNECTOR = (0.622, 0.494, 0.055, 0.012)
NOTE_RECT = (0.683, 0.432, 0.118, 0.136)

def rrect_cov(px, py, x, y, w, h, r):
    """1 if the sample point is inside the rounded rect."""
    if px < x or px > x + w or py < y or py > y + h: return False
    qx = max(x + r - px, 0, px - (x + w - r)); qy = max(y + r - py, 0, py - (y + h - r))
    return qx * qx + qy * qy <= r * r

def render(S, squircle=True, ss=3):
    pad = S * 0.09 if squircle else 0
    R = S * 0.205
    inner = (pad, pad, S - pad, S - pad)
    rows = []
    for y in range(S):
        row = bytearray()
        for x in range(S):
            acc = [0, 0, 0, 0]
            for sy in range(ss):
                for sx in range(ss):
                    px = x + (sx + 0.5) / ss; py = y + (sy + 0.5) / ss
                    if squircle:
                        qx = max(inner[0] + R - px, 0, px - (inner[2] - R)); qy = max(inner[1] + R - py, 0, py - (inner[3] - R))
                        if px < inner[0] or px > inner[2] or py < inner[1] or py > inner[3] or qx * qx + qy * qy > R * R: continue
                        c = CANVAS
                    else:
                        c = None
                    u, v = px / S, py / S
                    hit = None
                    for (sx0, sy0, sw, sh) in STROKES:
                        if rrect_cov(u, v, sx0, sy0, sw, sh, sh / 2): hit = INK
                    if rrect_cov(u, v, RULE_X - RULE_W / 2, RULE_Y0, RULE_W, RULE_Y1 - RULE_Y0, RULE_W / 2): hit = RULE
                    cx, cy, cw, ch = CONNECTOR
                    if rrect_cov(u, v, cx, cy, cw, ch, ch / 2): hit = RULE
                    nx, ny, nw, nh = NOTE_RECT
                    if rrect_cov(u, v, nx, ny, nw, nh, nh * 0.22): hit = NOTE
                    if hit: c = hit
                    if c is None: continue
                    acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 255
            n = ss * ss
            if acc[3] == 0: row += bytes([0, 0, 0, 0])
            else:
                k = acc[3] / 255
                row += bytes([int(acc[0] / k), int(acc[1] / k), int(acc[2] / k), int(acc[3] / n)])
        rows.append(bytes(row))
    raw = b"".join(b"\x00" + r for r in rows)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")

def svg(size=96):
    def rect(x, y, w, h, r, fill): return f'<rect x="{x*size:.2f}" y="{y*size:.2f}" width="{w*size:.2f}" height="{h*size:.2f}" rx="{r*size:.2f}" fill="{fill}"/>'
    hexc = lambda c: "#%02X%02X%02X" % c
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}" role="img" aria-label="Marginalia">']
    for (x, y, w, h) in STROKES: parts.append(rect(x, y, w, h, h / 2, hexc(INK)))
    parts.append(rect(RULE_X - RULE_W / 2, RULE_Y0, RULE_W, RULE_Y1 - RULE_Y0, RULE_W / 2, hexc(RULE)))
    parts.append(rect(*CONNECTOR, CONNECTOR[3] / 2, hexc(RULE)))
    parts.append(rect(*NOTE_RECT, NOTE_RECT[3] * 0.22, hexc(NOTE)))
    parts.append('</svg>')
    return "\n".join(parts)

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    os.makedirs(os.path.join(out, "brand"), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "icon.iconset"); os.makedirs(iconset)
        for size, name in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]:
            open(os.path.join(iconset, f"icon_{name}.png"), "wb").write(render(size))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "AppIcon.icns")], check=True)
        open(os.path.join(out, "brand", "icon-512.png"), "wb").write(open(os.path.join(iconset, "icon_512x512.png"), "rb").read())
    open(os.path.join(out, "brand", "mark.svg"), "w").write(svg())
    open(os.path.join(out, "brand", "mark@2x.png"), "wb").write(render(256, squircle=False))
    print("wrote", os.path.join(out, "AppIcon.icns"), "and brand/")

if __name__ == "__main__": main()
