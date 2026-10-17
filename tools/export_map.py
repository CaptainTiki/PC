"""levels/tb/<name>.json (from mapgen.py) -> levels/tb/<name>.map  (Valve 220, TrenchBroom)

The layout is cells; this file is the *dressing rules* that turn cells into brushes.
Every rule writes into its own TrenchBroom layer so a hand edit can select-by-layer:

  floor      solid columns up to floor height; tops floor / floor_metal / floor_grate
  border     floor_grate strip along every wall and riser (hides the tiling seam)
  ceiling    solid columns down to ceiling height
  skirting   kick band at the base of every wall
  panel      wall panels, varied per run by hash (wall / wall_vent / wall_rust / wall_cables)
  cornice    chamfer band under every ceiling edge
  beam       ceiling beams across rooms every 4th row
  stairs     4 real steps per stair cell
  lamp       light_strip fixture under every light
  doorframe  posts + lintel narrowing a door cell to the Door scene's slab (1.5 m x 3.25 m)

Entities: info_player_start, light (Godot property names, FuncGodot applies them to an
OmniLight3D), prop_door (-> scenes/props/door.tscn).

Units: 32 per metre. 1 cell = 64 (2 m). Floor step 32 (1 m). Ceiling level 56 (1.75 m).
Run: python3 tools/export_map.py levels/tb/seed1337.json
"""
import json, math, os, sys

U = 32                     # quake units per metre
CELL = 64
LVL = 32                   # floor level step
LVC = 56                   # ceiling level step (taller rooms than the floor grid implies)
VOID, FLOOR, DOOR, LOCKED, STAIRS, LIFT, PIT, CATWALK = range(8)

def ceil_u(f, c): return f * LVL + (c - f) * LVC

# ---------------------------------------------------------------- brushes ----
def box(x0, y0, z0, x1, y1, z1, top, side=None, bottom=None):
    """Axis-aligned brush with per-face textures. Valve 220 axes; outward normals."""
    side = side or top; bottom = bottom or top
    faces = [
        (((x1, y0, z1), (x0, y0, z1), (x0, y1, z1)), top,    "[ 1 0 0 0 ] [ 0 -1 0 0 ]"),  # +z
        (((x0, y1, z0), (x0, y0, z0), (x1, y0, z0)), bottom, "[ 1 0 0 0 ] [ 0 -1 0 0 ]"),  # -z
        (((x1, y1, z0), (x1, y0, z0), (x1, y0, z1)), side,   "[ 0 1 0 0 ] [ 0 0 -1 0 ]"),  # +x
        (((x0, y0, z1), (x0, y0, z0), (x0, y1, z0)), side,   "[ 0 1 0 0 ] [ 0 0 -1 0 ]"),  # -x
        (((x0, y1, z1), (x0, y1, z0), (x1, y1, z0)), side,   "[ 1 0 0 0 ] [ 0 0 -1 0 ]"),  # +y
        (((x1, y0, z1), (x1, y0, z0), (x0, y0, z0)), side,   "[ 1 0 0 0 ] [ 0 0 -1 0 ]"),  # -y
    ]
    out = ["{"]
    for pts, tex, axes in faces:
        out.append(" ".join(f"( {a:g} {b:g} {c:g} )" for a, b, c in pts) + f" {tex} {axes} 0 1 1")
    out.append("}")
    return "\n".join(out)

def merge_rects(cells):
    cells = set(cells); rects = []
    while cells:
        x0, y0 = min(cells, key=lambda p: (p[1], p[0])); x1 = x0
        while (x1 + 1, y0) in cells: x1 += 1
        y1 = y0
        while all((x, y1 + 1) in cells for x in range(x0, x1 + 1)): y1 += 1
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): cells.discard((x, y))
        rects.append((x0, y0, x1 + 1, y1 + 1))
    return rects

def merge_runs(segs, max_len=99):
    segs = set(segs); runs = []
    while segs:
        k, i0 = min(segs); i1 = i0
        while (k, i1 + 1) in segs and i1 - i0 + 1 < max_len: i1 += 1
        for i in range(i0, i1 + 1): segs.discard((k, i))
        runs.append((k, i0, i1 + 1))
    return runs

