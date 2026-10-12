extends SceneTree
## ASCII -> GridMap level scene.
## Run: godot --headless --path . -s tools/build_level.gd -- levels/test_room.txt
## Output: levels/<name>.tscn (fully editable GridMap afterwards).
##
## Walls auto-tile: each wall cell gets the profile piece matching its open sides
## and inside corners (see tools/build_kit.gd), rotated into place. Wall cells with
## no open neighbours (solid interior) are left empty. Feature walls (L, V, K...)
## need exactly one open side; otherwise they fall back to a plain auto piece.

const LEGEND := {
	"#": "wall", "C": "wall_bulkhead", "O": "wall_window", "H": "wall_hazard", "W": "wall_cables", "U": "wall_rust",
	"L": "wall_light", "V": "wall_vent", "K": "wall_console", "R": "wall_lamp", "P": "wall_pipes",
	".": "floor", ",": "floor_metal", "=": "floor_grate", "_": "floor_line", "*": "floor_light",
	"-": "floor_beam", "o": "pillar", "x": "crate", "X": "crate_stack", "D": "door", "@": "floor", "e": "floor",
}
const WALL_CHARS := "#CHWULVKRPO"

var rows: PackedStringArray

func ch(c: int, r: int) -> String:
	if r < 0 or r >= rows.size() or c < 0 or c >= rows[r].length():
		return " "
	return rows[r][c]

func is_open(s: String) -> bool:
	return s != " " and not WALL_CHARS.contains(s)

func is_wall(s: String) -> bool:
	return WALL_CHARS.contains(s)

# DIRS[i] in map space (x = col, y = row); matches build_kit.gd DIRS (+Z, +X, -Z, -X)
const MDIRS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const NAMED := {"1_0": "wall", "3_0": "wall_corner_out", "0_1": "wall_corner_in"}

func opens(c: int, r: int) -> bool:
	# for wall signatures: walkable floor only (doors count as wall)
	var s := ch(c, r)
	return s != " " and not WALL_CHARS.contains(s) and s != "D"

func rot_mask(m: int, k: int) -> int:
	var out := 0
	for i in 4:
		if m & (1 << i):
			out |= 1 << ((i + k) % 4)
	return out

func canonical(sides: int, diag: int) -> Array:
	var best := [999, 0, 0, 0]
	for k in 4:
		var key := rot_mask(sides, k) * 16 + rot_mask(diag, k)
		if key < best[0]:
			best = [key, rot_mask(sides, k), rot_mask(diag, k), k]
	return best

func wall_signature(c: int, r: int) -> Array:
	var sides := 0
	var diag := 0
	for i in 4:
		var d: Vector2i = MDIRS[i]
		if opens(c + d.x, r + d.y):
			sides |= 1 << i
	for j in 4:
		var a: Vector2i = MDIRS[j]
		var b: Vector2i = MDIRS[(j + 1) % 4]
		if not (sides & (1 << j)) and not (sides & (1 << ((j + 1) % 4))) and opens(c + a.x + b.x, r + a.y + b.y):
			diag |= 1 << j
	return [sides, diag]

func orient_k(k: int, grid: GridMap) -> int:
	return grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, k * PI / 2.0))

