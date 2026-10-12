@tool
class_name Level
extends Node3D
## Level root. Three GridMaps on one grid:
##   Grid  (structure, 2x4x2): wall faces, floors, doors
##   Trim  (2x2x2): slot y=0 floor trim (gutters), slot y=1 ceiling trim (chamfers, lights)
##   Props (2x4x2): runs that tile cell to cell (cable trays, pipes, beams, pillars)
## Paint, then press "Bake" (inspector): OmniLights for light pieces and Door scenes
## for door cells are written into the scene as normal saved nodes under "Baked".
## Nothing is generated at runtime. Re-bake after editing the grid.
##
## Capture mode (automated screenshots):
##   godot ... <scene> -- --capture   -> renders every Marker3D in group "shots"

const LIGHTS := {
	# item name: [local offset (before cell rotation), color, energy, range, shadow]
	"floor_light": [Vector3(0, 3.6, 0), Color(1.0, 0.9, 0.76), 2.6, 9.0, true],
	"wall_light": [Vector3(0, 2.9, 0.85), Color(0.35, 0.88, 1.0), 0.9, 5.5, false],
	"wall_lamp": [Vector3(0, 2.75, 0.65), Color(1.0, 0.22, 0.15), 1.6, 5.5, false],
	"wall_console": [Vector3(0, 1.8, 0.65), Color(0.3, 0.85, 1.0), 0.6, 3.5, false],
	"wall_window": [Vector3(0, 2.0, 0.55), Color(0.45, 0.6, 1.0), 0.7, 4.5, false],
	"floor_grate": [Vector3(0, 0.35, 0), Color(0.25, 0.8, 1.0), 0.3, 2.5, false],
	# trim grid, ceiling slot (cell origin is 2m up)
	"chamfer_light": [Vector3(0, 1.3, 1.1), Color(0.55, 0.9, 1.0), 2.4, 8.5, false],
	"chamfer_light_broken": [Vector3(0, 1.3, 1.1), Color(0.55, 0.9, 1.0), 1.2, 6.0, false],
}
const FLICKER := ["chamfer_light_broken"]
const DOOR_SCENE := preload("res://scenes/props/door.tscn")

@export_tool_button("Bake lights & doors", "Bake") var bake_action := bake
## Damaged areas in grid cells (x = column, y = row). Baked lights here run at
## `damage_light_scale` and some of them flicker.
@export var damaged_zones: Array[Rect2i] = []
@export var damage_light_scale := 0.45

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
	for g in [get_node_or_null("Grid"), get_node_or_null("Trim"), get_node_or_null("Props")]:
		if g:
			_bake_cells(g, baked, root)

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
func _bake_cells(g: GridMap, parent: Node, root: Node) -> void:
	for cell in g.get_used_cells():
		var nm := g.mesh_library.get_item_name(g.get_cell_item(cell))
		var basis := g.get_basis_with_orthogonal_index(g.get_cell_item_orientation(cell))
		var origin := g.map_to_local(cell)
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
			var hurt := false
			for z in damaged_zones:
				if z.has_point(Vector2i(cell.x, cell.z)):
					hurt = true
			if hurt:
				l.light_energy *= damage_light_scale
			if nm in FLICKER or (hurt and ((cell.x * 7 + cell.z * 13) % 3 == 0)):
				l.set_script(FlickerLight)
				l.base_energy = l.light_energy
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

# ------------------------------------------------------------ navigation ----
## Grid flow field: BFS over walkable structure cells (floors + doors), cached per
## goal cell. Enemies and the playtest bot use it to get round walls and through doors.
var _walk := {}
var _flows := {}
const NDIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

func is_walkable(c: Vector3i) -> bool:
	if _walk.is_empty():
		for cell in grid.get_used_cells():
			var nm := grid.mesh_library.get_item_name(grid.get_cell_item(cell))
			if nm.begins_with("floor") or nm.begins_with("door"):
				_walk[Vector3i(cell.x, 0, cell.z)] = true
	return _walk.has(Vector3i(c.x, 0, c.z))

func _nearest_walkable(c: Vector3i) -> Vector3i:
	if is_walkable(c):
		return c
	for d in NDIRS:
		if is_walkable(c + d):
			return c + d
	return c

func distance_field(goal: Vector3i) -> Dictionary:
	goal = _nearest_walkable(Vector3i(goal.x, 0, goal.z))
	if _flows.has(goal):
		return _flows[goal]
	var dist := {goal: 0}
	var queue: Array[Vector3i] = [goal]
	var i := 0
	while i < queue.size():
		var c: Vector3i = queue[i]
		i += 1
		for d in NDIRS:
			var n: Vector3i = c + d
			if not dist.has(n) and is_walkable(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	if _flows.size() > 8:
		_flows.clear()
	_flows[goal] = dist
	return dist

## Unit direction (XZ) from `from` toward the next cell on the way to `to`.
func flow_dir(from: Vector3, to: Vector3) -> Vector3:
	var field := distance_field(grid.local_to_map(grid.to_local(to)))
	var c := grid.local_to_map(grid.to_local(from))
	c = Vector3i(c.x, 0, c.z)
	var best := c
	var best_d: int = field.get(c, 1 << 30)
	for d in NDIRS:
		var n: Vector3i = c + d
		if field.has(n) and field[n] < best_d:
			best_d = field[n]
			best = n
	if best == c:
		return Vector3.ZERO      # already in the goal cell (or cut off)
	var p := grid.to_global(grid.map_to_local(best))
	var v := Vector3(p.x - from.x, 0, p.z - from.z)
	return v.normalized()

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
