extends SceneTree
## ASCII -> level scene with three GridMaps (Grid / Trim / Props) + clutter scenes.
## Run: godot --headless --path . -s tools/build_level.gd -- levels/test_room.txt
## Output: levels/<name>.tscn — fully editable in the editor afterwards.
##
## Walls auto-tile: each wall cell gets the face piece matching its open sides and
## inside corners, plus matching trim (gutter in the Trim y=0 slot, chamfer in the
## y=1 slot). Wall cells with no open neighbours are left empty.
##
## Legend
##   walls   #  plain          !  plain + lit chamfer     ?  plain + broken light
##           %  plain + glowing gutter
##           C bulkhead  H hazard  W cables  U rust  L wall light  V vent
##           K console   R red lamp  P pipe bay  O window      (features need a straight run)
##   floors  .  deck   ,  tread plate   =  glowing grate   _  yellow edge line   * ceiling light
##   props   o  pillar   -  ceiling beam   +  beam crossing   t  cable tray (auto-joins)
##           p  vertical pipes (against the nearest wall)
##   clutter x  crate    X  crate stack   (free-placed scenes, not grid)
##   actors  @  player start   e  Drifter   s  Skitter
##   items   h  health   a  energy cells   E  section exit
##   other   D  door (DD = double door)
##
## Sections after the map:
##   [damage]  zone <c0> <r0> <c1> <r1>   damaged area: lights ~45%, some flicker or
##             are dead, ceiling trim goes patchy
##   [shots]   shot <name> <col> <row> <yaw> <pitch>   screenshot markers

const WALLS := {
	"#": "", "!": "", "?": "", "%": "",
	"C": "wall_bulkhead", "H": "wall_hazard", "W": "wall_cables", "U": "wall_rust", "L": "wall_light",
	"V": "wall_vent", "K": "wall_console", "R": "wall_lamp", "P": "wall_pipes", "O": "wall_window",
}
const FLOORS := {
	".": "floor", ",": "floor_metal", "=": "floor_grate", "_": "floor_line", "*": "floor_light",
	"o": "floor", "-": "floor", "+": "floor", "t": "floor", "p": "floor",
	"x": "floor", "X": "floor", "@": "floor", "e": "floor", "D": "door",
	"s": "floor", "h": "floor", "a": "floor", "E": "floor",
}
# DIRS[i] in map space (x = col, y = row); matches build_kit.gd DIRS (+Z, +X, -Z, -X)
const MDIRS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const TRAYS := {1: "tray_end", 3: "tray_corner", 5: "tray", 7: "tray_t", 15: "tray_cross"}

var rows: PackedStringArray
var zones: Array[Rect2i] = []

func in_zone(c: int, r: int) -> bool:
	for z in zones:
		if z.has_point(Vector2i(c, r)):
			return true
	return false

## deterministic per-cell coin flip (0..1)
func roll(c: int, r: int, salt := 0) -> float:
	return float(((c * 73856093) ^ (r * 19349663) ^ (salt * 83492791)) & 0xffff) / 65535.0

func ch(c: int, r: int) -> String:
	if r < 0 or r >= rows.size() or c < 0 or c >= rows[r].length():
		return " "
	return rows[r][c]

func is_wall(s: String) -> bool:
	return WALLS.has(s)

func opens(c: int, r: int) -> bool:
	# for wall signatures: walkable floor only (doors count as wall)
	var s := ch(c, r)
	return FLOORS.has(s) and s != "D"

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

func sig_name(prefix: String, sides: int, diag: int) -> String:
	var key := "%d_%d" % [sides, diag]
	var named := {"1_0": "", "3_0": "_corner_out", "0_1": "_corner_in"}
	if named.has(key):
		return prefix + named[key]
	return "%s_auto_%s" % [prefix, key]

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

func orient_k(k: int, g: GridMap) -> int:
	return g.get_orthogonal_index_from_basis(Basis(Vector3.UP, k * PI / 2.0))

