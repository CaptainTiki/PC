@tool
class_name Level
extends Node3D
## Level root. Paint the GridMap, then press "Bake" (inspector) — this writes the
## derived ship detail into the scene as normal saved nodes under "Baked":
##   * auto-trims: angled wall/ceiling chamfers + floor kick plates along every
##     wall edge, mitred inner corners, capped outer corners
##   * OmniLights for light cells, Door scenes for door cells
## Nothing is generated at runtime. Re-bake after editing the grid.
##
## Capture mode (automated screenshots):
##   godot ... <scene> -- --capture   -> renders every Marker3D in group "shots"

const LIGHTS := {
	# item name: [local offset (before cell rotation), color, energy, range, shadow]
	"floor_light": [Vector3(0, 3.6, 0), Color(1.0, 0.9, 0.76), 2.6, 9.0, true],
	"wall_light": [Vector3(0, 2.9, 1.6), Color(0.35, 0.88, 1.0), 0.9, 5.5, false],
	"wall_lamp": [Vector3(0, 2.8, 1.4), Color(1.0, 0.22, 0.15), 1.6, 5.5, false],
	"wall_console": [Vector3(0, 1.8, 1.4), Color(0.3, 0.85, 1.0), 0.6, 3.5, false],
	"wall_window": [Vector3(0, 2.1, 1.3), Color(0.45, 0.6, 1.0), 0.7, 4.5, false],
	"floor_grate": [Vector3(0, 0.35, 0), Color(0.25, 0.8, 1.0), 0.3, 2.5, false],
}
const DOOR_SCENE := preload("res://scenes/props/door.tscn")

# trim profile (metres)
const CH_Y := 3.25     # chamfer starts on the wall at this height
const CH_D := 0.75     # ...and reaches this far out along the ceiling
const KICK_H := 0.25
const KICK_D := 0.2

@export_tool_button("Bake trims, lights & doors", "Bake") var bake_action := bake

@onready var grid: GridMap = $Grid
var meta: Dictionary

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		_capture.call_deferred()
	elif "--playtest" in args:
		add_child(Playtest.new())   # dev tooling only
	elif "--vmcheck" in args:
		add_child(preload("res://scripts/vm_check.gd").new())

func bake() -> void:
	if grid == null:
		grid = $Grid
	var old := get_node_or_null("Baked")
	if old:
		remove_child(old)
		old.free()
	var baked := Node3D.new()
	baked.name = "Baked"
	add_child(baked)
	var root := self if owner == null else owner
	baked.owner = root
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/textures/tiles.json"))
	var trims := _build_trims()
	if trims:
		var mi := MeshInstance3D.new()
		mi.name = "Trims"
		mi.mesh = trims
		_own(baked, mi, root)
	_bake_cells(baked, root)

func _own(parent: Node, n: Node, root: Node) -> void:
	parent.add_child(n, true)
	n.owner = root

# ---------------------------------------------------------- cell queries ----
func _name_at(c: Vector3i) -> String:
	var it := grid.get_cell_item(c)
	return "" if it == GridMap.INVALID_CELL_ITEM else grid.mesh_library.get_item_name(it)

func _is_wall(c: Vector3i) -> bool:
	return _name_at(c).begins_with("wall")

func _is_open(c: Vector3i) -> bool:
	var n := _name_at(c)
	return n != "" and not n.begins_with("wall") and not n.begins_with("door")

# ------------------------------------------------------------ live cells ----
func _bake_cells(parent: Node, root: Node) -> void:
	for cell in grid.get_used_cells():
		var nm := _name_at(cell)
		var basis := grid.get_basis_with_orthogonal_index(grid.get_cell_item_orientation(cell))
		var origin := grid.map_to_local(cell)
		if LIGHTS.has(nm):
			var d: Array = LIGHTS[nm]
			var l := OmniLight3D.new()
			l.name = "Light_" + nm
			l.position = origin + basis * (d[0] as Vector3)
			l.light_color = d[1]
			l.light_energy = d[2]
			l.omni_range = d[3]
			l.omni_attenuation = 1.4
			l.shadow_enabled = d[4]
			_own(parent, l, root)
		elif nm == "door" or nm == "door_half":
			var door: Door = DOOR_SCENE.instantiate()
			door.name = "Door"
			if nm == "door_half":
				door.slab_mesh = load("res://kit/door_slab_half.res")
				door.open_offset = Vector3(-1.72, 0, 0)
				door.slab_width = 1.75
				door.slab_center_x = 0.125
			else:
				door.slab_mesh = load("res://kit/door_slab.res")
			door.transform = Transform3D(basis, origin)
			_own(parent, door, root)

# ----------------------------------------------------------------- trims ----
func _uv(tile: String, u: float, v: float) -> Vector2:
	var i: int = meta.tiles[tile]
	var cols: int = meta.cols
	var cell: float = meta.cell
	var pad: float = meta.pad
	var t: float = meta.tile
	var cx := float(i % cols) * cell + pad
	var cy := float(i / cols) * cell + pad
	return Vector2((cx + clampf(u, 0, 1) * t) / float(meta.width), (cy + (1.0 - clampf(v, 0, 1)) * t) / float(meta.height))

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, tile: String,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var fn := (b - a).cross(c - a).normalized()
	var pts := [a, b, c]
	var uvs := [ua, ub, uc]
	var order := [0, 2, 1] if fn.dot(n) > 0.0 else [0, 1, 2]   # Godot front = clockwise
	for k in order:
		st.set_normal(fn if fn.dot(n) > 0.0 else -fn)
		st.set_uv(_uv(tile, uvs[k].x, uvs[k].y))
		st.add_vertex(pts[k])

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, tile: String,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, n, tile, ua, ub, uc)
	_tri(st, a, c, d, n, tile, ua, uc, ud)

