extends SceneTree
## Builds the modular grid kit -> res://kit/kit.meshlib.res
## Run: godot --headless --path . -s tools/build_kit.gd
##
## GRID RULES (the whole point of this kit):
##   * Cell = 2m (x) * 4m (y) * 2m (z). GridMap cell_size = (2,4,2), center_y = false.
##   * Every piece lives strictly inside its cell: x,z in [-1,1], y in [0,4].
##   * Walls are single-sided PROFILE pieces, not solid blocks. The visible face sits
##     0.75m back from the room-side cell edge (z = +0.25 local) and the profile
##     (gutter -> kick -> face -> chamfer) lands exactly on floor (y=0) and ceiling
##     (y=4) height at the cell edge, so it meets any neighbouring floor cell.
##     Nothing that can't be seen is drawn.
##   * Profile pieces are generated for every combination of open sides + inner
##     corners ("signature"); tools/build_level.gd picks the right one + rotation.
##     Hand-paint names: wall, wall_corner_in, wall_corner_out, wall_<feature>.
##   * Wall "features" (lights, vents, consoles...) are straight pieces facing +Z.
##   * Floor cells carry their own floor (y=0) and ceiling (y=4).

const ATLAS_META := "res://art/textures/tiles.json"
var meta: Dictionary
var tiles: Dictionary
var aw: float
var ah: float
var mat: Material

# ------------------------------------------------------------------ helpers --
func tile_uv(tile: String, u: float, v: float) -> Vector2:
	# u,v in 0..1 within the tile, v pointing UP (we flip for image space)
	var i: int = tiles[tile]
	var cols: int = meta.cols
	var cell: float = meta.cell
	var pad: float = meta.pad
	var t: float = meta.tile
	var cx := float(i % cols) * cell + pad
	var cy := float(i / cols) * cell + pad
	u = clampf(u, 0.0, 1.0)
	v = clampf(v, 0.0, 1.0)
	return Vector2((cx + u * t) / aw, (cy + (1.0 - v) * t) / ah)

func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		tile: String, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2) -> void:
	# a,b,c,d go around the quad. Winding is fixed up so the face points along n.
	var verts := [a, b, c, d]
	var uvs := [tile_uv(tile, uva.x, uva.y), tile_uv(tile, uvb.x, uvb.y), tile_uv(tile, uvc.x, uvc.y), tile_uv(tile, uvd.x, uvd.y)]
	var ccw := (b - a).cross(c - a).dot(n) > 0.0
	var order := [0, 2, 1, 0, 3, 2] if ccw else [0, 1, 2, 0, 2, 3]  # Godot front faces = clockwise
	for k in order:
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])

# A "side" of a wall block: outward normal n, right vector r (as seen from outside).
class Side:
	var n: Vector3
	var r: Vector3
	var base := 0.0     # depth of the plane this Side draws on, measured from the cell edge
	func _init(normal: Vector3, right: Vector3, b := 0.0) -> void:
		n = normal
		r = right
		base = b
	func p(s: float, y: float, depth: float) -> Vector3:
		return n * (1.0 - base - depth) + r * s + Vector3.UP * y

# wall profile (metres, depth measured from the room-side cell edge)
const GD := 0.55    # gutter: edge -> GD at floor level
const FD := 0.75    # face plane depth (face is at local +0.25)
const KH := 0.25    # kick plate top / face bottom
const CY := 3.25    # face top / chamfer start (chamfer lands on y=4 at the edge)
const DIRS := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]  # side index 0..3

var SIDE_F := Side.new(Vector3(0, 0, 1), Vector3(1, 0, 0))    # +Z (feature side)
var FACE_F := Side.new(Vector3(0, 0, 1), Vector3(1, 0, 0), FD) # +Z face plane
var SIDE_B := Side.new(Vector3(0, 0, -1), Vector3(-1, 0, 0))
var SIDE_R := Side.new(Vector3(1, 0, 0), Vector3(0, 0, -1))
var SIDE_L := Side.new(Vector3(-1, 0, 0), Vector3(0, 0, 1))

func side_rect(st: SurfaceTool, sd, s0: float, s1: float, y0: float, y1: float, depth: float,
		tile: String, u0: float, u1: float, v0: float, v1: float) -> void:
	quad(st, sd.p(s0, y0, depth), sd.p(s1, y0, depth), sd.p(s1, y1, depth), sd.p(s0, y1, depth), sd.n,
		tile, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))

func side_auto(st: SurfaceTool, sd, s0: float, s1: float, y0: float, y1: float, depth: float,
		lower: String, upper: String) -> void:
	# World-aligned mapping: lower 2m uses `lower`, upper 2m uses `upper`. Splits at y=2.
	if y1 <= y0 or s1 <= s0:
		return
	var u0 := (s0 + 1.0) / 2.0
	var u1 := (s1 + 1.0) / 2.0
	if y0 < 2.0:
		var ya := y0
		var yb := minf(y1, 2.0)
		side_rect(st, sd, s0, s1, ya, yb, depth, lower, u0, u1, ya / 2.0, yb / 2.0)
	if y1 > 2.0:
		var ya2 := maxf(y0, 2.0)
		var yb2 := y1
		side_rect(st, sd, s0, s1, ya2, yb2, depth, upper, u0, u1, (ya2 - 2.0) / 2.0, (yb2 - 2.0) / 2.0)

func plain_side(st: SurfaceTool, sd, lower: String, upper: String) -> void:
	side_auto(st, sd, -1, 1, 0, 4, 0, lower, upper)

func recess(st: SurfaceTool, sd, s0: float, s1: float, y0: float, y1: float, depth: float,
		lower: String, upper: String, back: String, edge: String,
		bu0 := 0.0, bu1 := 1.0, bv0 := 0.0, bv1 := 1.0) -> void:
	# front face (full height; trim covers top and bottom) with a rectangular hole
	side_auto(st, sd, -1, 1, 0.0, y0, 0, lower, upper)
	side_auto(st, sd, -1, 1, y1, 4.0, 0, lower, upper)
	side_auto(st, sd, -1, s0, y0, y1, 0, lower, upper)
	side_auto(st, sd, s1, 1, y0, y1, 0, lower, upper)
	# back panel
	side_rect(st, sd, s0, s1, y0, y1, depth, back, bu0, bu1, bv0, bv1)
	# inner walls of the hole (edge tile, depth maps to a thin strip of v)
	var dv := depth / 2.0
	var w := (s1 - s0) / 2.0
	var h := (y1 - y0) / 2.0
	# bottom sill (faces up)
	quad(st, sd.p(s0, y0, 0), sd.p(s1, y0, 0), sd.p(s1, y0, depth), sd.p(s0, y0, depth), Vector3.UP,
		edge, Vector2(0, 1), Vector2(w, 1), Vector2(w, 1 - dv), Vector2(0, 1 - dv))
	# top lintel (faces down)
	quad(st, sd.p(s0, y1, 0), sd.p(s1, y1, 0), sd.p(s1, y1, depth), sd.p(s0, y1, depth), Vector3.DOWN,
		edge, Vector2(0, 0), Vector2(w, 0), Vector2(w, dv), Vector2(0, dv))
	# left jamb (faces +r)
	quad(st, sd.p(s0, y0, 0), sd.p(s0, y0, depth), sd.p(s0, y1, depth), sd.p(s0, y1, 0), sd.r,
		edge, Vector2(0, 0), Vector2(dv, 0), Vector2(dv, h), Vector2(0, h))
	# right jamb (faces -r)
	quad(st, sd.p(s1, y0, 0), sd.p(s1, y0, depth), sd.p(s1, y1, depth), sd.p(s1, y1, 0), -sd.r,
		edge, Vector2(0, 0), Vector2(dv, 0), Vector2(dv, h), Vector2(0, h))

func box(st: SurfaceTool, mn: Vector3, mx: Vector3, tile_side: String, tile_top: String,
		tile_bottom := "", skip_top := false, split_tile := "", split_y := -1.0) -> void:
	# Axis-aligned box, UVs in metres/2 (keep sides <= 2m per face segment).
	var sx := (mx.x - mn.x) / 2.0
	var sz := (mx.z - mn.z) / 2.0
	var ys := [mn.y, mx.y]
	if split_y > mn.y and split_y < mx.y:
		ys = [mn.y, split_y, mx.y]
	for seg in range(ys.size() - 1):
		var y0: float = ys[seg]
		var y1: float = ys[seg + 1]
		var t := tile_side
		if seg == 0 and split_tile != "":
			t = split_tile
		var v0 := fmod(y0, 2.0) / 2.0
		var v1 := v0 + (y1 - y0) / 2.0
		if v1 > 1.0:
			v0 = 0.0
			v1 = minf((y1 - y0) / 2.0, 1.0)
		# +Z
		quad(st, Vector3(mn.x, y0, mx.z), Vector3(mx.x, y0, mx.z), Vector3(mx.x, y1, mx.z), Vector3(mn.x, y1, mx.z),
			Vector3.BACK, t, Vector2(0, v0), Vector2(sx, v0), Vector2(sx, v1), Vector2(0, v1))
		# -Z
		quad(st, Vector3(mx.x, y0, mn.z), Vector3(mn.x, y0, mn.z), Vector3(mn.x, y1, mn.z), Vector3(mx.x, y1, mn.z),
			Vector3.FORWARD, t, Vector2(0, v0), Vector2(sx, v0), Vector2(sx, v1), Vector2(0, v1))
		# +X
		quad(st, Vector3(mx.x, y0, mx.z), Vector3(mx.x, y0, mn.z), Vector3(mx.x, y1, mn.z), Vector3(mx.x, y1, mx.z),
			Vector3.RIGHT, t, Vector2(0, v0), Vector2(sz, v0), Vector2(sz, v1), Vector2(0, v1))
		# -X
		quad(st, Vector3(mn.x, y0, mn.z), Vector3(mn.x, y0, mx.z), Vector3(mn.x, y1, mx.z), Vector3(mn.x, y1, mn.z),
			Vector3.LEFT, t, Vector2(0, v0), Vector2(sz, v0), Vector2(sz, v1), Vector2(0, v1))
	if not skip_top:
		quad(st, Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z),
			Vector3.UP, tile_top, Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sz), Vector2(0, sz))
	if tile_bottom != "":
		quad(st, Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
			Vector3.DOWN, tile_bottom, Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sz), Vector2(0, sz))

