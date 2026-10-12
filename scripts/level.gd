@tool
class_name Level
extends Node3D
## Level root. Paint the GridMap, then press "Bake" (inspector) — this writes
## OmniLights for light cells and Door scenes for door cells into the scene as
## normal saved nodes under "Baked". Wall trims live in the wall pieces themselves.
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
}
const DOOR_SCENE := preload("res://scenes/props/door.tscn")

@export_tool_button("Bake lights & doors", "Bake") var bake_action := bake

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
