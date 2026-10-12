extends SceneTree
## Builds the modular grid kit -> res://kit/kit.meshlib.res
## Run: godot --headless --path . -s tools/build_kit.gd
##
## GRID RULES (the whole point of this kit):
##   * Cell = 2m (x) * 4m (y) * 2m (z). GridMap cell_size = (2,4,2), center_y = false.
##   * Every piece lives strictly inside its cell: x,z in [-1,1], y in [0,4].
##   * Walls are solid blocks. Detail is cut INTO them (recesses), never stuck out,
##     so neighbours never overlap and corners are always clean.
##   * Wall "features" (lights, vents, consoles...) sit on the +Z face. Rotate the
##     cell in the GridMap to point the feature at the room.
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
	func _init(normal: Vector3, right: Vector3) -> void:
		n = normal
		r = right
	func p(s: float, y: float, depth: float) -> Vector3:
		return n * (1.0 - depth) + r * s + Vector3.UP * y

var SIDE_F := Side.new(Vector3(0, 0, 1), Vector3(1, 0, 0))    # +Z (feature side)
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
	# front face with a rectangular hole
	side_auto(st, sd, -1, 1, 0, y0, 0, lower, upper)
	side_auto(st, sd, -1, 1, y1, 4, 0, lower, upper)
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

func glow_box(st: SurfaceTool, mn: Vector3, mx: Vector3) -> void:
	# every face sampled from the lit band of light_strip -> solid emissive block
	var a := Vector2(0.3, 0.585)
	var b := Vector2(0.4, 0.6)
	var faces := [
		[Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3.BACK],
		[Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3.FORWARD],
		[Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3.RIGHT],
		[Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3.LEFT],
		[Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3.UP],
		[Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z), Vector3.DOWN]]
	for f in faces:
		quad(st, f[0], f[1], f[2], f[3], f[4], "light_strip", a, Vector2(b.x, a.y), b, Vector2(a.x, b.y))

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

func ceiling_with_panel(st: SurfaceTool, hx: float, hz: float, depth: float) -> void:
	# ceiling with a recessed glowing panel in the middle
	var rects := [[-1, 1, -1, -hz], [-1, 1, hz, 1], [-1, -hx, -hz, hz], [hx, 1, -hz, hz]]
	for r in rects:
		var x0: float = r[0]; var x1: float = r[1]; var z0: float = r[2]; var z1: float = r[3]
		quad(st, Vector3(x0, 4, z0), Vector3(x1, 4, z0), Vector3(x1, 4, z1), Vector3(x0, 4, z1), Vector3.DOWN,
			"ceiling", Vector2((x0 + 1) / 2, (z0 + 1) / 2), Vector2((x1 + 1) / 2, (z0 + 1) / 2),
			Vector2((x1 + 1) / 2, (z1 + 1) / 2), Vector2((x0 + 1) / 2, (z1 + 1) / 2))
	var y := 4.0 + depth
	# glowing panel: sample the lit band of the light_strip tile
	quad(st, Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz), Vector3.DOWN,
		"light_strip", Vector2(0, 0.40), Vector2(1, 0.40), Vector2(1, 0.60), Vector2(0, 0.60))
	var dv := depth / 2.0
	for e in [[Vector3(-hx, 4, -hz), Vector3(hx, 4, -hz), Vector3.BACK], [Vector3(hx, 4, hz), Vector3(-hx, 4, hz), Vector3.FORWARD],
			[Vector3(-hx, 4, hz), Vector3(-hx, 4, -hz), Vector3.RIGHT], [Vector3(hx, 4, -hz), Vector3(hx, 4, hz), Vector3.LEFT]]:
		var a: Vector3 = e[0]; var b: Vector3 = e[1]
		quad(st, a, b, b + Vector3.UP * depth, a + Vector3.UP * depth, e[2],
			"trim", Vector2(0, 0), Vector2(1, 0), Vector2(1, dv), Vector2(0, dv))

# ----------------------------------------------------------------- pieces ----
func wall_base(st: SurfaceTool, lower := "wall_lower", upper := "wall_upper", skip_front := false) -> void:
	if not skip_front:
		plain_side(st, SIDE_F, lower, upper)
	plain_side(st, SIDE_B, lower, upper)
	plain_side(st, SIDE_R, lower, upper)
	plain_side(st, SIDE_L, lower, upper)

func new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func finish(st: SurfaceTool) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m

var lib := MeshLibrary.new()
var next_id := 0
var manifest := []