func glow_box(st: SurfaceTool, mn: Vector3, mx: Vector3, tile := "light_strip", a := Vector2(0.3, 0.585), b := Vector2(0.4, 0.6)) -> void:
	# every face sampled from one small emissive patch -> solid glowing block
	var faces := [
		[Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3.BACK],
		[Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3.FORWARD],
		[Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3.RIGHT],
		[Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3.LEFT],
		[Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3.UP],
		[Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z), Vector3.DOWN]]
	for f in faces:
		quad(st, f[0], f[1], f[2], f[3], f[4], tile, a, Vector2(b.x, a.y), b, Vector2(a.x, b.y))

func cylinder_y(st: SurfaceTool, center: Vector3, radius: float, y0: float, y1: float, tile: String, segs := 8) -> void:
	for seg_y in [[y0, minf(y1, y0 + 2.0)], [y0 + 2.0, y1]]:
		var ya: float = seg_y[0]
		var yb: float = seg_y[1]
		if yb <= ya:
			continue
		var vv := (yb - ya) / 2.0
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var d0 := Vector3(sin(a0), 0, cos(a0))
			var d1 := Vector3(sin(a1), 0, cos(a1))
			var nn := (d0 + d1).normalized()
			quad(st, center + d0 * radius + Vector3.UP * ya, center + d1 * radius + Vector3.UP * ya,
				center + d1 * radius + Vector3.UP * yb, center + d0 * radius + Vector3.UP * yb, nn,
				tile, Vector2(float(i) / segs, 0), Vector2(float(i + 1) / segs, 0),
				Vector2(float(i + 1) / segs, vv), Vector2(float(i) / segs, vv))

func floor_face(st: SurfaceTool, tile: String) -> void:
	quad(st, Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1), Vector3.UP,
		tile, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

func ceiling_face(st: SurfaceTool, tile := "ceiling") -> void:
	quad(st, Vector3(-1, 4, -1), Vector3(1, 4, -1), Vector3(1, 4, 1), Vector3(-1, 4, 1), Vector3.DOWN,
		tile, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

func ceiling_with_panel(st: SurfaceTool, hx: float, hz: float, depth: float, panel_tile := "light_strip") -> void:
	# ceiling with a recessed glowing panel in the middle
	var rects := [[-1, 1, -1, 1]]
	for r in rects:
		var x0: float = r[0]; var x1: float = r[1]; var z0: float = r[2]; var z1: float = r[3]
		quad(st, Vector3(x0, 4, z0), Vector3(x1, 4, z0), Vector3(x1, 4, z1), Vector3(x0, 4, z1), Vector3.DOWN,
			"ceiling", Vector2((x0 + 1) / 2, (z0 + 1) / 2), Vector2((x1 + 1) / 2, (z0 + 1) / 2),
			Vector2((x1 + 1) / 2, (z1 + 1) / 2), Vector2((x0 + 1) / 2, (z1 + 1) / 2))
	# the fitting hangs below the ceiling (a recess would poke through the floor above)
	var y := 4.0 - depth
	quad(st, Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz), Vector3.DOWN,
		panel_tile, Vector2(0, 0.40), Vector2(1, 0.40), Vector2(1, 0.60), Vector2(0, 0.60))
	var dv := depth / 2.0
	for e in [[Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3.FORWARD], [Vector3(hx, y, hz), Vector3(-hx, y, hz), Vector3.BACK],
			[Vector3(-hx, y, hz), Vector3(-hx, y, -hz), Vector3.LEFT], [Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3.RIGHT]]:
		var a: Vector3 = e[0]; var b: Vector3 = e[1]
		quad(st, a, b, b + Vector3.UP * depth, a + Vector3.UP * depth, e[2],
			"trim", Vector2(0, 0), Vector2(1, 0), Vector2(1, dv), Vector2(0, dv))

# ----------------------------------------------------------------- pieces ----
func poly(st: SurfaceTool, pts: Array, n: Vector3, tile: String, uvs: Array) -> void:
	# convex polygon as a fan; degenerate triangles skipped, each wound to face n
	for k in range(1, pts.size() - 1):
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[k]
		var c: Vector3 = pts[k + 1]
		var cr := (b - a).cross(c - a)
		if cr.length() < 1e-6:
			continue
		var idx := [0, k + 1, k] if cr.dot(n) > 0.0 else [0, k, k + 1]
		for j in idx:
			st.set_normal(n)
			var uv: Vector2 = uvs[j]
			st.set_uv(tile_uv(tile, uv.x, uv.y))
			st.add_vertex(pts[j])

func side_of(i: int, base := 0.0):
	var n: Vector3 = DIRS[i]
	return Side.new(n, Vector3.UP.cross(n), base)

## s-extent of a profile strip at depth d. Modes: "full", "convex" (mitre round an
## outside corner), "concave" (the strip is just the corner wedge of an inside corner).
func s_lo(mode: String, d: float) -> float:
	match mode:
		"convex": return -(1.0 - d)
		"concave": return 1.0 - d
	return -1.0

func s_hi(mode: String, d: float) -> float:
	match mode:
		"convex": return 1.0 - d
		"concave": return -(1.0 - d)
	return 1.0

## Profile segments: [d0, y0, d1, y1, tile, normal_kind, v0, v1]
## normal_kind: "up", "down", "kick" (up + toward room), "chamfer" (down + toward room)
const G_Y := 0.02   # trim gutter floats this far above the structure's floor band
const SEG_FLOOR_BAND := [[0.0, 0.0, FD, 0.0, "kick", "up", 0.0, 0.375]]
const SEG_CEIL_BAND := [[FD, 4.0, 0.0, 4.0, "ceiling", "down", 0.0, 0.375]]
const SEG_GUTTER := [[0.0, G_Y, GD, G_Y, "gutter", "up", 0.0, 0.275], [GD, G_Y, FD, KH, "kick", "kick", 0.2, 0.55]]
const SEG_GUTTER_GLOW := [[0.0, G_Y, GD, G_Y, "gutter_glow", "up", 0.0, 0.275], [GD, G_Y, FD, KH, "kick", "kick", 0.2, 0.55]]
const SEG_CHAMFER := [[FD, CY, 0.0, 4.0, "chamfer", "chamfer", 0.47, 1.0]]

func seg_normal(sd, kind: String) -> Vector3:
	match kind:
		"up": return Vector3.UP
		"down": return Vector3.DOWN
		"kick": return (sd.n * KH + Vector3.UP * (FD - GD)).normalized()
		"chamfer": return (sd.n + Vector3.DOWN).normalized()
	return Vector3.UP

## One profile strip along side sd. segs: profile segments; y_off shifts the
## geometry (trim ceiling slot lives 2m up). face: null / "plain" / Callable.
func profile(st: SurfaceTool, sd, lo_m: String, hi_m: String, segs: Array, face = null, y_off := 0.0) -> void:
	var up := Vector3(0, y_off, 0)
	for g in segs:
		var d0: float = g[0]; var y0: float = g[1]; var d1: float = g[2]; var y1: float = g[3]
		var v0: float = g[6]; var v1: float = g[7]
		var a := [s_lo(lo_m, d0), s_hi(hi_m, d0)]
		var b := [s_lo(lo_m, d1), s_hi(hi_m, d1)]
		var pts := [sd.p(a[0], y0, d0) + up, sd.p(a[1], y0, d0) + up, sd.p(b[1], y1, d1) + up, sd.p(b[0], y1, d1) + up]
		var uvs := [Vector2((a[0] + 1) / 2, v0), Vector2((a[1] + 1) / 2, v0), Vector2((b[1] + 1) / 2, v1), Vector2((b[0] + 1) / 2, v1)]
		poly(st, pts, seg_normal(sd, g[5]), g[4], uvs)
	if face is Callable:
		face.call(st)
	elif face == "plain":
		var f = Side.new(sd.n, sd.r, FD)
		side_auto(st, f, s_lo(lo_m, FD), s_hi(hi_m, FD), 0.0, 4.0, 0, "wall_lower", "wall_upper")

func rot_mask(m: int, k: int) -> int:
	var out := 0
	for i in 4:
		if m & (1 << i):
			out |= 1 << ((i + k) % 4)
	return out

## Mesh for a signature: `sides` = open neighbours (bit i = DIRS[i]),
## `diag` = inside corners (bit i = corner between DIRS[i] and DIRS[i+1]).
## face: null (trim only), "plain", or a Callable used on the +Z straight side.
func wall_mesh(st: SurfaceTool, sides: int, diag: int, segs: Array, face = null, y_off := 0.0) -> void:
	for i in 4:
		if sides & (1 << i):
			var lo := "convex" if sides & (1 << ((i + 3) % 4)) else "full"
			var hi := "convex" if sides & (1 << ((i + 1) % 4)) else "full"
			var f = face
			if face is Callable and i != 0:
				f = "plain"
			profile(st, side_of(i), lo, hi, segs, f, y_off)
	for j in 4:
		if diag & (1 << j):
			var f2 = "plain" if face != null else null
			profile(st, side_of(j), "concave", "full", segs, f2, y_off)            # wedge at +s end of side j
			profile(st, side_of((j + 1) % 4), "full", "concave", segs, f2, y_off)  # wedge at -s end of side j+1