func orient_for(dir: Vector2i, grid: GridMap) -> int:
	# rotate so local +Z points along dir (x=col, y=row)
	var ang := atan2(float(dir.x), float(dir.y))
	return grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, ang))

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else "levels/test_room.txt"
	var text := FileAccess.open("res://" + src, FileAccess.READ).get_as_text()
	var parts := text.split("[shots]")
	rows = parts[0].strip_edges(false, true).split("\n")
	var lib: MeshLibrary = load("res://kit/kit.meshlib.res")
	var ids := {}
	for id in lib.get_item_list():
		ids[lib.get_item_name(id)] = id

	var root := Node3D.new()
	root.name = src.get_file().get_basename().to_pascal_case()
	root.set_script(load("res://scripts/level.gd"))

	var grid := GridMap.new()
	grid.name = "Grid"
	grid.mesh_library = lib
	grid.cell_size = Vector3(2, 4, 2)
	grid.cell_center_y = false
	grid.cell_octant_size = 4
	root.add_child(grid)
	grid.owner = root

	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	var player_pos := Vector3.ZERO
	var enemy_cells: Array[Vector3i] = []
	for r in rows.size():
		for c in rows[r].length():
			var s := rows[r][c]
			if not LEGEND.has(s):
				continue
			var item: String = LEGEND[s]
			var ori := 0
			if is_wall(s):
				var sig := wall_signature(c, r)
				if sig[0] == 0 and sig[1] == 0:
					continue                                   # solid interior: draw nothing
				var feature := s != "#"
				if feature and sig[1] == 0 and [1, 2, 4, 8].has(sig[0]):
					ori = orient_k([1, 2, 4, 8].find(sig[0]), grid)   # straight feature piece
				else:
					if feature:
						push_warning("feature wall '%s' at %d,%d isn't a straight run; using plain wall" % [s, c, r])
					var cn := canonical(sig[0], sig[1])
					var key := "%d_%d" % [cn[1], cn[2]]
					item = NAMED.get(key, "wall_auto_" + key)
					# canonical = rot(actual, k)  ->  actual = rot(canonical, 4-k)
					ori = orient_k((4 - int(cn[3])) % 4, grid)
			elif s == "_":
				for d in dirs:   # line goes on the -Z edge -> point -Z at the wall
					if is_wall(ch(c + d.x, r + d.y)):
						ori = orient_for(-d, grid)
						break
			elif s == "D" and (ch(c + 1, r) == "D" or ch(c - 1, r) == "D" or ch(c, r + 1) == "D" or ch(c, r - 1) == "D"):
				item = "door_half"
				if ch(c + 1, r) == "D":
					ori = 0                                    # jamb on -X
				elif ch(c - 1, r) == "D":
					ori = orient_for(Vector2i(0, -1), grid)    # 180: jamb on +X
				elif ch(c, r - 1) == "D":
					ori = orient_for(Vector2i(1, 0), grid)     # jamb on +Z
				else:
					ori = orient_for(Vector2i(-1, 0), grid)    # jamb on -Z
			elif s == "D":
				if is_wall(ch(c - 1, r)) and is_wall(ch(c + 1, r)):
					ori = 0
				else:
					ori = orient_for(Vector2i(1, 0), grid)
			grid.set_cell_item(Vector3i(c, 0, r), ids[item], ori)
			if s == "@":
				player_pos = grid.map_to_local(Vector3i(c, 0, r))
			elif s == "e":
				enemy_cells.append(Vector3i(c, 0, r))

	# environment
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.27, 0.3)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.1)
	env.fog_density = 0.015
	we.environment = env
	root.add_child(we)
	we.owner = root

	var player: Node3D = load("res://scenes/actors/player.tscn").instantiate()
	player.name = "Player"
	player.position = player_pos
	root.add_child(player)
	player.owner = root

	var enemies := Node3D.new()
	enemies.name = "Enemies"
	root.add_child(enemies)
	enemies.owner = root
	var drifter: PackedScene = load("res://scenes/actors/drifter.tscn")
	for ec in enemy_cells:
		var e: Node3D = drifter.instantiate()
		e.position = grid.map_to_local(ec) + Vector3(0, 1.3, 0)
		enemies.add_child(e, true)
		e.owner = root

	root.bake()

	# screenshot markers
	if parts.size() > 1:
		var shots := Node3D.new()
		shots.name = "Shots"
		root.add_child(shots)
		shots.owner = root
		for line in parts[1].split("\n"):
			var t := line.strip_edges().split(" ", false)
			if t.size() >= 6 and t[0] == "shot":
				var m := Marker3D.new()
				m.name = t[1]
				m.position = grid.map_to_local(Vector3i(int(t[2]), 0, int(t[3]))) + Vector3(0, 1.65, 0)
				m.rotation_degrees = Vector3(float(t[5]), float(t[4]), 0)
				m.add_to_group("shots", true)
				shots.add_child(m)
				m.owner = root

	var ps := PackedScene.new()
	ps.pack(root)
	var out := "res://levels/%s.tscn" % src.get_file().get_basename()
	print("saved ", out, " -> ", ResourceSaver.save(ps, out), "  cells=", grid.get_used_cells().size())
	quit()