def hash01(a, b):
    h = (a * 374761393 + b * 668265263) ^ 0x5bd1e995
    h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
    return ((h ^ (h >> 16)) & 0xffffffff) / 4294967296.0

# ---------------------------------------------------------------- build ----
def build(level):
    H = level["height"]
    cells = {(c["x"], c["y"]): c for c in level["cells"]}
    at = cells.get
    fmin = min(c["f"] for c in cells.values()) - 1
    cmax = max(ceil_u(c["f"], c["c"]) for c in cells.values()) + 2 * LVL
    base = fmin * LVL - 16
    top = cmax + 16
    def Y(y): return (H - y) * CELL          # flip rows so the map reads like the PNG
    layers = {k: [] for k in ["floor", "border", "ceiling", "skirting", "panel", "cornice", "beam", "stairs", "lamp", "doorframe"]}
    ents = []
    room_of = {}
    for i, r in enumerate(level["rooms"]):
        for p in r["cells"]: room_of[tuple(p)] = i

    def floor_u(c): return c["f"] * LVL
    def ceil_of(c): return ceil_u(c["f"], c["c"])

    # --- floors: solid columns from base to the floor, grouped by (height, top texture)
    def floor_tex(c):
        if c["t"] == PIT: return "gutter_glow"
        if c["t"] == CATWALK: return "floor_grate"
        if (c["x"], c["y"]) not in room_of: return "floor_metal"     # corridors
        return "floor"
    groups = {}
    for (x, y), c in cells.items():
        if c["t"] == STAIRS: continue                                 # stairs get their own column below
        groups.setdefault((c["f"], floor_tex(c)), set()).add((x, y))
    for (f, tex), cs in groups.items():
        for x0, y0, x1, y1 in merge_rects(cs):
            layers["floor"].append(box(x0 * CELL, Y(y1), base, x1 * CELL, Y(y0), f * LVL, tex, "kick"))

    # --- ceilings: solid columns from the ceiling up
    groups = {}
    for (x, y), c in cells.items():
        groups.setdefault(ceil_of(c), set()).add((x, y))
    for cz, cs in groups.items():
        for x0, y0, x1, y1 in merge_rects(cs):
            layers["ceiling"].append(box(x0 * CELL, Y(y1), cz, x1 * CELL, Y(y0), top, "chamfer", "chamfer", "ceiling"))

    # --- walls on void edges: skirting (16u) + panel + cornice (16u), full base->top so the map seals
    # edge keys: direction -> set of (k, i) runs; panel texture chosen per run by hash
    E, W_, S, N = set(), set(), set(), set()
    for (x, y), c in cells.items():
        if (x + 1, y) not in cells: E.add((x, y))
        if (x - 1, y) not in cells: W_.add((x, y))
        if (x, y + 1) not in cells: S.add((y, x))
        if (x, y - 1) not in cells: N.add((y, x))
    def wall_run(x0, y0, x1, y1, floor_z, ceil_z, key):
        """x0..x1 / y0..y1 in quake units (thin box). Splits into skirting / panel / cornice."""
        t = hash01(*key)
        panel = "wall" if t < .55 else "wall_vent" if t < .72 else "wall_rust" if t < .86 else "wall_cables"
        layers["skirting"].append(box(x0, y0, base, x1, y1, floor_z + 16, "kick"))
        layers["panel"].append(box(x0, y0, floor_z + 16, x1, y1, ceil_z - 16, panel))
        layers["cornice"].append(box(x0, y0, ceil_z - 16, x1, y1, top, "chamfer"))
    def edge_runs(segs, vertical):
        # runs of cells sharing floor and ceiling so the bands line up; max 3 cells so panels vary
        out = []
        for k, i0, i1 in merge_runs(segs, 1):
            out.append((k, i0, i1))
        # group consecutive single segments with equal floor/ceil into runs up to 3
        out.sort(); runs = []; cur = None
        for k, i0, i1 in out:
            c = at((i0, k)) if not vertical else at((k, i0))
            fz, cz = floor_u(c), ceil_of(c)
            if cur and cur[0] == k and cur[2] == i0 and cur[3] == fz and cur[4] == cz and cur[2] - cur[1] < 3:
                cur[2] = i1
            else:
                if cur: runs.append(cur)
                cur = [k, i0, i1, fz, cz]
        if cur: runs.append(cur)
        return runs
    for x, y0, y1, fz, cz in edge_runs(E, True):
        wall_run((x + 1) * CELL, Y(y1), (x + 1) * CELL + 16, Y(y0), fz, cz, (x + 1, y0))
    for x, y0, y1, fz, cz in edge_runs(W_, True):
        wall_run(x * CELL - 16, Y(y1), x * CELL, Y(y0), fz, cz, (x - 1, y0))
    for y, x0, x1, fz, cz in edge_runs(S, False):
        wall_run(x0 * CELL, Y(y + 1) - 16, x1 * CELL, Y(y + 1), fz, cz, (x0, y + 1))
    for y, x0, x1, fz, cz in edge_runs(N, False):
        wall_run(x0 * CELL, Y(y), x1 * CELL, Y(y) + 16, fz, cz, (x0, y - 1))

    # --- border grate strips along walls and risers (12u wide, 2u tall on the floor)
    for (x, y), c in cells.items():
        if c["t"] in (PIT, CATWALK, STAIRS): continue
        fz = floor_u(c); X, Z0, Z1 = x * CELL, Y(y + 1), Y(y)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            o = at((x + dx, y + dy))
            if o and floor_u(o) <= fz: continue
            if dx == 1: layers["border"].append(box(X + CELL - 12, Z0, fz, X + CELL, Z1, fz + 2, "floor_grate"))
            if dx == -1: layers["border"].append(box(X, Z0, fz, X + 12, Z1, fz + 2, "floor_grate"))
            if dy == 1: layers["border"].append(box(X, Z0, fz, X + CELL, Z0 + 12, fz + 2, "floor_grate"))
            if dy == -1: layers["border"].append(box(X, Z1 - 12, fz, X + CELL, Z1, fz + 2, "floor_grate"))

    # --- beams every 4th row inside rooms where the ceiling is continuous
    for (x, y), c in cells.items():
        if y % 4 or c["t"] != FLOOR or (x, y) not in room_of: continue
        e, w = at((x + 1, y)), at((x - 1, y))
        if not (e or w) or (e and e["c"] != c["c"]) or (w and w["c"] != c["c"]): continue
        cz = ceil_of(c)
        if cz - floor_u(c) < 2.4 * U: continue
        zc = Y(y + 1) + CELL / 2
        layers["beam"].append(box(x * CELL, zc - 6, cz - 14, (x + 1) * CELL, zc + 6, cz, "beam"))

    # --- stairs: 4 steps rising from the lower neighbour's level to this cell's level
    for (x, y), c in cells.items():
        if c["t"] != STAIRS: continue
        f1 = floor_u(c); lower = None
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            o = at((x + dx, y + dy))
            if o and floor_u(o) < f1: lower = (dx, dy, floor_u(o)); break
        X, Z0, Z1 = x * CELL, Y(y + 1), Y(y)
        if not lower:
            layers["floor"].append(box(X, Z0, base, X + CELL, Z1, f1, "floor_metal", "kick")); continue
        dx, dy, f0 = lower; rise = (f1 - f0) / 4
        layers["floor"].append(box(X, Z0, base, X + CELL, Z1, f0, "floor_metal", "kick"))
        for i in range(4):
            h = f0 + rise * (i + 1); run = CELL / 4
            if dx == 1:   layers["stairs"].append(box(X + CELL - run * (i + 1), Z0, f0, X + CELL, Z1, h, "floor_metal", "kick"))
            if dx == -1:  layers["stairs"].append(box(X, Z0, f0, X + run * (i + 1), Z1, h, "floor_metal", "kick"))
            if dy == 1:   layers["stairs"].append(box(X, Z0, f0, X + CELL, Z0 + run * (i + 1), h, "floor_metal", "kick"))   # lower is south (screen down)
            if dy == -1:  layers["stairs"].append(box(X, Z1 - run * (i + 1), f0, X + CELL, Z1, h, "floor_metal", "kick"))

    # --- lights + lamp fixtures. Small rooms: one ceiling light. Big rooms: a 4-cell grid of
    #     pendants hung down to 4.5 m above the floor so the light reaches the deck.
    def light(cx, cz, z, energy, rng_, color="255 230 194", ceiling=None):
        ents.append(f'"classname" "light"\n"origin" "{cx:g} {cz:g} {z:g}"\n"light_color" "{color}"\n"light_energy" "{energy}"\n"omni_range" "{rng_}"')
        layers["lamp"].append(box(cx - 16, cz - 16, z + 12, cx + 16, cz + 16, z + 16, "light_strip", "trim"))
        if ceiling is not None and ceiling > z + 16:
            layers["lamp"].append(box(cx - 2, cz - 2, z + 16, cx + 2, cz + 2, ceiling, "trim"))   # pendant rod
    for r in level["rooms"]:
        cs = [tuple(p) for p in r["cells"] if tuple(p) in cells]
        cz = ceil_u(r["floor"], r["ceil"]); fz = r["floor"] * LVL
        hang = min(cz - 20, fz + int(4.5 * U))
        if len(cs) <= 80:
            cx = sum(p[0] for p in cs) / len(cs) + .5; cy = sum(p[1] for p in cs) / len(cs) + .5
            light(cx * CELL, Y(cy), hang, 5.0, 14, "255 230 194", cz)
        else:
            for p in cs:
                if p[0] % 4 == 2 and p[1] % 4 == 2 and cells[p]["t"] != PIT:
                    light((p[0] + .5) * CELL, Y(p[1] + .5), hang, 4.5, 12, "255 230 194", cz)
    for (x, y), c in cells.items():
        if (x, y) in room_of or c["t"] not in (FLOOR, DOOR) or (x + y) % 4: continue
        light((x + .5) * CELL, Y(y + .5), ceil_of(c) - 20, 3.0, 9, "140 230 255")

    # --- doors: frame to the Door scene's slab (1.5 m x 3.25 m) + prop_door entity
    for d in level["doors"]:
        x, y = d["x"], d["y"]; c = cells[(x, y)]
        ew = at((x + 1, y)) and at((x - 1, y)); ns = at((x, y + 1)) and at((x, y - 1))
        if ew == ns: continue
        fz, cz = floor_u(c), ceil_of(c); X, Z0, Z1 = x * CELL, Y(y + 1), Y(y)
        lint = fz + int(3.3 * U); post = int(.25 * U)         # 1.5 m opening
        if ew:   # corridor runs E-W: door slab lies in the y-z plane, posts at the z edges
            layers["doorframe"].append(box(X + 24, Z0, fz, X + 40, Z0 + post, cz, "trim"))
            layers["doorframe"].append(box(X + 24, Z1 - post, fz, X + 40, Z1, cz, "trim"))
            layers["doorframe"].append(box(X + 24, Z0, lint, X + 40, Z1, cz, "trim"))
            angle = 0
        else:
            layers["doorframe"].append(box(X, Z0 + 24, fz, X + post, Z0 + 40, cz, "trim"))
            layers["doorframe"].append(box(X + CELL - post, Z0 + 24, fz, X + CELL, Z0 + 40, cz, "trim"))
            layers["doorframe"].append(box(X, Z0 + 24, lint, X + CELL, Z0 + 40, cz, "trim"))
            angle = 90
        ents.append(f'"classname" "prop_door"\n"origin" "{X + 32:g} {Z0 + 32:g} {fz:g}"\n"angle" "{angle}"\n"lock" "{"jammed" if d["locked"] else "none"}"')

    # --- player start: the floor cell nearest room 1's centre, at that cell's own floor height
    r1 = level["rooms"][1]; cs = [tuple(p) for p in r1["cells"] if tuple(p) in cells and cells[tuple(p)]["t"] == FLOOR]
    mx = sum(p[0] for p in cs) / len(cs) + .5; my = sum(p[1] for p in cs) / len(cs) + .5
    sc = min(cs, key=lambda p: abs(p[0] + .5 - mx) + abs(p[1] + .5 - my))
    cx, cy = sc[0] + .5, sc[1] + .5
    hub = level["rooms"][0]; hcs = [tuple(p) for p in hub["cells"] if tuple(p) in cells]
    hx = sum(p[0] for p in hcs) / len(hcs) + .5; hy = sum(p[1] for p in hcs) / len(hcs) + .5
    ang = math.degrees(math.atan2(Y(hy) - Y(cy), (hx - cx) * CELL))
    ents.append(f'"classname" "info_player_start"\n"origin" "{cx * CELL:g} {Y(cy):g} {floor_u(cells[sc]) + 4:g}"\n"angle" "{ang:.0f}"')

    # screenshot markers: stand at the edge of a room, look at its centre
    def shot(name, r):
        rc = [tuple(p) for p in r["cells"] if tuple(p) in cells and cells[tuple(p)]["t"] in (FLOOR, CATWALK)]
        if not rc: return
        mx = sum(p[0] for p in rc) / len(rc) + .5; my = sum(p[1] for p in rc) / len(rc) + .5
        sx, sy = max(rc, key=lambda p: abs(p[0] + .5 - mx) + abs(p[1] + .5 - my))      # farthest floor cell
        sx += .5; sy += .5
        ang = math.degrees(math.atan2(Y(my) - Y(sy), (mx - sx) * CELL))
        sf = cells[(int(sx), int(sy))]["f"]
        ents.append(f'"classname" "shot"\n"origin" "{sx * CELL:g} {Y(sy):g} {sf * LVL + int(1.6 * U):g}"\n"angle" "{ang:.0f}"\n"shot_name" "{name}"')
    shot("hub", hub)
    for i in (1, 2, 5, 8):
        if i < len(level["rooms"]): shot(level["rooms"][i]["name"], level["rooms"][i])
    return layers, ents

