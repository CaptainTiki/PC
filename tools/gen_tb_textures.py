"""Standalone PBR texture set for TrenchBroom / FuncGodot levels.

Reuses the kit tile generators in gen_textures.py (same palette, same dither)
but writes each tile as its own file, plus normal / roughness / emission maps
derived from the tile's pre-quantisation shade:

  art/textures/tb/<name>.png             albedo (64x64, nearest-filtered in game)
  art/textures/tb/<name>_normal.png      tangent-space normal from the shade height
  art/textures/tb/<name>_roughness.png   roughness (high in grime, low on raised metal)
  art/textures/tb/<name>_emission.png    only for glowing tiles
  art/textures/tb/_template.tres         material template FuncGodot clones per texture

TrenchBroom reads the .png files straight from the folder; FuncGodot builds a
StandardMaterial3D per texture name from the template + the suffixed maps.
Run: python3 tools/gen_tb_textures.py
"""
import importlib.util, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "textures", "tb")
os.makedirs(OUT, exist_ok=True)

# load gen_textures as a module (this also rebuilds the kit atlas, which is fine)
spec = importlib.util.spec_from_file_location("gt", os.path.join(ROOT, "tools", "gen_textures.py"))
gt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gt)
T = gt.T

# capture the shade (height) each tile hands to quant()
_cap = {}
_orig_quant = gt.quant
def _quant(shade, ramp, dither=0.55):
    h = np.clip(shade, 0, 1)
    _cap["h"] = h if "h" not in _cap else np.maximum(_cap["h"], h)
    return _orig_quant(shade, ramp, dither)
gt.quant = _quant

# name -> (generator, base roughness, metallic hint)   base roughness is modulated by height
SET = {
    "floor":        (gt.floor_concrete, 0.80),
    "floor_metal":  (gt.floor_metal,    0.55),
    "floor_grate":  (gt.floor_grate,    0.60),
    "ceiling":      (gt.ceiling,        0.85),
    "wall":         (gt.wall_upper,     0.65),
    "wall_lower":   (gt.wall_lower,     0.70),
    "wall_concrete":(gt.wall_concrete,  0.90),
    "wall_rust":    (gt.rust_plate,     0.85),
    "wall_cables":  (gt.wall_cables,    0.75),
    "wall_vent":    (gt.vent,           0.60),
    "wall_pipes":   (gt.pipe,           0.50),
    "hazard":       (gt.hazard,         0.70),
    "trim":         (gt.trim,           0.55),
    "beam":         (gt.beam,           0.60),
    "kick":         (gt.kick,           0.60),
    "chamfer":      (gt.chamfer,        0.60),
    "light_strip":  (gt.light_strip,    0.40),
    "door":         (gt.door,           0.55),
    "console":      (gt.console,        0.45),
    "warning_lamp": (gt.warning_lamp,   0.50),
    "gutter_glow":  (gt.gutter_glow,    0.60),
    "window":       (gt.window,         0.20),
}

def normal_from_height(h, strength=2.2):
    hx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    hy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    n = np.stack([-hx, -hy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    # Godot uses OpenGL-style normal maps (green = +Y up); our rows run downwards, so flip G
    n[..., 1] *= -1
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)

def save(name, arr):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name))

count = 0
for name, (fn, base_rough) in SET.items():
    _cap.clear()
    res = fn()
    rgb, emit = (res if isinstance(res, tuple) else (res, None))
    h = _cap.get("h", np.full((T, T), 0.5, np.float32))
    # quantise height a little so the normal map is as chunky as the albedo
    hq = np.round(h * 12) / 12
    save(f"{name}.png", rgb)
    save(f"{name}_normal.png", normal_from_height(hq))
    rough = base_rough + (0.5 - hq) * 0.35 + (gt.vnoise(4, octaves=2) - 0.5) * 0.12
    rough = np.clip(rough, 0.08, 1.0)
    r8 = (rough * 255).astype(np.uint8)
    save(f"{name}_roughness.png", np.stack([r8, r8, r8], axis=-1))
    if emit is not None and np.max(emit) > 0:
        save(f"{name}_emission.png", emit)
    count += 1

# material template: nearest filtering so the 64px tiles stay crisp, roughness map drives spec
with open(os.path.join(OUT, "_template.tres"), "w") as f:
    f.write("""[gd_resource type="StandardMaterial3D" format=3]

[resource]
metallic = 0.3
metallic_specular = 0.45
roughness = 1.0
roughness_texture_channel = 0
emission_enabled = false
emission_energy_multiplier = 2.5
normal_scale = 1.0
texture_filter = 2
""")

# preview sheet: albedo | normal | roughness per row
names = list(SET)
sheet = Image.new("RGB", (3 * (T * 2 + 4), len(names) * (T * 2 + 4)), (10, 10, 10))
for i, n in enumerate(names):
    for j, suf in enumerate(["", "_normal", "_roughness"]):
        im = Image.open(os.path.join(OUT, f"{n}{suf}.png")).convert("RGB").resize((T * 2, T * 2), Image.NEAREST)
        sheet.paste(im, (j * (T * 2 + 4), i * (T * 2 + 4)))
os.makedirs(os.path.join(ROOT, "shots"), exist_ok=True)
sheet.save(os.path.join(ROOT, "shots", "tb_textures_preview.png"))
print(f"tb textures: {count} -> {OUT}")