func wall_collision(sides: int, diag: int) -> Array:
	# 3x3 sub-cells split at the face planes (+-0.25). Room sub-cells get floor,
	# solid sub-cells get a full-height box. Rows are merged along X.
	var edges := [-1.0, -0.25, 0.25, 1.0]
	var room := []
	for zi in 3:
		var row := []
		for xi in 3:
			var r := false
			if zi == 2 and sides & 1: r = true          # +Z
			if xi == 2 and sides & 2: r = true          # +X
			if zi == 0 and sides & 4: r = true          # -Z
			if xi == 0 and sides & 8: r = true          # -X
			if xi == 2 and zi == 2 and diag & 1: r = true
			if xi == 2 and zi == 0 and diag & 2: r = true
			if xi == 0 and zi == 0 and diag & 4: r = true
			if xi == 0 and zi == 2 and diag & 8: r = true
			row.append(r)
		room.append(row)
	var shapes := []
	for zi in 3:
		var xi := 0
		while xi < 3:
			var kind: bool = room[zi][xi]
			var xe := xi
			while xe + 1 < 3 and room[zi][xe + 1] == kind:
				xe += 1
			var mn := Vector3(edges[xi], 0, edges[zi])
			var mx := Vector3(edges[xe + 1], 4, edges[zi + 1])
			if kind:
				shapes += shape_box(Vector3(mn.x, -0.5, mn.z), Vector3(mx.x, 0, mx.z))
			else:
				shapes += shape_box(mn, mx)
			xi = xe + 1
	return shapes

func canonical(sides: int, diag: int) -> Array:
	var best := [999, 0, 0]
	for k in 4:
		var s := rot_mask(sides, k)
		var d := rot_mask(diag, k)
		var key := s * 16 + d
		if key < best[0]:
			best = [key, s, d]
	return [best[1], best[2]]

func all_signatures() -> Array:
	var done := {}
	var sigs := []
	for sides in 16:
		for diag in 16:
			var ok := sides != 0 or diag != 0
			for j in 4:   # an inside corner only exists where both adjacent sides are closed
				if diag & (1 << j) and (sides & (1 << j) or sides & (1 << ((j + 1) % 4))):
					ok = false
			if not ok:
				continue
			var c := canonical(sides, diag)
			var key := "%d_%d" % [c[0], c[1]]
			if not done.has(key):
				done[key] = true
				sigs.append(c)
	sigs.sort_custom(func(a, b): return a[0] * 16 + a[1] < b[0] * 16 + b[1])
	return sigs

func sig_name(prefix: String, c: Array) -> String:
	var key := "%d_%d" % [c[0], c[1]]
	var named := {"1_0": "", "3_0": "_corner_out", "0_1": "_corner_in"}
	if named.has(key):
		return prefix + named[key]
	return "%s_auto_%s" % [prefix, key]

func build_walls() -> void:
	var sigs := all_signatures()
	# --- structure: wall faces + flat floor/ceiling bands (a hard, untrimmed edge) ---
	for c in sigs:
		var st := new_st()
		wall_mesh(st, c[0], c[1], [], "plain")
		add_item(lib_structure, sig_name("wall", c), finish(st), wall_collision(c[0], c[1]), "Wall face, open sides %d, inside corners %d" % [c[0], c[1]])
	var feats := [
		["wall_bulkhead", "Ribbed bulkhead face", func(st): side_auto(st, FACE_F, -1, 1, 0, 4, 0, "wall_concrete", "wall_concrete")],
		["wall_hazard", "Hazard stripes, lower face", func(st): side_auto(st, FACE_F, -1, 1, 0, 4, 0, "hazard", "wall_upper")],
		["wall_cables", "Cable run, upper face", func(st): side_auto(st, FACE_F, -1, 1, 0, 4, 0, "wall_lower", "wall_cables")],
		["wall_rust", "Rusted upper face", func(st): side_auto(st, FACE_F, -1, 1, 0, 4, 0, "wall_lower", "rust_plate")],
		["wall_light", "Recessed cyan light strip (bakes an OmniLight)", func(st): recess(st, FACE_F, -0.875, 0.875, 2.625, 3.125, 0.125, "wall_lower", "wall_upper", "light_strip", "trim", 0.0, 1.0, 0.36, 0.64)],
		["wall_light_off", "Wall light strip with no power (see Level power zones)", func(st): recess(st, FACE_F, -0.875, 0.875, 2.625, 3.125, 0.125, "wall_lower", "wall_upper", "kick", "trim", 0.0, 1.0, 0.1, 0.3)],
		["wall_vent", "Recessed floor-level vent", func(st): recess(st, FACE_F, -0.625, 0.625, 0.375, 1.5, 0.25, "wall_lower", "wall_upper", "vent", "trim")],
		["wall_console", "Recessed console screen (bakes dim light)", func(st): recess(st, FACE_F, -0.75, 0.75, 1.0, 2.5, 0.25, "wall_lower", "wall_upper", "console", "trim")],
		["wall_lamp", "Red warning lamp (bakes red OmniLight)", func(st): recess(st, FACE_F, -0.375, 0.375, 2.375, 3.125, 0.125, "wall_lower", "wall_upper", "warning_lamp", "trim")],
		["wall_pipes", "Deep pipe bay", func(st): _pipes(st)],
		["wall_window", "Deep-set window onto space (bakes faint light)", func(st): recess(st, FACE_F, -0.875, 0.875, 0.875, 3.0, 0.375, "wall_lower", "wall_upper", "window", "trim")],
	]
	for f in feats:
		var st := new_st()
		wall_mesh(st, 1, 0, [], f[2])
		add_item(lib_structure, f[0], finish(st), wall_collision(1, 0), f[1])

	# --- trim grid (cells 2m tall): slot y=0 floor trim, slot y=1 ceiling trim ---
	for fam in [["band_floor", SEG_FLOOR_BAND, 0.0, "Floor trim: plain flat floor strip (hard 90 degree edge)"],
			["band_ceil", SEG_CEIL_BAND, -2.0, "Ceiling trim (y=1 slot): plain flat ceiling strip (hard edge)"],
			["gutter", SEG_GUTTER, 0.0, "Floor trim: dark grating gutter + kick"],
			["gutter_glow", SEG_GUTTER_GLOW, 0.0, "Floor trim: gutter with glowing slots"],
			["chamfer", SEG_CHAMFER, -2.0, "Ceiling trim (paint in the y=1 slot): plain chamfer"]]:
		for c in sigs:
			var st := new_st()
			wall_mesh(st, c[0], c[1], fam[1], null, fam[2])
			add_item(lib_trim, sig_name(fam[0], c), finish(st), [], fam[3])
	# lit / broken chamfers: straight only, light bar sits on the chamfer
	for spec in [["chamfer_light", 1, "Ceiling trim: chamfer with light bar (bakes an OmniLight)"],
			["chamfer_light_broken", 0, "Ceiling trim: chamfer with a failing light bar (bakes a flickering light)"],
			["chamfer_light_off", 2, "Ceiling trim: light bar with no power (see Level power zones)"]]:
		var st := new_st()
		wall_mesh(st, 1, 0, SEG_CHAMFER, null, -2.0)
		light_bar(st, spec[1], -2.0)
		add_item(lib_trim, spec[0], finish(st), [], spec[2])

## Light bar on the +Z chamfer: housing + emissive face, 1.5m long.
func light_bar(st: SurfaceTool, mode: int, y_off: float) -> void:
	# mode 1 = lit, 0 = broken (one glowing segment), 2 = unpowered (dark)
	var lit := mode == 1
	var sd = SIDE_F
	var n: Vector3 = (sd.n + Vector3.DOWN).normalized()
	var up := Vector3(0, y_off, 0)
	# points on the chamfer plane at depth d: y = 4 - d (45 degrees)
	var on := func(s: float, d: float, lift: float) -> Vector3:
		return sd.p(s, 4.0 - d, d) + up + n * lift
	var d0 := 0.26
	var d1 := 0.5
	for layer in [[0.03, 0.75, d0, d1, "trim"], [0.05, 0.68, d0 + 0.04, d1 - 0.04, "light_strip" if lit else "kick"]]:
		var lift: float = layer[0]; var hw: float = layer[1]; var a: float = layer[2]; var b: float = layer[3]
		var t: String = layer[4]
		var uv := [Vector2(0.1, 0.45), Vector2(0.9, 0.45), Vector2(0.9, 0.55), Vector2(0.1, 0.55)]
		if t != "light_strip":
			uv = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.1), Vector2(0, 0.1)]
		poly(st, [on.call(-hw, a, lift), on.call(hw, a, lift), on.call(hw, b, lift), on.call(-hw, b, lift)], n, t, uv)
		# sides of the slab down to the chamfer
		var base := lift - 0.03
		for e in [[Vector2(-hw, a), Vector2(hw, a)], [Vector2(hw, a), Vector2(hw, b)], [Vector2(hw, b), Vector2(-hw, b)], [Vector2(-hw, b), Vector2(-hw, a)]]:
			var p0: Vector3 = on.call(e[0].x, e[0].y, lift)
			var p1: Vector3 = on.call(e[1].x, e[1].y, lift)
			var q0: Vector3 = on.call(e[0].x, e[0].y, base)
			var q1: Vector3 = on.call(e[1].x, e[1].y, base)
			var mid: Vector3 = (p0 + p1) * 0.5 - on.call(0.0, (a + b) * 0.5, lift)
			poly(st, [q0, q1, p1, p0], mid.normalized(), "trim", [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.3, 0.03), Vector2(0, 0.03)])
	if mode == 0:
		# one short segment still glowing
		var hw2 := 0.12
		poly(st, [on.call(0.3 - hw2, d0 + 0.05, 0.052), on.call(0.3 + hw2, d0 + 0.05, 0.052), on.call(0.3 + hw2, d1 - 0.05, 0.052), on.call(0.3 - hw2, d1 - 0.05, 0.052)],
			n, "light_strip", [Vector2(0.1, 0.45), Vector2(0.3, 0.45), Vector2(0.3, 0.55), Vector2(0.1, 0.55)])

