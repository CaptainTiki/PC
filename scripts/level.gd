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
	"floor_light": [Vector3(0, 3.6, 0), Color(1.0, 0.9, 0.76), 2.6, 9.0, false],
	"wall_light": [Vector3(0, 2.9, 0.85), Color(0.35, 0.88, 1.0), 0.9, 5.5, false],
	"wall_lamp": [Vector3(0, 2.75, 0.65), Color(1.0, 0.22, 0.15), 1.6, 5.5, false],
	"wall_console": [Vector3(0, 1.8, 0.65), Color(0.3, 0.85, 1.0), 0.6, 3.5, false],
	"wall_window": [Vector3(0, 2.0, 0.55), Color(0.45, 0.6, 1.0), 0.7, 4.5, false],
	"floor_grate": [Vector3(0, 0.35, 0), Color(0.25, 0.8, 1.0), 0.3, 2.5, false],
	# trim grid, ceiling slot (cell origin is 2m up)
	"chamfer_light": [Vector3(0, 1.3, 1.1), Color(0.55, 0.9, 1.0), 2.4, 8.5, false],
	"chamfer_light_broken": [Vector3(0, 1.3, 1.1), Color(0.55, 0.9, 1.0), 1.2, 6.0, false],
	# unpowered pieces bake their light switched off (see power_zones / power_on)
	"floor_light_off": [Vector3(0, 3.6, 0), Color(1.0, 0.9, 0.76), 2.6, 9.0, false],
	"chamfer_light_off": [Vector3(0, 1.3, 1.1), Color(0.55, 0.9, 1.0), 2.4, 8.5, false],
	"void_light": [Vector3(0, 3.6, 0), Color(1.0, 0.9, 0.76), 3.4, 12.5, false],
	"void_light_off": [Vector3(0, 3.6, 0), Color(1.0, 0.9, 0.76), 3.4, 12.5, false],
	"wall_light_off": [Vector3(0, 2.9, 0.85), Color(0.35, 0.88, 1.0), 0.9, 5.5, false],
	"shaft": [Vector3(0, 2.4, 0), Color(0.4, 0.85, 1.0), 0.8, 4.5, false],   # every other cell
}
## pieces that keep running on emergency power inside an unpowered zone
const EMERGENCY := ["wall_lamp"]
## lit piece -> unpowered twin (power_on swaps them back)
const POWER_SWAP := {"floor_light_off": "floor_light", "chamfer_light_off": "chamfer_light",
	"void_light_off": "void_light", "wall_light_off": "wall_light"}
const FLICKER := ["chamfer_light_broken"]
const DOOR_SCENE := preload("res://scenes/props/door.tscn")

@export_tool_button("Bake lights & doors", "Bake") var bake_action := bake
## Damaged areas in grid cells (x = column, y = row). Baked lights here run at
## `damage_light_scale` and some of them flicker.
@export var damaged_zones: Array[Rect2i] = []
@export var damage_light_scale := 0.45
## Unpowered areas (grid cells, all floors). Their lights bake switched off and
## their doors locked until a Breaker calls power_on(index).
@export var power_zones: Array[Rect2i] = []
## Door locks by grid cell (Vector3i -> "jammed" / "inside" / "lockdown" / "seal").
## Kept here so a re-bake keeps them; Switches unlock cells through unlock().
@export var door_locks: Dictionary = {}

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
	elif "--topdown" in args:
		add_child(preload("res://scripts/top_down.gd").new())
	elif "--flashcheck" in args:
		add_child(preload("res://scripts/flash_check.gd").new())
	elif "--deckcheck" in args:
		add_child(preload("res://scripts/deck03_check.gd").new())
	elif "--chaincheck" in args:
		add_child(preload("res://scripts/chain_check.gd").new())
	elif "--doorcheck" in args:
		add_child(preload("res://scripts/door_check.gd").new())
	elif "--mechcheck" in args:
		add_child(preload("res://scripts/mech_check.gd").new())
	elif "--vmcheck" in args:
		add_child(preload("res://scripts/vm_check.gd").new())

