"""Minimal dependency-free raster plotting: a 3x5 bitmap font, a line-drawing canvas, and a
PNG encoder built on `zlib` alone.

Why not matplotlib: the before/after graph is a REQUIRED artifact on every backend-only
performance PR (see tools/perf/README.md), so the tool that draws it has to run wherever a
contributor or an automated agent happens to be working, with no pip install and no system
packages. Everything here is Python standard library.

The font is uppercase-only on purpose -- it halves the glyph table for a chart whose entire
text content is titles, bucket names and numbers. `text()` upcases what it is given.
"""

import struct
import zlib

# 3x5 glyphs, five rows of three pixels each ('1' = ink). Small, but legible from scale 2 up.
_FONT = {
    "0": "111 101 101 101 111", "1": "010 110 010 010 111",
    "2": "111 001 111 100 111", "3": "111 001 111 001 111",
    "4": "101 101 111 001 001", "5": "111 100 111 001 111",
    "6": "111 100 111 101 111", "7": "111 001 001 001 001",
    "8": "111 101 111 101 111", "9": "111 101 111 001 111",
    "A": "111 101 111 101 101", "B": "110 101 110 101 110",
    "C": "111 100 100 100 111", "D": "110 101 101 101 110",
    "E": "111 100 111 100 111", "F": "111 100 111 100 100",
    "G": "111 100 101 101 111", "H": "101 101 111 101 101",
    "I": "111 010 010 010 111", "J": "001 001 001 101 111",
    "K": "101 101 110 101 101", "L": "100 100 100 100 111",
    "M": "101 111 111 101 101", "N": "110 101 101 101 101",
    "O": "111 101 101 101 111", "P": "111 101 111 100 100",
    "Q": "111 101 101 111 011", "R": "111 101 110 101 101",
    "S": "111 100 111 001 111", "T": "111 010 010 010 010",
    "U": "101 101 101 101 111", "V": "101 101 101 101 010",
    "W": "101 101 111 111 101", "X": "101 101 010 101 101",
    "Y": "101 101 010 010 010", "Z": "111 001 010 100 111",
    " ": "000 000 000 000 000", ".": "000 000 000 000 010",
    ",": "000 000 000 010 100", ":": "000 010 000 010 000",
    "-": "000 000 111 000 000", "+": "000 010 111 010 000",
    "/": "001 001 010 100 100", "%": "101 001 010 100 101",
    "(": "001 010 010 010 001", ")": "100 010 010 010 100",
    "_": "000 000 000 000 111", "=": "000 111 000 111 000",
    "#": "101 111 101 111 101", "*": "000 101 010 101 000",
    "?": "111 001 011 000 010", "!": "010 010 010 000 010",
}
_UNKNOWN = "111 101 101 101 111"

GLYPH_W, GLYPH_H = 3, 5


def text_width(s, scale=1, spacing=1):
    """Pixel width of `s` rendered at `scale`, including inter-glyph spacing."""
    if not s:
        return 0
    return len(s) * (GLYPH_W + spacing) * scale - spacing * scale


class Canvas:
    """An RGB pixel buffer with just enough drawing to make a line chart."""

    def __init__(self, width, height, background=(255, 255, 255)):
        self.w = width
        self.h = height
        self.px = bytearray(bytes(background) * (width * height))

    def set(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 3
            self.px[i:i + 3] = bytes(color)

    def rect(self, x0, y0, x1, y1, color):
        """Filled rectangle, inclusive of both corners."""
        for y in range(max(0, y0), min(self.h, y1 + 1)):
            for x in range(max(0, x0), min(self.w, x1 + 1)):
                self.set(x, y, color)

    def hline(self, x0, x1, y, color):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.set(x, y, color)

    def vline(self, x, y0, y1, color):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, y, color)

    def line(self, x0, y0, x1, y1, color, weight=1):
        """Bresenham segment; `weight` > 1 thickens it into a small square brush."""
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            if weight <= 1:
                self.set(x0, y0, color)
            else:
                half = weight // 2
                for oy in range(-half, weight - half):
                    for ox in range(-half, weight - half):
                        self.set(x0 + ox, y0 + oy, color)
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def text(self, x, y, s, color, scale=1, spacing=1):
        """Draw `s` with its top-left at (x, y). Lowercase is upcased by the font."""
        cursor = x
        for ch in s.upper():
            rows = _FONT.get(ch, _UNKNOWN).split()
            for ry, row in enumerate(rows):
                for rx, bit in enumerate(row):
                    if bit == "1":
                        self.rect(cursor + rx * scale, y + ry * scale,
                                  cursor + (rx + 1) * scale - 1, y + (ry + 1) * scale - 1, color)
            cursor += (GLYPH_W + spacing) * scale
        return cursor

    def text_centered(self, cx, y, s, color, scale=1):
        self.text(cx - text_width(s, scale) // 2, y, s, color, scale)

    def to_png(self):
        """Encode as a PNG byte string (filter type 0 on every row, one zlib stream)."""
        raw = bytearray()
        stride = self.w * 3
        for y in range(self.h):
            raw.append(0)
            raw += self.px[y * stride:(y + 1) * stride]

        def chunk(tag, data):
            out = struct.pack(">I", len(data)) + tag + data
            return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

        header = struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0)
        return (b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", header)
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                + chunk(b"IEND", b""))

    def save(self, path):
        with open(path, "wb") as f:
            f.write(self.to_png())