func _pipes(st: SurfaceTool) -> void:
	recess(st, FACE_F, -0.75, 0.75, KH, 3.0, 0.5, "wall_lower", "wall_upper", "recess_back", "trim", 0.0, 0.75, 0.0, 1.0)
	for px in [-0.45, 0.0, 0.45]:
		cylinder_y(st, Vector3(px, 0, 0.0), 0.14, KH, 3.0, "pipe")

func new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func finish(st: SurfaceTool) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m

var lib_structure := MeshLibrary.new()
var lib_trim := MeshLibrary.new()
var lib_props := MeshLibrary.new()
var manifest := {"structure": [], "trim": [], "props": []}

func add_item(lib: MeshLibrary, name: String, mesh: ArrayMesh, shapes: Array, note: String) -> void:
	var id := lib.get_item_list().size()
	lib.create_item(id)
	lib.set_item_name(id, name)
	lib.set_item_mesh(id, mesh)
	lib.set_item_shapes(id, shapes)
	var key := "structure" if lib == lib_structure else ("trim" if lib == lib_trim else "props")
	manifest[key].append({"id": id, "name": name, "note": note})

func shape_box(mn: Vector3, mx: Vector3) -> Array:
	var b := BoxShape3D.new()
	b.size = mx - mn
	return [b, Transform3D(Basis(), (mn + mx) * 0.5)]

func floor_shapes() -> Array:
	return shape_box(Vector3(-1, -0.5, -1), Vector3(1, 0, 1)) + shape_box(Vector3(-1, 3.85, -1), Vector3(1, 4, 1))

func finish_empty(st: SurfaceTool) -> ArrayMesh:
	# an item with no geometry still needs a (degenerate) mesh in a MeshLibrary
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2.ZERO)
	st.add_vertex(Vector3.ZERO); st.add_vertex(Vector3.ZERO); st.add_vertex(Vector3.ZERO)
	return finish(st)

func stair_mesh(st: SurfaceTool, k: int) -> void:
	var h := 4.0 / 3.0
	var n := 6
	for i in n:
		var z0 := 1.0 - float(i) * 2.0 / n
		var z1 := 1.0 - float(i + 1) * 2.0 / n
		var yb := k * h + float(i) * h / n
		var yt := k * h + float(i + 1) * h / n
		# tread
		quad(st, Vector3(-1, yt, z0), Vector3(1, yt, z0), Vector3(1, yt, z1), Vector3(-1, yt, z1), Vector3.UP,
			"floor_metal", Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.16), Vector2(0, 0.16))
		# riser (hazard nosing so steps read from a distance)
		quad(st, Vector3(-1, yb, z0), Vector3(1, yb, z0), Vector3(1, yt, z0), Vector3(-1, yt, z0), Vector3.BACK,
			"hazard", Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.11), Vector2(0, 0.11))
		# side stringers down to the floor
		for sx in [-1.0, 1.0]:
			quad(st, Vector3(sx, 0, z0), Vector3(sx, 0, z1), Vector3(sx, yt, z1), Vector3(sx, yt, z0), Vector3(sx, 0, 0),
				"wall_lower", Vector2(0, 0), Vector2(0.33, 0), Vector2(0.33, minf(yt / 2.0, 1.0)), Vector2(0, minf(yt / 2.0, 1.0)))
	# handrails both sides: sloped rail + posts
	for sx in [-0.93, 0.93]:
		var a: Vector3 = Vector3(sx, k * h + 1.0, 1.0)
		var b := Vector3(sx, (k + 1) * h + 1.0, -1.0)
		var t := 0.03
		for face in [[Vector3(0, t, 0), Vector3.UP], [Vector3(0, -t, 0), Vector3.DOWN], [Vector3(t, 0, 0), Vector3.RIGHT], [Vector3(-t, 0, 0), Vector3.LEFT]]:
			var o: Vector3 = face[0]
			var side: Vector3 = Vector3(t, 0, 0) if absf(o.y) > 0 else Vector3(0, t, 0)
			quad(st, a + o - side, b + o - side, b + o + side, a + o + side, face[1], "hazard", Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.03), Vector2(0, 0.03))
		for pz in [0.8, -0.2]:
			var py: float = k * h + (1.0 - pz) / 2.0 * h
			box(st, Vector3(sx - 0.025, py, pz - 0.025), Vector3(sx + 0.025, py + 1.0, pz + 0.025), "trim", "trim")
	# back face at the top of the segment (visible from the far side / below)
	var top := (k + 1) * h
	quad(st, Vector3(1, 0, -1), Vector3(-1, 0, -1), Vector3(-1, top, -1), Vector3(1, top, -1), Vector3.FORWARD,
		"wall_lower", Vector2(0, 0), Vector2(1, 0), Vector2(1, minf(top / 2.0, 1.0)), Vector2(0, minf(top / 2.0, 1.0)))

# ------------------------------------------------------- tubes (ducts/shafts) ----
## Cross-sections are lists of (s, y) points going round the tube; s is lateral
## (right of the travel direction). Faces point inward.
const OCT := [Vector2(-0.45, 0), Vector2(0.45, 0), Vector2(0.95, 0.5), Vector2(0.95, 2.1), Vector2(0.45, 2.6), Vector2(-0.45, 2.6), Vector2(-0.95, 2.1), Vector2(-0.95, 0.5)]
const DUCT := [Vector2(-0.7, 0), Vector2(0.7, 0), Vector2(0.7, 1.2), Vector2(-0.7, 1.2)]

func _tube_tile(a: Vector2, b: Vector2, floor_tile: String, wall_tile: String) -> String:
	if a.y == 0 and b.y == 0:
		return floor_tile
	return wall_tile

## straight tube along dir (unit, XZ) from t0 to t1 (distance from cell centre)
func tube_run(st: SurfaceTool, dir: Vector3, t0: float, t1: float, sec: Array, floor_tile: String, wall_tile: String) -> void:
	var r := Vector3.UP.cross(dir)
	var cy := 0.0
	var cs := 0.0
	for p in sec:
		cy += (p as Vector2).y
	cy /= sec.size()
	for i in sec.size():
		var a: Vector2 = sec[i]
		var b: Vector2 = sec[(i + 1) % sec.size()]
		var mid := (a + b) * 0.5
		var n := (r * (cs - mid.x) + Vector3.UP * (cy - mid.y)).normalized()
		var pa0 := r * a.x + Vector3.UP * a.y + dir * t0
		var pb0 := r * b.x + Vector3.UP * b.y + dir * t0
		var pb1 := r * b.x + Vector3.UP * b.y + dir * t1
		var pa1 := r * a.x + Vector3.UP * a.y + dir * t1
		var w := a.distance_to(b) / 2.0
		var l := (t1 - t0) / 2.0
		quad(st, pa0, pb0, pb1, pa1, n, _tube_tile(a, b, floor_tile, wall_tile), Vector2(0, 0), Vector2(w, 0), Vector2(w, l), Vector2(0, l))

## Junction chamber (square, half-width hw, height h) with openings on `arms`.
func tube_hub(st: SurfaceTool, arms: int, sec: Array, hw: float, h: float, floor_tile: String, wall_tile: String, y0 := 0.0) -> void:
	quad(st, Vector3(-hw, y0, hw), Vector3(hw, y0, hw), Vector3(hw, y0, -hw), Vector3(-hw, y0, -hw), Vector3.UP, floor_tile, Vector2(0, 0), Vector2(hw, 0), Vector2(hw, hw), Vector2(0, hw))
	quad(st, Vector3(-hw, h, -hw), Vector3(hw, h, -hw), Vector3(hw, h, hw), Vector3(-hw, h, hw), Vector3.DOWN, wall_tile, Vector2(0, 0), Vector2(hw, 0), Vector2(hw, hw), Vector2(0, hw))
	for i in 4:
		var d: Vector3 = DIRS[i]
		var r := Vector3.UP.cross(d)
		var c := d * hw
		if arms & (1 << i):
			# fill between the square opening and the tube cross-section (corner wedges)
			for corner in [[Vector2(-hw, y0), Vector2(-hw, h)], [Vector2(hw, y0), Vector2(hw, h)]]:
				for cp in corner:
					var q: Vector2 = cp
					# nearest two section points to this square corner
					var best := []
					for p in sec:
						best.append([(p as Vector2).distance_to(q), p])
					best.sort_custom(func(x, y): return x[0] < y[0])
					var p1: Vector2 = best[0][1]
					var p2: Vector2 = best[1][1]
					if p1.distance_to(q) < 0.01:
						continue
					poly(st, [c + r * q.x + Vector3.UP * q.y, c + r * p1.x + Vector3.UP * p1.y, c + r * p2.x + Vector3.UP * p2.y], -d, wall_tile,
						[Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.2)])
		else:
			var b0 := Vector3.UP * y0
			quad(st, c - r * hw + b0, c + r * hw + b0, c + r * hw + Vector3.UP * h, c - r * hw + Vector3.UP * h, -d, wall_tile, Vector2(0, 0), Vector2(hw, 0), Vector2(hw, minf((h - y0) / 2.0, 1.0)), Vector2(0, minf((h - y0) / 2.0, 1.0)))

## Collision for a tube cell: open centre + arms, everything else solid.
func tube_collision(arms: int, hw: float, h: float, y0 := 0.0) -> Array:
	var e := [-1.0, -hw, hw, 1.0]
	var shapes := shape_box(Vector3(-1, -0.5, -1), Vector3(1, y0, 1)) + shape_box(Vector3(-1, h, -1), Vector3(1, 4, 1))
	for zi in 3:
		for xi in 3:
			var open := xi == 1 and zi == 1
			if xi == 1 and zi == 2 and arms & 1: open = true
			if xi == 2 and zi == 1 and arms & 2: open = true
			if xi == 1 and zi == 0 and arms & 4: open = true
			if xi == 0 and zi == 1 and arms & 8: open = true
			if not open:
				shapes += shape_box(Vector3(e[xi], y0, e[zi]), Vector3(e[xi + 1], h, e[zi + 1]))
	return shapes

