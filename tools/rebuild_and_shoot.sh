#!/bin/bash
# Full pipeline: textures -> import -> kit -> level -> screenshots -> contact sheet
set -e
cd /home/claude/collider
LEVEL=${1:-test_room}
rm -f shots/${LEVEL}_*.png
python3 tools/gen_textures.py
timeout 300 tools/godot.sh --import >/dev/null 2>&1 || true
timeout 200 tools/godot.sh -s tools/build_kit.gd 2>&1 | grep -E "kit saved|SCRIPT|Parse" || true
timeout 200 tools/godot.sh -s tools/build_level.gd -- levels/$LEVEL.txt 2>&1 | grep -E "saved|SCRIPT|Parse" || true
timeout 240 tools/render.sh --resolution 960x540 res://levels/$LEVEL.tscn -- --capture 2>&1 | grep -cE "captured" || true
python3 - "$LEVEL" <<'PY'
import sys, glob
from PIL import Image
lv = sys.argv[1]
fs = sorted(glob.glob(f"shots/{lv}_*.png"))
ims = [Image.open(f) for f in fs]
W, H = ims[0].size
cols = 2
rows = (len(ims) + 1) // 2
s = Image.new("RGB", (W * cols, H * rows))
for i, im in enumerate(ims):
    s.paste(im, ((i % cols) * W, (i // cols) * H))
s.save(f"shots/contact_{lv}.png")
print("contact:", len(ims))
PY
