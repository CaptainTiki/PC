#!/bin/bash
# TrenchBroom pipeline: layout -> dressing rules -> .map -> FuncGodot scene -> screenshots
#   tools/rebuild_tb.sh [seed]          regenerate the layout for a seed, then build + shoot
#   tools/rebuild_tb.sh <name>.map      skip generation (a hand-edited map), just build + shoot
set -e
cd $(cd "$(dirname "$0")/.." && pwd)
ARG=${1:-1337}
if [[ "$ARG" == *.map ]]; then
  MAP=$ARG
else
  python3 tools/mapgen.py "$ARG"
  python3 tools/export_map.py levels/tb/seed$ARG.json
  MAP=levels/tb/seed$ARG.map
fi
NAME=$(basename "$MAP" .map)
python3 tools/gen_tb_textures.py
timeout 300 tools/godot.sh --import >/dev/null 2>&1 || true
timeout 200 tools/godot.sh -s tools/build_tb_config.gd 2>&1 | grep -E "saved|SCRIPT" || true
timeout 300 tools/godot.sh -s tools/build_tb_level.gd -- "$MAP" 2>&1 | grep -E "saved|built|SCRIPT" || true
rm -f shots/${NAME}_*.png
QUIT_AFTER=3000 timeout 300 tools/render.sh --resolution 960x540 res://levels/tb/$NAME.tscn -- --capture 2>&1 | grep -c captured || true
python3 - "$NAME" <<'PY'
import sys, glob
from PIL import Image
lv = sys.argv[1]
fs = sorted(glob.glob(f"shots/{lv}_*.png"))
if fs:
    ims = [Image.open(f) for f in fs]; W, H = ims[0].size; cols = 2; rows = (len(ims) + 1) // 2
    s = Image.new("RGB", (W * cols, H * rows))
    for i, im in enumerate(ims): s.paste(im, ((i % cols) * W, (i // cols) * H))
    s.save(f"shots/contact_{lv}.png"); print("contact:", len(ims))
PY