func tube_family(prefix: String, sec: Array, hw: float, h: float, floor_tile: String, wall_tile: String, light_strip: bool, note: String, y0 := 0.0) -> void:
	var names := {1: "_end", 3: "_corner", 5: "", 7: "_t", 15: "_cross"}
	for arms in [1, 3, 5, 7, 15]:
		var st := new_st()
		if arms == 5:
			tube_run(st, Vector3(0, 0, 1), -1.0, 1.0, sec, floor_tile, wall_tile)
			if light_strip:
				quad(st, Vector3(-0.08, h - 0.01, -1), Vector3(0.08, h - 0.01, -1), Vector3(0.08, h - 0.01, 1), Vector3(-0.08, h - 0.01, 1), Vector3.DOWN,
					"light_strip", Vector2(0.1, 0.45), Vector2(0.9, 0.45), Vector2(0.9, 0.55), Vector2(0.1, 0.55))
		else:
			tube_hub(st, arms, sec, hw, h, floor_tile, wall_tile, y0)
			for i in 4:
				if arms & (1 << i):
					tube_run(st, DIRS[i], hw, 1.0, sec, floor_tile, wall_tile)
		add_item(lib_structure, prefix + names[arms], finish(st), tube_collision(arms, hw, h, y0), note)

## Wall face (+Z, at the face plane) with a tube-shaped opening, and the tube running
## from the face back through the wall cell to its -Z edge.
func wall_with_tube(st: SurfaceTool, sec: Array, hw: float, h: float, floor_tile: String, wall_tile: String, y0 := 0.0) -> void:
	var f = FACE_F
	side_auto(st, f, -1, 1, h, 4.0, 0, "wall_lower", "wall_upper")       # above the opening
	side_auto(st, f, -1, -hw, y0, h, 0, "wall_lower", "wall_upper")      # left of it
	side_auto(st, f, hw, 1, y0, h, 0, "wall_lower", "wall_upper")        # right of it
	side_auto(st, f, -1, 1, 0, y0, 0, "wall_lower", "wall_upper")        # below it (high mouths)
	var zf := 1.0 - FD
	if y0 > 0.0:   # sill of a high mouth
		quad(st, Vector3(-hw, y0, zf), Vector3(hw, y0, zf), Vector3(hw, y0, -1), Vector3(-hw, y0, -1), Vector3.UP, floor_tile,
			Vector2(0, 0), Vector2(hw, 0), Vector2(hw, 0.6), Vector2(0, 0.6))
	for cp in [Vector2(-hw, y0), Vector2(hw, y0), Vector2(-hw, h), Vector2(hw, h)]:
		var best := []
		for p in sec:
			best.append([(p as Vector2).distance_to(cp), p])
		best.sort_custom(func(x, y): return x[0] < y[0])
		var p1: Vector2 = best[0][1]
		var p2: Vector2 = best[1][1]
		if p1.distance_to(cp) < 0.01:
			continue
		poly(st, [Vector3(cp.x, cp.y, zf), Vector3(p1.x, p1.y, zf), Vector3(p2.x, p2.y, zf)], Vector3.BACK, "wall_lower",
			[Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.2)])
	tube_run(st, Vector3(0, 0, -1), -zf, 1.0, sec, floor_tile, wall_tile)

func wall_tube_collision(hw: float, h: float, y0 := 0.0) -> Array:
	var zf := 1.0 - FD
	return (shape_box(Vector3(-1, -0.5, -1), Vector3(1, 0, 1)) + (shape_box(Vector3(-hw, 0, -1), Vector3(hw, y0, zf)) if y0 > 0.0 else [])
		+ shape_box(Vector3(-1, 0, -1), Vector3(-hw, 4, zf)) + shape_box(Vector3(hw, 0, -1), Vector3(1, 4, zf))
		+ shape_box(Vector3(-hw, h, -1), Vector3(hw, 4, zf)))

func build_tubes() -> void:
	tube_family("shaft", OCT, 0.95, 2.6, "floor_metal", "recess_back", true, "Octagonal maintenance shaft (auto-joins)")
	tube_family("duct", DUCT, 0.7, 1.2, "floor_metal", "vent", false, "Crawl duct, 1.2m tall - crouch to fit (auto-joins)")
	var st := new_st()
	wall_with_tube(st, OCT, 0.95, 2.6, "floor_metal", "recess_back")
	add_item(lib_structure, "wall_shaft", finish(st), wall_tube_collision(0.75, 2.6), "Wall face with a shaft mouth; the shaft continues out of -Z")
	st = new_st()
	wall_with_tube(st, DUCT, 0.7, 1.2, "floor_metal", "vent")
	add_item(lib_structure, "wall_duct", finish(st), wall_tube_collision(0.7, 1.2), "Wall face with a duct mouth at floor level; duct continues out of -Z")
	# high ducts: same crawl duct with its floor 2 m up (mouths at ledge height)
	var high := []
	for p in DUCT:
		high.append((p as Vector2) + Vector2(0, 1.8))
	tube_family("hduct", high, 0.7, 3.0, "floor_metal", "vent", false, "Crawl duct 1.8 m up (reach it from a ledge), auto-joins", 1.8)
	st = new_st()
	wall_with_tube(st, high, 0.7, 3.0, "floor_metal", "vent", 1.8)
	add_item(lib_structure, "wall_hduct", finish(st), wall_tube_collision(0.7, 3.0, 1.8), "Wall face with a high duct mouth (1.8 m up, ledge height); duct continues out of -Z")