func new_grid(name: String, lib_path: String, cell: Vector3, root: Node) -> GridMap:
	var g := GridMap.new()
	g.name = name
	g.mesh_library = load(lib_path)
	g.cell_size = cell
	g.cell_center_y = false
	g.cell_octant_size = 2
	root.add_child(g)
	g.owner = root
	return g

func ids_of(g: GridMap) -> Dictionary:
	var ids := {}
	for id in g.mesh_library.get_item_list():
		ids[g.mesh_library.get_item_name(id)] = id
	return ids

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else "levels/test_room.txt"
	var text := FileAccess.open("res://" + src, FileAccess.READ).get_as_text()
	var sections := {"map": [], "shots": [], "damage": []}
	var cur := "map"
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("[") and t.ends_with("]") and sections.has(t.substr(1, t.length() - 2)):
			cur = t.substr(1, t.length() - 2)
			continue
		sections[cur].append(line)
	rows = PackedStringArray(sections.map)
	while rows.size() > 0 and rows[rows.size() - 1].strip_edges() == "":
		rows.remove_at(rows.size() - 1)
	for line in sections.damage:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 5 and t[0] == "zone":
			var a := Vector2i(int(t[1]), int(t[2]))
			var b := Vector2i(int(t[3]), int(t[4]))
			zones.append(Rect2i(a, b - a + Vector2i.ONE))

	var root := Node3D.new()
	root.name = src.get_file().get_basename().to_pascal_case()
	root.set_script(load("res://scripts/level.gd"))
	root.damaged_zones = zones
	var grid := new_grid("Grid", "res://kit/structure.meshlib.res", Vector3(2, 4, 2), root)
	var trim := new_grid("Trim", "res://kit/trim.meshlib.res", Vector3(2, 2, 2), root)
	var props := new_grid("Props", "res://kit/props.meshlib.res", Vector3(2, 4, 2), root)
	var sid := ids_of(grid)
	var tid := ids_of(trim)
	var pid := ids_of(props)

	var clutter := Node3D.new()
	clutter.name = "Clutter"
	root.add_child(clutter)
	clutter.owner = root
	var crate_scenes := {"x": load("res://scenes/props/crate.tscn"), "X": load("res://scenes/props/crate_stack.tscn")}
	var item_scenes := {"h": load("res://scenes/props/pickup_health.tscn"), "a": load("res://scenes/props/pickup_cells.tscn"), "E": load("res://scenes/props/exit.tscn")}
	var skitter_cells: Array[Vector3i] = []

	var player_pos := Vector3.ZERO
	var enemy_cells: Array[Vector3i] = []
	for r in rows.size():
		for c in rows[r].length():
			var s := rows[r][c]
			var cell := Vector3i(c, 0, r)
			if is_wall(s):
				var sig := wall_signature(c, r)
				if sig[0] == 0 and sig[1] == 0:
					continue                                    # solid interior: nothing
				var cn := canonical(sig[0], sig[1])
				var wori := orient_k((4 - int(cn[3])) % 4, grid)   # canonical -> actual
				var straight: bool = sig[1] == 0 and [1, 2, 4, 8].has(sig[0])
				var face_item := sig_name("wall", cn[1], cn[2])
				var feature: String = WALLS[s]
				var fori := wori
				if feature != "":
					if straight:
						face_item = feature
						fori = orient_k([1, 2, 4, 8].find(sig[0]), grid)
					else:
						push_warning("feature '%s' at %d,%d needs a straight run; using plain wall" % [s, c, r])
				grid.set_cell_item(cell, sid[face_item], fori)
				var gutter := "gutter_glow" if s == "%" else "gutter"
				var chamfer := sig_name("chamfer", cn[1], cn[2])
				var cori := wori
				var dmg := in_zone(c, r)
				if (s == "!" or s == "?") and straight:
					var broken := s == "?" or (dmg and roll(c, r, 1) < 0.5)
					chamfer = "chamfer_light_broken" if broken else "chamfer_light"
					cori = orient_k([1, 2, 4, 8].find(sig[0]), trim)
				elif dmg and roll(c, r, 2) < 0.35:
					chamfer = ""                                 # patchy: missing ceiling trim
				trim.set_cell_item(Vector3i(c, 0, r), tid[sig_name(gutter, cn[1], cn[2])], wori)
				if chamfer != "":
					trim.set_cell_item(Vector3i(c, 1, r), tid[chamfer], cori)
				continue
			if not FLOORS.has(s):
				continue
			var item: String = FLOORS[s]
			if s == "*" and in_zone(c, r) and roll(c, r, 3) < 0.5:
				item = "floor"                                   # dead ceiling light
			var ori := 0
			if s == "_":
				for i in 4:   # line is on the local -Z edge -> point -Z at the wall
					var d: Vector2i = MDIRS[i]
					if is_wall(ch(c + d.x, r + d.y)):
						ori = orient_k((i + 2) % 4, grid)
						break
			elif s == "D":
				if ch(c + 1, r) == "D" or ch(c - 1, r) == "D" or ch(c, r + 1) == "D" or ch(c, r - 1) == "D":
					item = "door_half"
					if ch(c + 1, r) == "D":
						ori = 0                       # jamb on -X
					elif ch(c - 1, r) == "D":
						ori = orient_k(2, grid)       # jamb on +X
					elif ch(c, r - 1) == "D":
						ori = orient_k(1, grid)
					else:
						ori = orient_k(3, grid)
				elif not (is_wall(ch(c - 1, r)) and is_wall(ch(c + 1, r))):
					ori = orient_k(1, grid)
			grid.set_cell_item(cell, sid[item], ori)
			# props / clutter / actors
			match s:
				"o":
					props.set_cell_item(cell, pid["pillar"], 0)
				"-":
					var along_z := (ch(c, r - 1) == "-" or ch(c, r + 1) == "-") and not (ch(c - 1, r) == "-" or ch(c + 1, r) == "-")
					props.set_cell_item(cell, pid["beam"], orient_k(1, props) if along_z else 0)
				"+":
					props.set_cell_item(cell, pid["beam_cross"], 0)
				"t":
					var arms := 0
					for i in 4:
						var d: Vector2i = MDIRS[i]
						if ch(c + d.x, r + d.y) == "t":
							arms |= 1 << i
					if arms == 0:
						arms = 5
					var tc := canonical(arms, 0)
					props.set_cell_item(cell, pid[TRAYS[tc[1]]], orient_k((4 - int(tc[3])) % 4, props))
				"p":
					for i in 4:
						var d: Vector2i = MDIRS[i]
						if is_wall(ch(c + d.x, r + d.y)):
							props.set_cell_item(cell, pid["pipes_vertical"], orient_k(i, props))
							break
				"x", "X":
					var crate: Node3D = crate_scenes[s].instantiate()
					crate.position = grid.map_to_local(cell)
					crate.rotation.y = deg_to_rad(float((c * 37 + r * 91) % 31) - 15.0)
					clutter.add_child(crate, true)
					crate.owner = root
				"@":
					player_pos = grid.map_to_local(cell)
				"e":
					enemy_cells.append(cell)
				"s":
					skitter_cells.append(cell)
				"h", "a", "E":
					var it: Node3D = item_scenes[s].instantiate()
					it.position = grid.map_to_local(cell)
					clutter.add_child(it, true)
					it.owner = root

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
	var skitter: PackedScene = load("res://scenes/actors/skitter.tscn")
	for sc in skitter_cells:
		var e: Node3D = skitter.instantiate()
		e.position = grid.map_to_local(sc) + Vector3(0, 0.05, 0)
		enemies.add_child(e, true)
		e.owner = root

	root.bake()

	# screenshot markers
	if sections.shots.size() > 0:
		var shots := Node3D.new()
		shots.name = "Shots"
		root.add_child(shots)
		shots.owner = root
		for line in sections.shots:
			var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
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
	print("saved ", out, " -> ", ResourceSaver.save(ps, out), "  structure=", grid.get_used_cells().size(),
		" trim=", trim.get_used_cells().size(), " props=", props.get_used_cells().size())
	quit()