func bake() -> void:
	if grid == null:
		grid = $Grid
	var old := get_node_or_null("Baked")
	if old:
		remove_child(old)
		old.free()
	_doors.clear()
	var baked := Node3D.new()
	baked.name = "Baked"
	add_child(baked)
	var root := self if owner == null else owner
	baked.owner = root
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/textures/tiles.json"))
	for g in [get_node_or_null("Grid"), get_node_or_null("Trim"), get_node_or_null("Props")]:
		if g:
			_bake_cells(g, baked, root)

func _power_zone(cell: Vector3i) -> int:
	for i in power_zones.size():
		if power_zones[i].has_point(Vector2i(cell.x, cell.z)):
			return i
	return -1

## Breaker callback: lights on, ceiling pieces swapped to their lit versions, doors unlocked.
func power_on(zone: int) -> void:
	if zone < 0 or zone >= power_zones.size():
		return
	for g in [get_node_or_null("Grid"), get_node_or_null("Trim")]:
		if g == null:
			continue
		var gm := g as GridMap
		var ids := {}
		for id in gm.mesh_library.get_item_list():
			ids[gm.mesh_library.get_item_name(id)] = id
		for cell in gm.get_used_cells():
			if not power_zones[zone].has_point(Vector2i(cell.x, cell.z)):
				continue
			var nm := gm.mesh_library.get_item_name(gm.get_cell_item(cell))
			if POWER_SWAP.has(nm):
				gm.set_cell_item(cell, ids[POWER_SWAP[nm]], gm.get_cell_item_orientation(cell))
	for n in get_tree().get_nodes_in_group("power_%d" % zone):
		if n is Door and (n as Door).lock == "power":
			(n as Door).lock = "none"
		elif n is Light3D:
			(n as Light3D).visible = true
	_walk.clear()
	_flows.clear()
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_node("Hud"):
		p.get_node("Hud").toast("POWER RESTORED", Color(0.5, 0.95, 1.0))

## Baked door at a grid cell (null if none).
func door_at(cell: Vector3i) -> Door:
	if _doors.is_empty():
		var baked := get_node_or_null("Baked")
		if baked:
			for n in baked.get_children():
				if n is Door:
					_doors[grid.local_to_map((n as Door).position)] = n
	return _doors.get(cell)

## A door changed state on its own (one-way opened, keycard used): refresh navigation.
func doors_changed() -> void:
	_walk.clear()
	_flows.clear()

## Switch callback: unlock the doors on these cells (whatever their lock reason).
func unlock(cells: Array) -> void:
	for c in cells:
		var d := door_at(c)
		if d:
			d.lock = "none"
	_walk.clear()
	_flows.clear()

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
			if nm == "shaft" and (cell.x + cell.z) % 2 != 0:
				continue
			var d: Array = LIGHTS[nm]
			var l := OmniLight3D.new()
			l.name = "Light_" + nm
			l.position = origin + basis * (d[0] as Vector3)
			l.light_color = d[1]
			l.light_energy = d[2]
			l.omni_range = d[3]
			l.omni_attenuation = 1.4
			l.distance_fade_enabled = true
			l.distance_fade_begin = 30.0
			l.distance_fade_length = 10.0
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
			var pz := _power_zone(cell)
			if pz >= 0 and not nm in EMERGENCY:
				l.visible = false
				l.add_to_group("power_%d" % pz, true)
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
			var lk: String = door_locks.get(cell, "none")
			var parts := lk.split(":")
			door.lock = parts[0]
			if parts[0] == "oneway" and parts.size() > 1:
				# "oneway:n" = opens from the north side; turn that into the door's local side
				var wd: Vector3 = {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "e": Vector3(1, 0, 0), "w": Vector3(-1, 0, 0)}.get(parts[1], Vector3.BACK)
				door.open_side = 1 if (basis.inverse() * wd).z > 0.0 else -1
			elif parts[0] == "keycard" and parts.size() > 1:
				door.key_id = parts[1]
			var dz := _power_zone(cell)
			if dz >= 0:
				if door.lock == "none":
					door.lock = "power"
				door.add_to_group("power_%d" % dz, true)
			_own(parent, door, root)