func add_item(name: String, mesh: ArrayMesh, shapes: Array, note: String) -> void:
	lib.create_item(next_id)
	lib.set_item_name(next_id, name)
	lib.set_item_mesh(next_id, mesh)
	lib.set_item_shapes(next_id, shapes)
	manifest.append({"id": next_id, "name": name, "note": note})
	next_id += 1

func shape_box(mn: Vector3, mx: Vector3) -> Array:
	var b := BoxShape3D.new()
	b.size = mx - mn
	return [b, Transform3D(Basis(), (mn + mx) * 0.5)]

func wall_shapes() -> Array:
	return shape_box(Vector3(-1, 0, -1), Vector3(1, 4, 1))

func floor_shapes() -> Array:
	return shape_box(Vector3(-1, -0.5, -1), Vector3(1, 0, 1)) + shape_box(Vector3(-1, 4, -1), Vector3(1, 4.5, 1))

func build_walls() -> void:
	var st: SurfaceTool
	# plain steel
	st = new_st(); wall_base(st)
	add_item("wall", finish(st), wall_shapes(), "Plain steel wall block")
	# concrete
	st = new_st(); wall_base(st, "wall_concrete", "wall_concrete")
	add_item("wall_bulkhead", finish(st), wall_shapes(), "Ribbed bulkhead wall block")
	# hazard band lower
	st = new_st(); wall_base(st, "hazard", "wall_upper", true); plain_side(st, SIDE_F, "hazard", "wall_upper")
	add_item("wall_hazard", finish(st), wall_shapes(), "Hazard stripes on +Z lower half")
	# cables upper
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true); plain_side(st, SIDE_F, "wall_lower", "wall_cables")
	add_item("wall_cables", finish(st), wall_shapes(), "Cable run on +Z upper half")
	# rust upper
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true); plain_side(st, SIDE_F, "wall_lower", "rust_plate")
	add_item("wall_rust", finish(st), wall_shapes(), "Rusted upper panel on +Z")
	# recessed light strip (spawns a light)
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true)
	recess(st, SIDE_F, -0.875, 0.875, 2.625, 3.125, 0.125, "wall_lower", "wall_upper", "light_strip", "trim", 0.0, 1.0, 0.36, 0.64)
	add_item("wall_light", finish(st), wall_shapes(), "Recessed cyan light strip on +Z (spawns OmniLight)")
	# vent
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true)
	recess(st, SIDE_F, -0.625, 0.625, 0.25, 1.5, 0.25, "wall_lower", "wall_upper", "vent", "trim", 0.0, 1.0, 0.0, 1.0)
	add_item("wall_vent", finish(st), wall_shapes(), "Recessed floor-level vent on +Z")
	# console
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true)
	recess(st, SIDE_F, -0.75, 0.75, 1.0, 2.5, 0.25, "wall_lower", "wall_upper", "console", "trim", 0.0, 1.0, 0.0, 1.0)
	add_item("wall_console", finish(st), wall_shapes(), "Recessed console screen on +Z (spawns dim light)")
	# red warning lamp
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true)
	recess(st, SIDE_F, -0.375, 0.375, 2.5, 3.25, 0.125, "wall_lower", "wall_upper", "warning_lamp", "trim", 0.0, 1.0, 0.0, 1.0)
	add_item("wall_lamp", finish(st), wall_shapes(), "Red warning lamp on +Z (spawns red OmniLight)")
	# pipe bay: deep recess with vertical pipes
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true)
	recess(st, SIDE_F, -0.75, 0.75, 0.0, 3.5, 0.5, "wall_lower", "wall_upper", "recess_back", "trim", 0.0, 0.75, 0.0, 1.0)
	for px in [-0.45, 0.0, 0.45]:
		cylinder_y(st, Vector3(px, 0, 0.75), 0.14, 0.0, 3.5, "pipe")
	add_item("wall_pipes", finish(st), wall_shapes(), "Deep pipe bay on +Z")
	# porthole window onto space
	st = new_st(); wall_base(st, "wall_lower", "wall_upper", true)
	recess(st, SIDE_F, -0.875, 0.875, 0.875, 3.0, 0.375, "wall_lower", "wall_upper", "window", "trim", 0.0, 1.0, 0.0, 1.0)
	add_item("wall_window", finish(st), wall_shapes(), "Deep-set window onto space on +Z (spawns faint light)")