# ------------------------------------------------------------ upper floors ----
func build_upper() -> void:
	# catwalk: see-through grating deck with an underside, ceiling above
	var st := new_st()
	quad(st, Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1), Vector3.UP, "gutter", Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	quad(st, Vector3(-1, -0.15, -1), Vector3(1, -0.15, -1), Vector3(1, -0.15, 1), Vector3(-1, -0.15, 1), Vector3.DOWN, "gutter", Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	for sx in [-0.7, 0.7]:   # two stringer beams underneath
		box(st, Vector3(sx - 0.08, -0.45, -1), Vector3(sx + 0.08, -0.15, 1), "beam", "beam", "beam", true)
	ceiling_face(st)
	add_item(lib_structure, "catwalk", finish(st), shape_box(Vector3(-1, -0.15, -1), Vector3(1, 0, 1)) + shape_box(Vector3(-1, 3.85, -1), Vector3(1, 4, 1)), "Catwalk grating over open air (ceiling above)")
	# glass wall: open on +Z and -Z, window through the middle
	st = new_st()
	var gst := new_st()
	for sd in [FACE_F, Side.new(Vector3(0, 0, -1), Vector3(-1, 0, 0), FD)]:
		side_auto(st, sd, -1, 1, 0, 0.9, 0, "wall_lower", "wall_upper")
		side_auto(st, sd, -1, 1, 3.0, 4.0, 0, "wall_lower", "wall_upper")
		side_auto(st, sd, -1, -0.8, 0.9, 3.0, 0, "wall_lower", "wall_upper")
		side_auto(st, sd, 0.8, 1, 0.9, 3.0, 0, "wall_lower", "wall_upper")
	var zf := 1.0 - FD
	quad(st, Vector3(-0.8, 0.9, zf), Vector3(0.8, 0.9, zf), Vector3(0.8, 0.9, -zf), Vector3(-0.8, 0.9, -zf), Vector3.UP, "trim", Vector2(0, 0), Vector2(0.8, 0), Vector2(0.8, 0.25), Vector2(0, 0.25))
	quad(st, Vector3(-0.8, 3.0, -zf), Vector3(0.8, 3.0, -zf), Vector3(0.8, 3.0, zf), Vector3(-0.8, 3.0, zf), Vector3.DOWN, "trim", Vector2(0, 0), Vector2(0.8, 0), Vector2(0.8, 0.25), Vector2(0, 0.25))
	for sx in [-0.8, 0.8]:
		quad(st, Vector3(sx, 0.9, -zf), Vector3(sx, 0.9, zf), Vector3(sx, 3.0, zf), Vector3(sx, 3.0, -zf), Vector3(-signf(sx), 0, 0), "trim", Vector2(0, 0), Vector2(0.25, 0), Vector2(0.25, 1), Vector2(0, 1))
	for nz in [1.0, -1.0]:
		quad(gst, Vector3(-0.8, 0.9, 0.0), Vector3(0.8, 0.9, 0.0), Vector3(0.8, 3.0, 0.0), Vector3(-0.8, 3.0, 0.0), Vector3(0, 0, nz), "light_strip", Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var gm := finish(st)
	gst.commit(gm)
	gm.surface_set_material(1, load("res://kit/glass_material.tres"))
	add_item(lib_structure, "wall_glass", gm, shape_box(Vector3(-1, 0, -zf), Vector3(1, 4, zf)), "Interior window wall between two rooms (needs open space on +Z and -Z)")

func rail_edge(st: SurfaceTool, i: int) -> void:
	var d: Vector3 = DIRS[i]
	var r := Vector3.UP.cross(d)
	var c := d * 0.92
	for y in [0.5, 1.05]:
		box_oriented(st, c + Vector3.UP * y, r, 1.0, 0.03, 0.03, "hazard" if y > 1.0 else "trim")
	for sx in [-0.9, 0.0, 0.9]:
		var p: Vector3 = c + r * sx
		box(st, Vector3(p.x - 0.03, 0, p.z - 0.03), Vector3(p.x + 0.03, 1.08, p.z + 0.03), "trim", "trim")

## thin box centred at c, long axis along `axis` (unit X or Z), half-length hl
func box_oriented(st: SurfaceTool, c: Vector3, axis: Vector3, hl: float, hw: float, hh: float, tile: String) -> void:
	var ext := Vector3(absf(axis.x) * hl + absf(axis.z) * hw, hh, absf(axis.z) * hl + absf(axis.x) * hw)
	box(st, c - ext, c + ext, tile, tile, tile)

func build_rails_cover() -> void:
	var names := {1: "rail", 3: "rail_corner", 5: "rail_both", 7: "rail_u", 15: "rail_ring"}
	for mask in [1, 3, 5, 7, 15]:
		var st := new_st()
		var shapes := []
		for i in 4:
			if mask & (1 << i):
				rail_edge(st, i)
				var d: Vector3 = DIRS[i]
				var a := d * 0.92
				var ext := Vector3(absf(d.z) * 1.0 + absf(d.x) * 0.05, 0.6, absf(d.x) * 1.0 + absf(d.z) * 0.05)
				shapes += shape_box(a - ext + Vector3(0, 0.6, 0), a + ext + Vector3(0, 0.6, 0))
		add_item(lib_props, names[mask], finish(st), shapes, "Railing on the cell's edge(s), for upper floors next to open air")
	# low cover barrier along X
	var st := new_st()
	box(st, Vector3(-1, 0, -0.2), Vector3(1, 1.05, 0.2), "wall_lower", "hazard")
	add_item(lib_props, "cover", finish(st), shape_box(Vector3(-1, 0, -0.2), Vector3(1, 1.05, 0.2)), "Waist-high cover barrier along X")
	# console desk along X, screens facing +Z
	st = new_st()
	box(st, Vector3(-0.95, 0, -0.35), Vector3(0.95, 0.9, 0.35), "kick", "trim")
	for sx in [-0.5, 0.5]:
		var a: Vector3 = Vector3(sx - 0.4, 0.95, -0.25)
		quad(st, a, a + Vector3(0.8, 0, 0), a + Vector3(0.8, 0.45, -0.1), a + Vector3(0, 0.45, -0.1), Vector3(0, 0.2, 1).normalized(), "console",
			Vector2(0.1, 0.4), Vector2(0.9, 0.4), Vector2(0.9, 0.9), Vector2(0.1, 0.9))
		quad(st, a + Vector3(0.8, 0, -0.02), a + Vector3(0, 0, -0.02), a + Vector3(0, 0.45, -0.12), a + Vector3(0.8, 0.45, -0.12), Vector3(0, -0.2, -1).normalized(), "trim",
			Vector2(0, 0), Vector2(0.4, 0), Vector2(0.4, 0.25), Vector2(0, 0.25))
	add_item(lib_props, "console_desk", finish(st), shape_box(Vector3(-0.95, 0, -0.35), Vector3(0.95, 1.4, 0.35)), "Console desk along X, screens face +Z")
	# ledges: grated walkway 2 m up along the wall edges of a cell (edge masks like rails),
	# reaching back to the wall face so there's no gap
	var lnames := {1: "ledge", 3: "ledge_corner", 5: "ledge_both", 7: "ledge_u", 15: "ledge_ring"}
	for mask in [1, 3, 5, 7, 15]:
		st = new_st()
		var lshapes := []
		for i in 4:
			if not mask & (1 << i):
				continue
			var d: Vector3 = DIRS[i]
			var r := Vector3.UP.cross(d)
			var a := r * -1.0 + d * -0.05
			var b := r * 1.0 + d * 1.74
			var lo := Vector3(minf(a.x, b.x), 1.68, minf(a.z, b.z))
			var hi := Vector3(maxf(a.x, b.x), 1.8, maxf(a.z, b.z))
			box(st, lo, hi, "beam", "floor_grate", "beam")
			lshapes += shape_box(lo, hi)
			for lx in [-0.85, 0.85]:
				var p: Vector3 = r * lx + d * 0.05
				box(st, Vector3(p.x - 0.05, 0, p.z - 0.05), Vector3(p.x + 0.05, 1.68, p.z + 0.05), "beam", "beam")
		add_item(lib_props, lnames[mask], finish(st), lshapes, "Walkway ledge 1.8 m up along the cell's wall edge(s), reach high ducts from it")

func build_device_meshes() -> void:
	# ladder: rails + rungs, 5m tall, in the XY plane at z = 0
	var st := new_st()
	for sx in [-0.32, 0.32]:
		box(st, Vector3(sx - 0.03, 0, -0.03), Vector3(sx + 0.03, 5.0, 0.03), "hazard", "trim")
	var y := 0.3
	while y < 5.0:
		box(st, Vector3(-0.3, y - 0.02, -0.02), Vector3(0.3, y + 0.02, 0.02), "trim", "trim")
		y += 0.3
	for yb in [0.6, 2.4, 3.8]:   # brackets back toward the wall
		for sx in [-0.32, 0.32]:
			box(st, Vector3(sx - 0.02, yb, -0.9), Vector3(sx + 0.02, yb + 0.05, 0.0), "beam", "beam")
	ResourceSaver.save(finish(st), "res://kit/ladder.res")
	# elevator platform: 1.9m square deck, top at y = 0
	st = new_st()
	box(st, Vector3(-0.95, -0.25, -0.95), Vector3(0.95, 0.0, 0.95), "hazard", "floor_metal", "beam")
	ResourceSaver.save(finish(st), "res://kit/elevator_platform.res")
	# button post: waist-high pedestal with a glowing button face (+Z)
	st = new_st()
	box(st, Vector3(-0.08, 0, -0.08), Vector3(0.08, 1.0, 0.08), "beam", "trim")
	box(st, Vector3(-0.16, 1.0, -0.12), Vector3(0.16, 1.3, 0.12), "kick", "trim")
	glow_box(st, Vector3(-0.07, 1.08, 0.12), Vector3(0.07, 1.22, 0.14))
	ResourceSaver.save(finish(st), "res://kit/button_post.res")
	# breaker: tall panel with a hazard frame and a big lever housing (+Z)
	st = new_st()
	box(st, Vector3(-0.4, 0, -0.15), Vector3(0.4, 1.9, 0.15), "wall_lower", "trim")
	box(st, Vector3(-0.3, 0.9, 0.15), Vector3(0.3, 1.6, 0.2), "hazard", "trim")
	glow_box(st, Vector3(-0.12, 1.65, 0.15), Vector3(0.12, 1.75, 0.18), "warning_lamp", Vector2(0.47, 0.47), Vector2(0.53, 0.53))
	ResourceSaver.save(finish(st), "res://kit/breaker.res")
	st = new_st()
	box(st, Vector3(-0.05, -0.05, 0), Vector3(0.05, 0.05, 0.25), "trim", "trim")
	box(st, Vector3(-0.08, -0.08, 0.25), Vector3(0.08, 0.08, 0.32), "hazard", "hazard")
	ResourceSaver.save(finish(st), "res://kit/breaker_lever.res")
	# explosive canister
	st = new_st()
	cylinder_y(st, Vector3.ZERO, 0.32, 0.0, 1.1, "rust_plate", 10)
	quad(st, Vector3(-0.3, 1.1, 0.3), Vector3(0.3, 1.1, 0.3), Vector3(0.3, 1.1, -0.3), Vector3(-0.3, 1.1, -0.3), Vector3.UP, "warning_lamp", Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.7, 0.7), Vector2(0.3, 0.7))
	for yb in [0.2, 0.85]:
		cylinder_y(st, Vector3.ZERO, 0.34, yb, yb + 0.08, "hazard", 10)
	ResourceSaver.save(finish(st), "res://kit/canister.res")
	# vent cover grille (1.4 x 1.2, faces +Z)
	st = new_st()
	quad(st, Vector3(-0.7, 0, 0.02), Vector3(0.7, 0, 0.02), Vector3(0.7, 1.2, 0.02), Vector3(-0.7, 1.2, 0.02), Vector3.BACK, "vent", Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	quad(st, Vector3(0.7, 0, -0.02), Vector3(-0.7, 0, -0.02), Vector3(-0.7, 1.2, -0.02), Vector3(0.7, 1.2, -0.02), Vector3.FORWARD, "vent", Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	ResourceSaver.save(finish(st), "res://kit/vent_cover.res")
	# door release: wall panel (back on z = 0, faces +Z) with a big glowing button
	st = new_st()
	box(st, Vector3(-0.3, 0.95, 0.0), Vector3(0.3, 1.75, 0.1), "kick", "trim")
	box(st, Vector3(-0.22, 1.05, 0.1), Vector3(0.22, 1.25, 0.13), "hazard", "trim")
	glow_box(st, Vector3(-0.1, 1.4, 0.1), Vector3(0.1, 1.6, 0.16), "warning_lamp", Vector2(0.47, 0.47), Vector2(0.53, 0.53))
	ResourceSaver.save(finish(st), "res://kit/switch_panel.res")
	# lockdown console: pedestal with a tilted screen facing +Z
	st = new_st()
	box(st, Vector3(-0.45, 0, -0.3), Vector3(0.45, 0.85, 0.3), "kick", "trim")
	var a := Vector3(-0.4, 0.9, 0.2)
	quad(st, a, a + Vector3(0.8, 0, 0), a + Vector3(0.8, 0.4, -0.3), a + Vector3(0, 0.4, -0.3), Vector3(0, 0.6, 0.8).normalized(), "console",
		Vector2(0.1, 0.4), Vector2(0.9, 0.4), Vector2(0.9, 0.9), Vector2(0.1, 0.9))
	quad(st, a + Vector3(0.8, -0.05, -0.02), a + Vector3(0, -0.05, -0.02), a + Vector3(0, 0.38, -0.34), a + Vector3(0.8, 0.38, -0.34), Vector3(0, -0.6, -0.8).normalized(), "trim",
		Vector2(0, 0), Vector2(0.4, 0), Vector2(0.4, 0.25), Vector2(0, 0.25))
	glow_box(st, Vector3(-0.3, 0.86, 0.22), Vector3(0.3, 0.9, 0.28), "warning_lamp", Vector2(0.47, 0.47), Vector2(0.53, 0.53))
	ResourceSaver.save(finish(st), "res://kit/switch_console.res")

func build_floors() -> void:
	var st: SurfaceTool
	for f in [["floor", "floor_concrete", "Deck floor + ceiling"],
			["floor_metal", "floor_metal", "Tread-plate floor + ceiling"],
			["floor_grate", "floor_grate", "Glowing grate floor + ceiling (bakes low light)"],
			["floor_line", "floor_line", "Deck floor with yellow line on -Z edge"]]:
		st = new_st(); floor_face(st, f[1]); ceiling_face(st)
		add_item(lib_structure, f[0], finish(st), floor_shapes(), f[2])
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_with_panel(st, 0.75, 0.5, 0.125)
	add_item(lib_structure, "floor_light", finish(st), floor_shapes(), "Deck floor, recessed ceiling light (bakes OmniLight)")
	# unpowered ceiling light (power zones swap it to floor_light when the breaker is thrown)
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_with_panel(st, 0.75, 0.5, 0.125, "kick")
	add_item(lib_structure, "floor_light_off", finish(st), floor_shapes(), "Ceiling light with no power (see Level power zones)")
	# open-ceiling floors: the room continues up into the floor above (double height)
	for f in [["floor_open", "floor_concrete"], ["floor_metal_open", "floor_metal"], ["floor_grate_open", "floor_grate"], ["floor_line_open", "floor_line"]]:
		st = new_st(); floor_face(st, f[1])
		add_item(lib_structure, f[0], finish(st), shape_box(Vector3(-1, -0.5, -1), Vector3(1, 0, 1)), "Floor with no ceiling (open to the level above)")
	# open air: no floor, ceiling only (upper level of a double-height space)
	st = new_st(); ceiling_face(st)
	add_item(lib_structure, "void", finish(st), shape_box(Vector3(-1, 3.85, -1), Vector3(1, 4, 1)), "Open air: ceiling only, no floor")
	st = new_st(); ceiling_with_panel(st, 0.75, 0.5, 0.125)
	add_item(lib_structure, "void_light", finish(st), shape_box(Vector3(-1, 3.85, -1), Vector3(1, 4, 1)), "Open air with a ceiling light (bakes OmniLight)")
	st = new_st(); ceiling_with_panel(st, 0.75, 0.5, 0.125, "kick")
	add_item(lib_structure, "void_light_off", finish(st), shape_box(Vector3(-1, 3.85, -1), Vector3(1, 4, 1)), "Open-air ceiling light with no power (see Level power zones)")
	st = new_st()
	add_item(lib_structure, "void_open", finish_empty(st), [], "Open air, no ceiling either (stacked shafts)")
	# stairs: 3 segments ascend toward local -Z, 4m rise over 6m (33.7 degrees)
	for k in 3:
		st = new_st()
		stair_mesh(st, k)
		var h := 4.0 / 3.0
		var wedge := ConvexPolygonShape3D.new()
		wedge.points = PackedVector3Array([Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1),
			Vector3(-1, k * h, 1), Vector3(1, k * h, 1), Vector3(-1, (k + 1) * h, -1), Vector3(1, (k + 1) * h, -1)])
		var shapes := [wedge, Transform3D()]
		for sx in [-1.0, 0.94]:   # invisible rail walls so nobody drops into the side gap
			var rail := ConvexPolygonShape3D.new()
			rail.points = PackedVector3Array([Vector3(sx, k * h, 1), Vector3(sx + 0.06, k * h, 1), Vector3(sx, k * h, -1), Vector3(sx + 0.06, k * h, -1),
				Vector3(sx, k * h + 1.05, 1), Vector3(sx + 0.06, k * h + 1.05, 1), Vector3(sx, (k + 1) * h + 1.05, -1), Vector3(sx + 0.06, (k + 1) * h + 1.05, -1)])
			shapes += [rail, Transform3D()]
		if k == 0:
			shapes += shape_box(Vector3(-1, 3.85, -1), Vector3(1, 4, 1))   # bottom segment keeps its ceiling
			ceiling_face(st)
		add_item(lib_structure, "stair_%d" % k, finish(st), shapes, "Stairs segment %d of 3 (ascends toward -Z; floor above must be open for segments 1-2)" % k)
	# doors: passage along Z, frame faces sit on the wall face planes (+-0.25) so the
	# wall profile runs straight through above the opening. Slabs are baked by Level.
	for spec in [["door", [-1.0, 1.0], "Door frame, passage along Z (bakes a sliding door)"],
			["door_half", [-1.0], "Half of a 2-cell double door, jamb on -X (pair with a 180-rotated twin)"]]:
		var dst := new_st()
		door_mesh(dst, spec[1])
		var shapes := shape_box(Vector3(-1, -0.5, -1), Vector3(1, 0, 1)) + shape_box(Vector3(-1, CY, -0.25), Vector3(1, 4, 0.25))
		for jx in spec[1]:
			var x0: float = minf(jx, jx * 0.75)
			var x1: float = maxf(jx, jx * 0.75)
			shapes += shape_box(Vector3(x0, 0, -0.25), Vector3(x1, CY, 0.25))
		add_item(lib_structure, spec[0], finish(dst), shapes, spec[2])

# ------------------------------------------------------------------ props ----
## Props grid: same 2x4x2 cells as structure, painted over open floor cells.
## Runs (trays, pipes, beams) line up cell to cell.
const TRAY_Y := 3.3
func tray_arm(st: SurfaceTool, dir: Vector3) -> void:
	# U-channel from the cell centre to the edge along dir
	var side := Vector3(-dir.z, 0, dir.x)
	var w := 0.3
	var a := -side * w
	var b := side * w
	var c0 := Vector3(0, TRAY_Y, 0) - dir * w
	var c1 := Vector3(0, TRAY_Y, 0) + dir * 1.0
	poly(st, [c0 + a, c0 + b, c1 + b, c1 + a], Vector3.DOWN, "beam", [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.3, 0.5), Vector2(0, 0.5)])
	poly(st, [c0 + a + Vector3(0, 0.02, 0), c1 + a + Vector3(0, 0.02, 0), c1 + b + Vector3(0, 0.02, 0), c0 + b + Vector3(0, 0.02, 0)], Vector3.UP, "wall_cables", [Vector2(0, 0.3), Vector2(0.5, 0.3), Vector2(0.5, 0.7), Vector2(0, 0.7)])
	for sgn in [-1.0, 1.0]:
		var e: Vector3 = side * w * sgn
		var n: Vector3 = side * sgn
		poly(st, [c0 + e, c1 + e, c1 + e + Vector3(0, 0.12, 0), c0 + e + Vector3(0, 0.12, 0)], n, "trim", [Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 0.06), Vector2(0, 0.06)])
		poly(st, [c0 + e, c1 + e, c1 + e + Vector3(0, 0.12, 0), c0 + e + Vector3(0, 0.12, 0)], -n, "trim", [Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 0.06), Vector2(0, 0.06)])

