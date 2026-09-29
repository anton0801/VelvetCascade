#!/usr/bin/env python3
"""Контактный лист скриншотов: scripts/contact_sheet.py <dir> <out.png> [cols] [start] [count]"""
import sys, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 6
start = int(sys.argv[4]) if len(sys.argv) > 4 else 0
count = int(sys.argv[5]) if len(sys.argv) > 5 else 999
files = sorted(f for f in os.listdir(d) if f.endswith('.png'))[start:start + count]
tw = 300
ims = []
for f in files:
    im = Image.open(os.path.join(d, f)).convert('RGB')
    im.thumbnail((tw, tw * 3))
    ims.append((f, im))
th = max(im.height for _, im in ims) + 20
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * (tw + 8), rows * th), (0, 0, 0))
dr = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(ims):
    x, y = (i % cols) * (tw + 8), (i // cols) * th
    sheet.paste(im, (x, y + 18))
    dr.text((x + 4, y + 2), f[:-4], fill=(255, 220, 120))
sheet.save(out)
print(out, len(ims))