func build_floors() -> void:
	var st: SurfaceTool
	for f in [["floor", "floor_concrete", "Concrete floor + ceiling"],
			["floor_metal", "floor_metal", "Tread-plate floor + ceiling"],
			["floor_grate", "floor_grate", "Glowing grate floor + ceiling (spawns low light)"],
			["floor_line", "floor_line", "Concrete floor with yellow line on -Z edge"]]:
		st = new_st(); floor_face(st, f[1]); ceiling_face(st)
		add_item(f[0], finish(st), floor_shapes(), f[2])
	# ceiling light
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_with_panel(st, 0.75, 0.5, 0.125)
	add_item("floor_light", finish(st), floor_shapes(), "Concrete floor, recessed ceiling light (spawns OmniLight)")
	# ceiling beam along X (lines up with neighbours into long beams)
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_face(st)
	box(st, Vector3(-1, 3.5, -0.25), Vector3(1, 4.0, 0.25), "beam", "beam", "trim", true)
	add_item("floor_beam", finish(st), floor_shapes(), "Concrete floor, ceiling I-beam along X")
	# pillar
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_face(st)
	box(st, Vector3(-0.375, 0, -0.375), Vector3(0.375, 4, 0.375), "wall_concrete", "trim", "", true, "hazard", 0.5)
	add_item("pillar", finish(st), floor_shapes() + shape_box(Vector3(-0.375, 0, -0.375), Vector3(0.375, 4, 0.375)), "Floor with central concrete pillar")
	# crates
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_face(st)
	box(st, Vector3(-0.6, 0, -0.6), Vector3(0.6, 1.2, 0.6), "crate", "crate")
	add_item("crate", finish(st), floor_shapes() + shape_box(Vector3(-0.6, 0, -0.6), Vector3(0.6, 1.2, 0.6)), "Floor with one 1.2m crate")
	st = new_st(); floor_face(st, "floor_concrete"); ceiling_face(st)
	box(st, Vector3(-0.75, 0, -0.75), Vector3(0.75, 1.5, 0.75), "crate", "crate")
	box(st, Vector3(-0.5, 1.5, -0.5), Vector3(0.5, 2.5, 0.5), "crate", "crate")
	add_item("crate_stack", finish(st), floor_shapes() + shape_box(Vector3(-0.75, 0, -0.75), Vector3(0.75, 1.5, 0.75)) + shape_box(Vector3(-0.5, 1.5, -0.5), Vector3(0.5, 2.5, 0.5)), "Floor with stacked crates")
	# door frame (passage runs along Z, door slab spawned at runtime)
	st = new_st(); floor_face(st, "floor_metal"); ceiling_face(st)
	box(st, Vector3(-1, 0, -0.25), Vector3(-0.75, 3.25, 0.25), "hazard", "trim", "", true)
	box(st, Vector3(0.75, 0, -0.25), Vector3(1, 3.25, 0.25), "hazard", "trim", "", true)
	box(st, Vector3(-1, 3.25, -0.25), Vector3(1, 4, 0.25), "trim", "trim", "trim", true)
	add_item("door", finish(st), floor_shapes() + shape_box(Vector3(-1, 0, -0.25), Vector3(-0.75, 4, 0.25)) + shape_box(Vector3(0.75, 0, -0.25), Vector3(1, 4, 0.25)) + shape_box(Vector3(-1, 3.25, -0.25), Vector3(1, 4, 0.25)), "Door frame, passage along Z (spawns sliding door)")
	# half of a double door: jamb on -X only; pair two cells (second rotated 180)
	st = new_st(); floor_face(st, "floor_metal"); ceiling_face(st)
	box(st, Vector3(-1, 0, -0.25), Vector3(-0.75, 3.25, 0.25), "hazard", "trim", "", true)
	box(st, Vector3(-1, 3.25, -0.25), Vector3(1, 4, 0.25), "trim", "trim", "trim", true)
	add_item("door_half", finish(st), floor_shapes() + shape_box(Vector3(-1, 0, -0.25), Vector3(-0.75, 4, 0.25)) + shape_box(Vector3(-1, 3.25, -0.25), Vector3(1, 4, 0.25)), "Half of a 2-cell double door, jamb on -X (spawns slab that slides into the jamb side)")

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
	build_walls()
	build_floors()
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
	var err := ResourceSaver.save(lib, "res://kit/kit.meshlib.res")
	var mf := FileAccess.open("res://kit/kit_manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, " "))
	print("kit saved (", err, "): ", next_id, " items")
	quit()