func tray_mesh(st: SurfaceTool, arms: int) -> void:
	for i in 4:
		if arms & (1 << i):
			tray_arm(st, DIRS[i])
	# hanger rods at the centre
	for sgn in [-1.0, 1.0]:
		box(st, Vector3(-0.02 + sgn * 0.33, TRAY_Y, -0.02), Vector3(0.02 + sgn * 0.33, 4.0, 0.02), "trim", "trim")

func build_props() -> void:
	# cable tray: every rotation-unique arm combination (end, straight, corner, T, cross)
	var named := {1: "tray_end", 5: "tray", 3: "tray_corner", 7: "tray_t", 15: "tray_cross"}
	for arms in [1, 3, 5, 7, 15]:
		var st := new_st()
		tray_mesh(st, arms)
		add_item(lib_props, named[arms], finish(st), [], "Ceiling cable tray (%s), runs along local Z/X" % named[arms])
	# vertical pipe bundle against the +Z edge, floor to ceiling
	var st := new_st()
	for px in [-0.45, 0.0, 0.45]:
		cylinder_y(st, Vector3(px, 0, 0.78), 0.12, 0.0, 4.0, "pipe")
	for y in [0.6, 3.4]:
		box(st, Vector3(-0.7, y, 0.62), Vector3(0.7, y + 0.1, 0.94), "beam", "trim", "trim")
	add_item(lib_props, "pipes_vertical", finish(st), shape_box(Vector3(-0.6, 0, 0.64), Vector3(0.6, 4, 0.92)), "Vertical pipe bundle hugging the +Z edge")
	# ceiling I-beam along X
	st = new_st()
	box(st, Vector3(-1, 3.5, -0.25), Vector3(1, 4.0, 0.25), "beam", "beam", "trim", true)
	add_item(lib_props, "beam", finish(st), [], "Ceiling I-beam along X (lines up into long beams)")
	st = new_st()
	box(st, Vector3(-0.25, 3.5, -1), Vector3(0.25, 4.0, 1), "beam", "beam", "trim", true)
	box(st, Vector3(-1, 3.5, -0.25), Vector3(1, 4.0, 0.25), "beam", "beam", "trim", true)
	add_item(lib_props, "beam_cross", finish(st), [], "Ceiling I-beam crossing")
	# pillar
	st = new_st()
	box(st, Vector3(-0.375, 0, -0.375), Vector3(0.375, 4, 0.375), "wall_concrete", "trim", "", true, "hazard", 0.5)
	add_item(lib_props, "pillar", finish(st), shape_box(Vector3(-0.375, 0, -0.375), Vector3(0.375, 4, 0.375)), "Structural pillar, cell centre")

	# free-placed clutter meshes (used by scenes/props/crate*.tscn)
	st = new_st()
	box(st, Vector3(-0.6, 0, -0.6), Vector3(0.6, 1.2, 0.6), "crate", "crate")
	ResourceSaver.save(finish(st), "res://kit/crate.res")
	st = new_st()
	box(st, Vector3(-0.75, 0, -0.75), Vector3(0.75, 1.5, 0.75), "crate", "crate")
	box(st, Vector3(-0.5, 1.5, -0.5), Vector3(0.5, 2.5, 0.5), "crate", "crate")
	ResourceSaver.save(finish(st), "res://kit/crate_stack.res")
	# pickups (spun/bobbed by scripts/pickup.gd)
	st = new_st()
	box(st, Vector3(-0.22, 0, -0.14), Vector3(0.22, 0.3, 0.14), "trim", "trim", "trim")
	var red_a := Vector2(0.47, 0.47)
	var red_b := Vector2(0.53, 0.53)
	glow_box(st, Vector3(-0.05, 0.06, 0.14), Vector3(0.05, 0.26, 0.16), "warning_lamp", red_a, red_b)
	glow_box(st, Vector3(-0.12, 0.13, 0.14), Vector3(0.12, 0.19, 0.16), "warning_lamp", red_a, red_b)
	glow_box(st, Vector3(-0.05, 0.06, -0.16), Vector3(0.05, 0.26, -0.14), "warning_lamp", red_a, red_b)
	glow_box(st, Vector3(-0.12, 0.13, -0.16), Vector3(0.12, 0.19, -0.14), "warning_lamp", red_a, red_b)
	ResourceSaver.save(finish(st), "res://kit/pickup_health.res")
	st = new_st()
	box(st, Vector3(-0.1, 0, -0.1), Vector3(0.1, 0.42, 0.1), "kick", "trim", "trim")
	glow_box(st, Vector3(-0.105, 0.12, -0.105), Vector3(0.105, 0.3, 0.105))
	box(st, Vector3(-0.05, 0.42, -0.05), Vector3(0.05, 0.47, 0.05), "trim", "trim")
	ResourceSaver.save(finish(st), "res://kit/pickup_cells.res")