func _build_trims() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var count := 0
	for cell in grid.get_used_cells():
		if not _is_open(cell):
			continue
		var o := grid.map_to_local(cell)
		for di in dirs:
			if not _is_wall(cell + di):
				continue
			var d := Vector3(di)
			var t := Vector3(-d.z, 0, d.x)
			var n := -d
			# chamfer: wall @CH_Y -> ceiling @ (1-CH_D)
			var w0 := o + d - t + Vector3(0, CH_Y, 0)
			var w1 := o + d + t + Vector3(0, CH_Y, 0)
			var c1 := o + d * (1.0 - CH_D) + t + Vector3(0, 4, 0)
			var c0 := o + d * (1.0 - CH_D) - t + Vector3(0, 4, 0)
			_quad(st, w0, w1, c1, c0, (n + Vector3.DOWN).normalized(), "chamfer",
				Vector2(0, 0.47), Vector2(1, 0.47), Vector2(1, 1), Vector2(0, 1))
			# kick plate: floor @(1-KICK_D) -> wall @KICK_H
			var f0 := o + d * (1.0 - KICK_D) - t
			var f1 := o + d * (1.0 - KICK_D) + t
			var k1 := o + d + t + Vector3(0, KICK_H, 0)
			var k0 := o + d - t + Vector3(0, KICK_H, 0)
			_quad(st, f0, f1, k1, k0, (n + Vector3.UP).normalized(), "kick",
				Vector2(0, 0.2), Vector2(1, 0.2), Vector2(1, 0.55), Vector2(0, 0.55))
			count += 1
			# end caps where the run stops at a doorway
			for sgn in [-1.0, 1.0]:
				var side := cell + Vector3i(t * sgn)
				if _name_at(side).begins_with("door"):
					var e: Vector3 = o + t * sgn
					_tri(st, e + d + Vector3(0, CH_Y, 0), e + d + Vector3(0, 4, 0), e + d * (1.0 - CH_D) + Vector3(0, 4, 0),
						t * sgn, "trim", Vector2(0, 0), Vector2(0, 0.4), Vector2(0.4, 0.4))
					_tri(st, e + d * (1.0 - KICK_D), e + d, e + d + Vector3(0, KICK_H, 0),
						t * sgn, "trim", Vector2(0, 0), Vector2(0.15, 0), Vector2(0.15, 0.15))
		# outer corners: diagonal is wall, both orthogonal neighbours open
		for dx in [-1, 1]:
			for dz in [-1, 1]:
				if _is_wall(cell + Vector3i(dx, 0, dz)) and _is_open(cell + Vector3i(dx, 0, 0)) and _is_open(cell + Vector3i(0, 0, dz)) \
						and not _is_wall(cell + Vector3i(dx, 0, 0)) and not _is_wall(cell + Vector3i(0, 0, dz)):
					var p := o + Vector3(dx, CH_Y, dz)
					var a := o + Vector3(dx, 4, dz * (1.0 - CH_D))
					var b := o + Vector3(dx * (1.0 - CH_D), 4, dz)
					var m := o + Vector3(dx * (1.0 - CH_D), 4, dz * (1.0 - CH_D))
					var nn := Vector3(-dx, -1.4, -dz).normalized()
					_tri(st, p, a, m, nn, "chamfer", Vector2(0.5, 0.47), Vector2(0.5, 1), Vector2(0.9, 1))
					_tri(st, p, m, b, nn, "chamfer", Vector2(0.5, 0.47), Vector2(0.9, 1), Vector2(0.9, 0.47))
					var kp := o + Vector3(dx, KICK_H, dz)
					var ka := o + Vector3(dx, 0, dz * (1.0 - KICK_D))
					var kb := o + Vector3(dx * (1.0 - KICK_D), 0, dz)
					var km := o + Vector3(dx * (1.0 - KICK_D), 0, dz * (1.0 - KICK_D))
					var kn := Vector3(-dx, 1.4, -dz).normalized()
					_tri(st, kp, ka, km, kn, "kick", Vector2(0.3, 0.55), Vector2(0.3, 0.2), Vector2(0.5, 0.2))
					_tri(st, kp, km, kb, kn, "kick", Vector2(0.3, 0.55), Vector2(0.5, 0.2), Vector2(0.5, 0.55))
	if count == 0:
		return null
	var mesh := st.commit()
	mesh.surface_set_material(0, load("res://kit/kit_material.tres"))
	return mesh

# --------------------------------------------------------------- capture ----
func _capture() -> void:
	var cam := Camera3D.new()
	cam.fov = 80
	add_child(cam)
	cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene_name := scene_file_path.get_file().get_basename()
	for m in get_tree().get_nodes_in_group("shots"):
		cam.global_transform = (m as Node3D).global_transform
		for i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var path := "%s/%s_%s.png" % [out_dir, scene_name, m.name]
		img.save_png(path)
		print("captured ", path)
	get_tree().quit()