CHUNK = 4 * CELL     # 8 m tiles: each becomes its own mesh so the renderer's per-mesh light cap is local

def _chunk_of(brush):
    """(cx, cy) of a brush from its first plane point (min corner-ish)."""
    import re
    pts = [tuple(float(v) for v in m) for m in re.findall(r"\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s*\)", brush)]
    x = min(p[0] for p in pts); y = min(p[1] for p in pts)
    return (int(x // CHUNK), int(y // CHUNK))

def write_map(layers, ents, path, name):
    out = ["// Game: Collider", "// Format: Valve", "{", '"classname" "worldspawn"', '"mapversion" "220"', f'"message" "{name}"', "}"]
    lid = 0
    for lname, brushes in layers.items():
        if not brushes: continue
        lid += 1
        out += ["{", '"classname" "func_group"', '"_tb_type" "_tb_layer"', f'"_tb_name" "{lname}"', f'"_tb_id" "{lid}"', "}"]
        chunks = {}
        for b in brushes: chunks.setdefault(_chunk_of(b), []).append(b)
        for (cx, cy), bs in sorted(chunks.items()):
            out += ["{", '"classname" "func_detail"', f'"_tb_layer" "{lid}"', f'"_chunk" "{lname}_{cx}_{cy}"']
            out += bs; out.append("}")
    for props in ents:
        out += ["{", props, "}"]
    open(path, "w").write("\n".join(out) + "\n")
    return sum(len(b) for b in layers.values())

if __name__ == "__main__":
    src = sys.argv[1]
    level = json.load(open(src))
    name = os.path.splitext(os.path.basename(src))[0]
    layers, ents = build(level)
    dst = os.path.join(os.path.dirname(src), name + ".map")
    n = write_map(layers, ents, dst, name)
    print(f"{n} brushes in {sum(1 for v in layers.values() if v)} layers, {len(ents)} entities -> {dst}")