## jambs: list of jamb sides in local X (-1 and/or +1). Jamb occupies |x| in [0.75, 1].
func door_mesh(st: SurfaceTool, jambs: Array) -> void:
	# passage floor + soffit
	quad(st, Vector3(-1, 0, 0.25), Vector3(1, 0, 0.25), Vector3(1, 0, -0.25), Vector3(-1, 0, -0.25), Vector3.UP,
		"floor_metal", Vector2(0, 0.375), Vector2(1, 0.375), Vector2(1, 0.625), Vector2(0, 0.625))
	var ox0 := -0.75 if jambs.has(-1.0) else -1.0
	var ox1 := 0.75 if jambs.has(1.0) else 1.0
	quad(st, Vector3(ox0, CY, -0.25), Vector3(ox1, CY, -0.25), Vector3(ox1, CY, 0.25), Vector3(ox0, CY, 0.25), Vector3.DOWN,
		"trim", Vector2(0, 0), Vector2(0.75, 0), Vector2(0.75, 0.25), Vector2(0, 0.25))
	for i in [0, 2]:   # +Z and -Z sides
		var sd = side_of(i)
		var f = Side.new(sd.n, sd.r, FD)
		# gutter + chamfer full width
		for g in [[0.0, G_Y, GD, G_Y, "gutter", Vector3.UP, 0.0, GD / 2.0], [FD, CY, 0.0, 4.0, "chamfer", (sd.n + Vector3.DOWN).normalized(), 0.47, 1.0]]:
			var pts := [sd.p(-1, g[1], g[0]), sd.p(1, g[1], g[0]), sd.p(1, g[3], g[2]), sd.p(-1, g[3], g[2])]
			poly(st, pts, g[5], g[4], [Vector2(0, g[6]), Vector2(1, g[6]), Vector2(1, g[7]), Vector2(0, g[7])])
		# floor between gutter and frame face (doorway threshold)
		poly(st, [sd.p(ox0 * sd.r.x if sd.r.x != 0 else ox0, 0, GD), sd.p(ox1 * sd.r.x if sd.r.x != 0 else ox1, 0, GD), sd.p(ox1 * sd.r.x if sd.r.x != 0 else ox1, 0, FD), sd.p(ox0 * sd.r.x if sd.r.x != 0 else ox0, 0, FD)],
			Vector3.UP, "floor_metal", [Vector2(0, 0), Vector2(0.75, 0), Vector2(0.75, 0.1), Vector2(0, 0.1)])
		for jx in jambs:
			# jamb in s-space of this side
			var js: float = jx * sd.r.x
			var s0 := minf(js, js * 0.75)
			var s1 := maxf(js, js * 0.75)
			var kp := [sd.p(s0, G_Y, GD), sd.p(s1, G_Y, GD), sd.p(s1, KH, FD), sd.p(s0, KH, FD)]
			poly(st, kp, (sd.n * KH + Vector3.UP * (FD - GD)).normalized(), "kick",
				[Vector2((s0 + 1) / 2, 0.2), Vector2((s1 + 1) / 2, 0.2), Vector2((s1 + 1) / 2, 0.55), Vector2((s0 + 1) / 2, 0.55)])
			side_auto(st, f, s0, s1, KH, CY, 0, "hazard", "hazard")
			# kick end cap, facing the opening
			var inner := js * 0.75
			var cap_n: Vector3 = sd.r * (-signf(js))
			poly(st, [sd.p(inner, 0, GD), sd.p(inner, 0, FD), sd.p(inner, KH, FD)], cap_n, "trim",
				[Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 0.12)])
	# jamb inner faces (between the two face planes)
	for jx in jambs:
		var x: float = jx * 0.75
		var n := Vector3(-signf(jx), 0, 0)
		quad(st, Vector3(x, 0, -0.25), Vector3(x, 0, 0.25), Vector3(x, CY, 0.25), Vector3(x, CY, -0.25), n,
			"hazard", Vector2(0, 0), Vector2(0.25, 0), Vector2(0.25, 1), Vector2(0, 1))

func _init() -> void:
	var f := FileAccess.open(ATLAS_META, FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	tiles = meta.tiles
	aw = meta.width
	ah = meta.height
	var sm := ShaderMaterial.new()
	sm.shader = load("res://kit/kit.gdshader")
	sm.set_shader_parameter("albedo_tex", load("res://art/textures/kit_albedo.png"))
	sm.set_shader_parameter("emission_tex", load("res://art/textures/kit_emission.png"))
	sm.set_shader_parameter("emission_energy", 2.0)
	ResourceSaver.save(sm, "res://kit/kit_material.tres")
	mat = load("res://kit/kit_material.tres")
	var gm := ShaderMaterial.new()
	gm.shader = load("res://art/shaders/glass.gdshader")
	ResourceSaver.save(gm, "res://kit/glass_material.tres")
	build_walls()
	build_floors()
	build_props()
	build_tubes()
	build_upper()
	build_rails_cover()
	build_device_meshes()
	# door slab (not a grid piece: spawned by Level for each "door" cell)
	var ds := new_st()
	for sd in [SIDE_F, SIDE_B]:
		var z: float = 0.08 * sd.n.z
		quad(ds, Vector3(-0.75 * sd.r.x, 0, z), Vector3(0.75 * sd.r.x, 0, z), Vector3(0.75 * sd.r.x, 3.25, z), Vector3(-0.75 * sd.r.x, 3.25, z),
			sd.n, "door", Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	box(ds, Vector3(-0.74, 0, -0.075), Vector3(0.74, 3.25, 0.075), "trim", "trim", "trim")
	ResourceSaver.save(finish(ds), "res://kit/door_slab.res")
	var dh := new_st()
	for sd in [SIDE_F, SIDE_B]:
		var zz: float = 0.08 * sd.n.z
		var xa: float = -0.75 if sd.r.x > 0 else 1.0
		var xb: float = 1.0 if sd.r.x > 0 else -0.75
		quad(dh, Vector3(xa, 0, zz), Vector3(xb, 0, zz), Vector3(xb, 3.25, zz), Vector3(xa, 3.25, zz),
			sd.n, "door", Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0, 1))
	box(dh, Vector3(-0.74, 0, -0.075), Vector3(0.99, 3.25, 0.075), "trim", "trim", "trim")
	ResourceSaver.save(finish(dh), "res://kit/door_slab_half.res")
	# ---- scattergun viewmodel (low-poly, same atlas; barrel along -Z) ----
	var g := new_st()
	box(g, Vector3(-0.065, -0.07, -0.06), Vector3(0.065, 0.07, 0.2), "beam", "trim", "trim")          # receiver
	box(g, Vector3(-0.06, -0.05, -0.33), Vector3(0.06, 0.055, -0.06), "wall_lower", "trim", "trim")   # shroud
	box(g, Vector3(-0.078, -0.062, -0.4), Vector3(0.078, 0.07, -0.33), "trim", "beam", "kick")        # muzzle block
	box(g, Vector3(-0.05, -0.02, -0.43), Vector3(-0.008, 0.03, -0.4), "kick", "kick", "kick")         # barrel L
	box(g, Vector3(0.008, -0.02, -0.43), Vector3(0.05, 0.03, -0.4), "kick", "kick", "kick")           # barrel R
	for zc in [-0.13, -0.24]:
		glow_box(g, Vector3(-0.068, -0.058, zc - 0.018), Vector3(0.068, 0.063, zc + 0.018))           # coils
	box(g, Vector3(-0.036, -0.22, 0.08), Vector3(0.036, -0.07, 0.17), "kick", "kick", "kick")         # grip
	box(g, Vector3(-0.025, 0.07, -0.05), Vector3(0.025, 0.1, 0.15), "trim", "trim", "trim")           # top rail
	glow_box(g, Vector3(0.065, -0.04, 0.0), Vector3(0.088, 0.035, 0.14))                            # side cell
	ResourceSaver.save(finish(g), "res://kit/scattergun.res")
	ResourceSaver.save(lib_structure, "res://kit/structure.meshlib.res")
	ResourceSaver.save(lib_trim, "res://kit/trim.meshlib.res")
	ResourceSaver.save(lib_props, "res://kit/props.meshlib.res")
	var mf := FileAccess.open("res://kit/kit_manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, " "))
	print("kit saved: structure ", manifest.structure.size(), ", trim ", manifest.trim.size(), ", props ", manifest.props.size())
	quit()
