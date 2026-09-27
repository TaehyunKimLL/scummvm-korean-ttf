#!/usr/bin/env python3
"""mkfont.py: a Unicode (version 2, cmap) SVFN with Thai combining marks.

FONT_FORMAT.md section 3: with flags bit 2, a combining mark (Mn/Me) is
stored with the pen at max(0, -bearingX) so its ink, left of the pen, is not
clipped, and bearingX keeps its true (negative) value; its advance is 0.

  python3 -m unittest scripts/test_mkfont.py      (from the docs repo)

Needs Pillow and a Thai face with zero-advance marks: $THAI_TTF, else the
C11 sample face (sukhumvit-text.ttf); skipped when neither is there.
"""

import os
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MKFONT = os.path.join(HERE, "mkfont.py")
THAI = os.environ.get("THAI_TTF",
                      "/Users/juami/work/scummvm/runs/c11/data/fonts/sukhumvit-text.ttf")


def read_svfn(path):
    with open(path, "rb") as fh:
        d = fh.read()
    magic, version, flags, bpp = struct.unpack_from("<4sHHB", d, 0)
    count, cw, ch, ascent = struct.unpack_from("<HBBB", d, 12)
    metrics_off, data_off, data_size = struct.unpack_from("<III", d, 20)
    cmap_off = struct.unpack_from("<I", d, 32)[0] if version >= 2 else 0
    cmap = {}
    for i in range(count if cmap_off else 0):
        cp, idx = struct.unpack_from("<II", d, cmap_off + i * 8)
        cmap[cp] = idx
    metrics = []
    for i in range(count if metrics_off else 0):
        metrics.append(struct.unpack_from("<BbBB", d, metrics_off + i * 4))
    stride = cw * ch if bpp == 8 else ((cw + 7) // 8) * ch
    glyphs = [d[data_off + i * stride: data_off + (i + 1) * stride] for i in range(count)]
    return dict(magic=magic, version=version, flags=flags, bpp=bpp, count=count, cw=cw, ascent=ascent,
                ch=ch, cmap=cmap, metrics=metrics, glyphs=glyphs)


def ink_columns(g, cw, ch):
    cols = [x for x in range(cw) if any(g[y * cw + x] >= 64 for y in range(ch))]
    return (min(cols), max(cols)) if cols else None


@unittest.skipUnless(os.path.exists(THAI), "no Thai face (set THAI_TTF)")
class ThaiSvfn(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.out = os.path.join(cls.tmp, "thai24.fnt")
        subprocess.run([sys.executable, MKFONT, THAI, cls.out, "--size", "24", "--bpp", "8",
                        "--unicode", "0E01-0E3A,0E40-0E4E,0020-007E"], check=True,
                       stdout=subprocess.DEVNULL)
        cls.f = read_svfn(cls.out)

    def test_version_2_with_cmap_and_bit_2(self):
        f = self.f
        self.assertEqual(f["magic"], b"SVFN")
        self.assertEqual(f["version"], 2)
        self.assertTrue(f["flags"] & 1)          # proportional
        self.assertTrue(f["flags"] & 4)          # marks stored at their origin
        self.assertIn(0x0E17, f["cmap"])
        self.assertIn(0x0E48, f["cmap"])
        self.assertIn(ord("A"), f["cmap"])

    def test_mark_keeps_its_ink_and_negative_bearing(self):
        f = self.f
        for cp in (0x0E48, 0x0E35, 0x0E38):      # tone mark, upper vowel, lower vowel
            i = f["cmap"][cp]
            adv, bearing, ink_w, _ = f["metrics"][i]
            self.assertEqual(adv, 0, hex(cp))
            self.assertLess(bearing, 0, hex(cp))
            ink = ink_columns(f["glyphs"][i], f["cw"], f["ch"])
            self.assertIsNotNone(ink, hex(cp))
            pen = min(-bearing, f["cw"])
            # The ink lies left of the pen, from column 0, and is whole: the
            # stored width is what the face draws.
            self.assertLess(ink[0], pen, hex(cp))
            self.assertGreaterEqual(ink[1] - ink[0] + 1, ink_w - 1, hex(cp))

    def test_composed_marks_land_where_the_face_puts_them(self):
        # Place "ที่" the way the engine does (SvfnGlyphSource originX =
        # -bearingX for a mark; I18N_TEXT_DESIGN.md 4.2): base at pen 0, each
        # mark at the pen after the base minus originX. Its ink columns must
        # match the face's own rendering of the string (Pillow, no shaping).
        from PIL import Image, ImageDraw, ImageFont
        f = self.f
        cw, chh = f["cw"], f["ch"]
        canvas = Image.new("L", (cw * 3, chh), 0)
        pen = 0
        anchor = 0
        for cp in (0x0E17, 0x0E35, 0x0E48):
            i = f["cmap"][cp]
            adv, bearing, ink_w, _ = f["metrics"][i]
            cell = Image.frombytes("L", (cw, chh), f["glyphs"][i])
            if adv == 0 and bearing < 0:
                x = anchor - min(-bearing, cw)
            else:
                x = pen
                anchor = pen + adv
                pen += adv
            canvas.paste(cell, (x + cw, 0), cell)
        font = ImageFont.truetype(THAI, 24)
        ref = Image.new("L", (cw * 3, chh), 0)
        ascent = f["ascent"]
        ImageDraw.Draw(ref).text((cw, ascent), "\u0e17\u0e35\u0e48", font=font, fill=255, anchor="ls")
        a = canvas.point(lambda v: 255 if v >= 128 else 0).getbbox()
        b = ref.point(lambda v: 255 if v >= 128 else 0).getbbox()
        self.assertIsNotNone(a)
        for k in range(4):
            self.assertLessEqual(abs(a[k] - b[k]), 1, (a, b))

    def test_base_is_unchanged_by_bit_2(self):
        f = self.f
        i = f["cmap"][0x0E17]
        adv, bearing, ink_w, _ = f["metrics"][i]
        self.assertGreater(adv, 0)
        self.assertGreaterEqual(bearing, 0)
        self.assertGreater(ink_w, 0)


if __name__ == "__main__":
    unittest.main()