# ------------------------------------------------------------ navigation ----
## Grid flow field: BFS over walkable structure cells (floors, doors, stairs,
## shafts, catwalks) across all floors, cached per goal cell. Stairs link a floor
## to the landing in front of their top on the floor above. Enemies and the
## playtest bot use it to get round walls, through doors and up/down stairs.
const WALKABLE := ["floor", "door", "stair", "shaft", "wall_shaft", "catwalk"]
const NDIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
var _walk := {}
var _stairs := {}     # cell -> [segment, ascent dir]
var _flows := {}
var _ladders := {}    # bottom cell <-> landing cell (only for climbers, i.e. the bot)
var _doors := {}      # cell -> baked Door

func _build_walk() -> void:
	for cell in grid.get_used_cells():
		var nm := grid.mesh_library.get_item_name(grid.get_cell_item(cell))
		for w in WALKABLE:
			if nm.begins_with(w):
				_walk[cell] = true
				break
		if nm.begins_with("door"):
			var d := door_at(cell)
			if d and d.lock != "none":
				_walk.erase(cell)      # locked doors are walls until unlocked
		if nm.begins_with("stair_"):
			var asc := grid.get_basis_with_orthogonal_index(grid.get_cell_item_orientation(cell)) * Vector3(0, 0, -1)
			_stairs[cell] = [int(nm.substr(6)), Vector3i(roundi(asc.x), 0, roundi(asc.z))]
	for l in find_children("*", "Ladder", true, false):
		var lad := l as Node3D
		var z := lad.global_transform.basis.z
		var bottom := cell_of(lad.global_position + z)
		var landing := cell_of(lad.global_position - z + Vector3(0, float(lad.get("height")), 0))
		_ladders[bottom] = landing
		_ladders[landing] = bottom

func is_walkable(c: Vector3i) -> bool:
	if _walk.is_empty():
		_build_walk()
	return _walk.has(c)

func _links(c: Vector3i, climb := false) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if climb and _ladders.has(c):
		out.append(_ladders[c])
	if _stairs.has(c):
		var k: int = _stairs[c][0]
		var d: Vector3i = _stairs[c][1]
		out.append(c - d)
		out.append(c + d + (Vector3i(0, 1, 0) if k == 2 else Vector3i.ZERO))
	else:
		for d in NDIRS:
			var n: Vector3i = c + d
			if _stairs.has(n):
				if _stairs[n][0] == 0 and _stairs[n][1] == d:
					out.append(n)          # step onto the bottom of a flight
				continue
			out.append(n)
			var below: Vector3i = n - Vector3i(0, 1, 0)
			if _stairs.has(below) and _stairs[below][0] == 2 and _stairs[below][1] == -d:
				out.append(below)          # landing -> top of a flight
	return out.filter(func(n: Vector3i) -> bool: return is_walkable(n))

func cell_of(p: Vector3) -> Vector3i:
	return grid.local_to_map(grid.to_local(p + Vector3(0, 0.3, 0)))

func _nearest_walkable(c: Vector3i) -> Vector3i:
	if is_walkable(c):
		return c
	var down := c - Vector3i(0, 1, 0)
	if is_walkable(down):
		return down
	for base in [c, down]:
		for d in NDIRS:
			if is_walkable(base + d):
				return base + d
	return c

func distance_field(goal: Vector3i, climb := false) -> Dictionary:
	goal = _nearest_walkable(goal)
	var key := [goal, climb]
	if _flows.has(key):
		return _flows[key]
	var dist := {goal: 0}
	var queue: Array[Vector3i] = [goal]
	var i := 0
	while i < queue.size():
		var c: Vector3i = queue[i]
		i += 1
		for n in _links(c, climb):
			if not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	if _flows.size() > 8:
		_flows.clear()
	_flows[key] = dist
	return dist

## Unit direction (XZ) from `from` toward the next cell on the way to `to`.
## climb: also use ladders (the playtest bot; enemies don't climb).
func flow_dir(from: Vector3, to: Vector3, climb := false) -> Vector3:
	var field := distance_field(cell_of(to), climb)
	var c := _nearest_walkable(cell_of(from))
	var best := c
	var best_d: int = field.get(c, 1 << 30)
	for n in _links(c, climb):
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
	if "--power" in OS.get_cmdline_user_args():   # capture with every zone powered
		for i in power_zones.size():
			power_on(i)
		scene_name += "_pw"
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
