extends SceneTree
## ASCII -> level scene with three GridMaps (Grid / Trim / Props) + placed scenes.
## Run: godot --headless --path . -s tools/build_level.gd -- levels/test_room.txt
## Output: levels/<name>.tscn — fully editable in the editor afterwards.
##
## Walls auto-tile: each wall cell gets the face piece matching its open sides and
## inside corners, plus matching trim (gutter in the floor slot, chamfer in the
## ceiling slot). Wall cells with no open neighbours are left empty.
##
## Floors: the map before any header is floor 0; "[floor 1]", "[floor 2]" ... start
## the next ones (4m apart, same columns/rows). A floor cell under open air on the
## floor above ('^' 'v' 'c' 'Q') automatically loses its ceiling.
##
## Legend
##   walls   #  plain          !  plain + lit chamfer     ?  plain + broken light
##           %  plain + glowing gutter
##           C bulkhead  H hazard  W cables  U rust  L wall light  V vent
##           K console   R red lamp  P pipe bay  O window      (features need a straight run)
##           g  interior glass window (room on both sides)
##   floors  .  deck   ,  tread plate   =  glowing grate   _  yellow edge line   * ceiling light
##   air     ^  open air (no floor; double-height / stairwell / hatch)   v  open air + ceiling light
##           ~  open air with no railings round it: a collapsed floor you're meant to drop through
##           c  catwalk (grating deck, railings added automatically next to open air)
##   levels  /  stair cell (declared in [stairs])     l  ladder (climbs the adjacent wall; the
##           cell above must be '^', the landing is the cell above that wall)
##           Q  elevator shaft (stack Q on consecutive floors; call buttons placed automatically)
##   tubes   d  crawl duct (crouch)   m  octagon maintenance shaft. Both auto-join; a wall cell
##           between a room and a tube becomes a duct/shaft mouth (ducts get a vent cover you
##           shoot off)
##   props   o  pillar   -  ceiling beam   +  beam crossing   t  cable tray (auto-joins)
##           p  vertical pipes (against the nearest wall)
##           n  waist-high cover (joins into runs)   j  console desk (back to the nearest wall)
##   clutter x  crate    X  crate stack    b  explosive canister    (free-placed scenes)
##   actors  @  player start   e  Drifter   s  Skitter
##   items   h  health   a  energy cells   E  section exit
##   other   D  door (DD = double door)    k  power breaker (against the nearest wall)
##           r  door release panel (on the nearest wall)   y  lockdown console (back to the wall)
##           q  crew keycard
##   climb   w  ledge: walkway 1.8 m up along this cell's walls (joins round corners)
##           z  ledge + a crate on the room side to jump up from
##           i  high crawl duct (floor 1.8 m up): its mouth is a vent at ledge height
##           u  climb cell under a ceiling grate: crate, ledge 2 m up on the wall, short ladder
##              up through the grate (the cell above must be 'G'; landing = cell above that wall)
##           G  ceiling grate: a hatch in this floor with a shootable grate (drop through it,
##              or climb up to it from a 'u' below)
##
## Sections after the maps:
##   [stairs]  stair <c> <r> <n|e|s|w> [floor]   bottom cell + ascent direction; the flight is
##             3 cells and lands on the floor above in the 4th cell
##   [power]   zone <c0> <r0> <c1> <r1>   unpowered area (all floors): lights off, doors locked.
##             Breakers 'k' power zones in reading order (floor 0 first, row by row).
##   [damage]  zone <c0> <r0> <c1> <r1>   damaged area: lights ~45%, some flicker or
##             are dead, ceiling trim goes patchy
##   [locks]   lock <c> <r> <f> <jammed|inside|lockdown|seal>   door lock (both halves of a double door)
##             lock <c> <r> <f> oneway <n|e|s|w>   opens only from that side, then stays open
##             lock <c> <r> <f> keycard [id]       opens once you carry that keycard (default crew)
##   [links]   link <c> <r> <f> to <c> <r> <f> [<c> <r> <f> ...]   switch ('r' / 'y') -> door cells it unlocks
##   [rooms]   room <template> <c> <r> <n|e|s|w> [floor] [variant]   stamps rooms/<template>.txt with its
##             door 'D' on cell c,r and the door facing n/e/s/w. Variant rolled per room if omitted.
##             In templates: '$' rolls loot (health / cells / nothing), '&' rolls a skitter or nothing.
##   [shots]   shot <name> <col> <row> <yaw> <pitch> [floor]   screenshot markers

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
	"k": "floor", "b": "floor", "n": "floor_metal", "j": "floor", "l": "floor_metal",
	"c": "catwalk", "r": "floor", "y": "floor", "u": "floor_metal", "q": "floor",
	"w": "floor", "z": "floor",
}
## things that can stand on a catwalk: with 2+ catwalk neighbours the cell is catwalk
const ON_CATWALK := "@eshaExXb"
const OPEN_ONLY := "/^vcQG~"     # open (not walls) but not plain floors
const AIR_ABOVE := "^vcQG~"      # cells that leave the floor below without a ceiling
const OPEN_VARIANT := {"floor": "floor_open", "floor_metal": "floor_metal_open", "floor_grate": "floor_grate_open",
	"floor_line": "floor_line_open", "floor_light": "floor_open", "floor_light_off": "floor_open"}
# DIRS[i] in map space (x = col, y = row); matches build_kit.gd DIRS (+Z, +X, -Z, -X)
const MDIRS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const TRAYS := {1: "tray_end", 3: "tray_corner", 5: "tray", 7: "tray_t", 15: "tray_cross"}
const TUBES := {1: "_end", 3: "_corner", 5: "", 7: "_t", 15: "_cross"}
const LEDGES := {1: "ledge", 3: "ledge_corner", 5: "ledge_both", 7: "ledge_u", 15: "ledge_ring"}
const RAILS := {1: "rail", 3: "rail_corner", 5: "rail_both", 7: "rail_u", 15: "rail_ring"}
const STAIR_DIRS := {"s": 0, "e": 1, "n": 2, "w": 3}   # -> MDIRS index of the ascent

var floors: Array = []            # Array[PackedStringArray]
var zones: Array[Rect2i] = []     # damage
var pzones: Array[Rect2i] = []    # power
var stairs := {}                  # Vector3i(c, f, r) -> [segment, MDIRS index]
var no_rail := {}                 # "c,f,r,i" -> true (stair landings, ladder exits)
var ladder_walls := {}            # Vector3i wall cells a ladder climbs
var overlay := {}                 # Vector3i -> actor/clutter char standing on a catwalk

func in_rects(rects: Array[Rect2i], c: int, r: int) -> int:
	for i in rects.size():
		if rects[i].has_point(Vector2i(c, r)):
			return i
	return -1

## deterministic per-cell coin flip (0..1)
func roll(c: int, r: int, salt := 0) -> float:
	return float(((c * 73856093) ^ (r * 19349663) ^ (salt * 83492791)) & 0xffff) / 65535.0

func ch(f: int, c: int, r: int) -> String:
	if f < 0 or f >= floors.size():
		return " "
	var rows: PackedStringArray = floors[f]
	if r < 0 or r >= rows.size() or c < 0 or c >= rows[r].length():
		return " "
	return rows[r][c]

func is_wall(s: String) -> bool:
	return WALLS.has(s) or s == "g"

func is_tube(s: String) -> bool:
	return s == "d" or s == "m" or s == "i"

func opens(f: int, c: int, r: int) -> bool:
	# for wall signatures: anything you can stand in or see across (doors count as wall)
	var s := ch(f, c, r)
	return (FLOORS.has(s) and s != "D") or OPEN_ONLY.contains(s)

## no floor here: open air
func is_air(f: int, c: int, r: int) -> bool:
	var s := ch(f, c, r)
	return s == "^" or s == "v" or s == "G" or s == "~" or (s == "Q" and ch(f - 1, c, r) == "Q")

func open_above(f: int, c: int, r: int) -> bool:
	return AIR_ABOVE.contains(ch(f + 1, c, r))

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

## [sides, diag, open neighbour cells]
func wall_signature(f: int, c: int, r: int) -> Array:
	var sides := 0
	var diag := 0
	var cells: Array[Vector2i] = []
	for i in 4:
		var d: Vector2i = MDIRS[i]
		if opens(f, c + d.x, r + d.y):
			sides |= 1 << i
			cells.append(Vector2i(c + d.x, r + d.y))
	for j in 4:
		var a: Vector2i = MDIRS[j]
		var b: Vector2i = MDIRS[(j + 1) % 4]
		if not (sides & (1 << j)) and not (sides & (1 << ((j + 1) % 4))) and opens(f, c + a.x + b.x, r + a.y + b.y):
			diag |= 1 << j
			cells.append(Vector2i(c + a.x + b.x, r + a.y + b.y))
	return [sides, diag, cells]

## wall cell between a room (side o) and a tube (opposite side): [tube char, o] or []
func tube_mouth(f: int, c: int, r: int, sides: int, diag: int) -> Array:
	if diag != 0 or not [1, 2, 4, 8].has(sides):
		return []
	var o: int = [1, 2, 4, 8].find(sides)
	var back: Vector2i = MDIRS[(o + 2) % 4]
	var t := ch(f, c + back.x, r + back.y)
	return [t, o] if is_tube(t) and tube_end(f, c + back.x, r + back.y) else []

## tubes only open into rooms at the ends of their runs (one tube neighbour or none)
func tube_end(f: int, c: int, r: int) -> bool:
	var n := 0
	for d in MDIRS:
		if ch(f, c + d.x, r + d.y) == ch(f, c, r):
			n += 1
	return n <= 1

func orient_k(k: int, g: GridMap) -> int:
	return g.get_orthogonal_index_from_basis(Basis(Vector3.UP, k * PI / 2.0))

## MDIRS index of the first wall next to (c, r), or -1
func wall_dir(f: int, c: int, r: int) -> int:
	for i in 4:
		var d: Vector2i = MDIRS[i]
		if is_wall(ch(f, c + d.x, r + d.y)):
			return i
	return -1

func new_grid(name: String, lib_path: String, cell: Vector3, lroot: Node) -> GridMap:
	var g := GridMap.new()
	g.name = name
	g.mesh_library = load(lib_path)
	g.cell_size = cell
	g.cell_center_y = false
	g.cell_octant_size = 2
	lroot.add_child(g)
	g.owner = lroot
	return g

func ids_of(g: GridMap) -> Dictionary:
	var ids := {}
	for id in g.mesh_library.get_item_list():
		ids[g.mesh_library.get_item_name(id)] = id
	return ids

func parse_rect(t: PackedStringArray) -> Rect2i:
	var a := Vector2i(int(t[1]), int(t[2]))
	var b := Vector2i(int(t[3]), int(t[4]))
	return Rect2i(a, b - a + Vector2i.ONE)

## a door cell plus the other half of a double door
func door_cells(cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = [cell]
	if ch(cell.y, cell.x, cell.z) != "D":
		push_warning("lock/link target %s is not a door" % cell)
	for d in MDIRS:
		if ch(cell.y, cell.x + d.x, cell.z + d.y) == "D":
			out.append(Vector3i(cell.x + d.x, cell.y, cell.z + d.y))
	return out

## rooms/<name>.txt: "[variant]" headers, each followed by an ASCII room drawn with its
## door at the bottom (facing south). Returns variant -> rows.
func load_template(name: String) -> Dictionary:
	var out := {}
	var cur := "default"
	var path := "res://rooms/%s.txt" % name
	if not FileAccess.file_exists(path):
		push_warning("no room template " + path)
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#!") or (t.begins_with(";")):
			continue
		if t.begins_with("[") and t.ends_with("]"):
			cur = t.substr(1, t.length() - 2)
			out[cur] = PackedStringArray()
			continue
		if t == "":
			continue
		if not out.has(cur):
			out[cur] = PackedStringArray()
		out[cur].append(line.rstrip(" \r"))
	return out

func rotate_cw(rows: PackedStringArray) -> PackedStringArray:
	var h := rows.size()
	var w := 0
	for row in rows:
		w = maxi(w, row.length())
	var out := PackedStringArray()
	for y in w:
		var line := ""
		for x in h:
			var row: String = rows[h - 1 - x]
			line += row[y] if y < row.length() else " "
		out.append(line)
	return out

func set_ch(f: int, c: int, r: int, v: String) -> void:
	while floors.size() <= f:
		floors.append(PackedStringArray())
	var rows: PackedStringArray = floors[f]
	while rows.size() <= r:
		rows.append("")
	var line: String = rows[r]
	while line.length() <= c:
		line += " "
	rows[r] = line.substr(0, c) + v + line.substr(c + 1)
	floors[f] = rows

## Stamp a room template with its door on (c, r), door facing `facing`.
func stamp_room(name: String, c: int, r: int, facing: String, f: int, variant: String) -> void:
	var tpl := load_template(name)
	if tpl.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d:%d" % [name, c, r, f])
	var keys := tpl.keys()
	if variant == "" or not tpl.has(variant):
		variant = keys[rng.randi() % keys.size()]
	var rows: PackedStringArray = tpl[variant]
	for i in {"s": 0, "w": 1, "n": 2, "e": 3}.get(facing, 0):
		rows = rotate_cw(rows)
	var anchor := Vector2i(-1, -1)
	for y in rows.size():
		var x := rows[y].find("D")
		if x >= 0:
			anchor = Vector2i(x, y)
			break
	if anchor.x < 0:
		push_warning("room template %s/%s has no door 'D'" % [name, variant])
		return
	for y in rows.size():
		for x in rows[y].length():
			var v := rows[y][x]
			if v == " ":
				continue
			if v == "$":
				var roll_v := rng.randf()
				v = "h" if roll_v < 0.3 else ("a" if roll_v < 0.65 else ".")
			elif v == "&":
				v = "s" if rng.randf() < 0.5 else "."
			set_ch(f, c + x - anchor.x, r + y - anchor.y, v)

var lroot: Node3D
var clutter: Node3D

func place(scene: PackedScene, pos: Vector3, yaw_k := 0.0, parent: Node = null) -> Node3D:
	var n: Node3D = scene.instantiate()
	n.position = pos
	n.rotation.y = yaw_k * PI / 2.0
	(parent if parent else clutter).add_child(n, true)
	n.owner = lroot
	return n

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else "levels/test_room.txt"
	var text := FileAccess.open("res://" + src, FileAccess.READ).get_as_text()
	var maps: Array = [[]]
	var sections := {"shots": [], "damage": [], "stairs": [], "power": [], "locks": [], "links": [], "rooms": []}
	var cur := "map"
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("[") and t.ends_with("]"):
			var tag := t.substr(1, t.length() - 2)
			if tag.begins_with("floor "):
				var fi := int(tag.substr(6))
				while maps.size() <= fi:
					maps.append([])
				cur = "floor:%d" % fi
				continue
			if sections.has(tag):
				cur = tag
				continue
		if cur == "map":
			maps[0].append(line)
		elif cur.begins_with("floor:"):
			maps[int(cur.substr(6))].append(line)
		else:
			sections[cur].append(line)
	for m in maps:
		var rows := PackedStringArray(m)
		while rows.size() > 0 and rows[rows.size() - 1].strip_edges() == "":
			rows.remove_at(rows.size() - 1)
		floors.append(rows)
	for line in sections.rooms:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 5 and t[0] == "room":
			stamp_room(t[1], int(t[2]), int(t[3]), t[4], int(t[5]) if t.size() > 5 else 0, t[6] if t.size() > 6 else "")
	for f in floors.size():
		var rows: PackedStringArray = floors[f]
		for r in rows.size():
			for c in rows[r].length():
				if not ON_CATWALK.contains(rows[r][c]):
					continue
				var n := 0
				for d in MDIRS:
					if ch(f, c + d.x, r + d.y) == "c":
						n += 1
				if n >= 2:
					overlay[Vector3i(c, f, r)] = rows[r][c]
		for cell in overlay:
			if cell.y == f:
				var line: String = rows[cell.z]
				rows[cell.z] = line.substr(0, cell.x) + "c" + line.substr(cell.x + 1)
		floors[f] = rows
	for line in sections.damage:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 5 and t[0] == "zone":
			zones.append(parse_rect(t))
	for line in sections.power:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 5 and t[0] == "zone":
			pzones.append(parse_rect(t))
	for line in sections.stairs:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 4 and t[0] == "stair":
			var di: int = STAIR_DIRS[t[3]]
			var d: Vector2i = MDIRS[di]
			var f := int(t[4]) if t.size() > 4 else 0
			var c0 := int(t[1])
			var r0 := int(t[2])
			for k in 3:
				var sc := Vector3i(c0 + d.x * k, f, r0 + d.y * k)
				if ch(f, sc.x, sc.z) != "/":
					push_warning("stair cell %s is not '/' on the map" % sc)
				stairs[sc] = [k, di]
			# top landing: no railing on the edge back toward the flight
			no_rail["%d,%d,%d,%d" % [c0 + d.x * 3, f + 1, r0 + d.y * 3, (di + 2) % 4]] = true

	var door_locks := {}
	for line in sections.locks:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 5 and t[0] == "lock":
			for dc in door_cells(Vector3i(int(t[1]), int(t[3]), int(t[2]))):
				door_locks[dc] = t[4] + (":" + t[5] if t.size() > 5 else "")
	var links := {}      # switch cell -> door cells
	for line in sections.links:
		var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
		if t.size() >= 8 and t[0] == "link" and t[4] == "to":
			var cells: Array[Vector3i] = []
			var i := 5
			while i + 2 < t.size():
				cells.append_array(door_cells(Vector3i(int(t[i]), int(t[i + 2]), int(t[i + 1]))))
				i += 3
			links[Vector3i(int(t[1]), int(t[3]), int(t[2]))] = cells

	lroot = Node3D.new()
	lroot.name = src.get_file().get_basename().to_pascal_case()
	lroot.set_script(load("res://scripts/level.gd"))
	lroot.damaged_zones = zones
	lroot.power_zones = pzones
	lroot.door_locks = door_locks
	var grid := new_grid("Grid", "res://kit/structure.meshlib.res", Vector3(2, 4, 2), lroot)
	var trim := new_grid("Trim", "res://kit/trim.meshlib.res", Vector3(2, 2, 2), lroot)
	var props := new_grid("Props", "res://kit/props.meshlib.res", Vector3(2, 4, 2), lroot)
	var sid := ids_of(grid)
	var tid := ids_of(trim)
	var pid := ids_of(props)

	clutter = Node3D.new()
	clutter.name = "Clutter"
	lroot.add_child(clutter)
	clutter.owner = lroot
	var devices := Node3D.new()
	devices.name = "Devices"
	lroot.add_child(devices)
	devices.owner = lroot
	var scenes := {
		"x": load("res://scenes/props/crate.tscn"), "X": load("res://scenes/props/crate_stack.tscn"),
		"h": load("res://scenes/props/pickup_health.tscn"), "a": load("res://scenes/props/pickup_cells.tscn"),
		"E": load("res://scenes/props/exit.tscn"), "b": load("res://scenes/props/explosive.tscn"),
	}
	var breaker_scene: PackedScene = load("res://scenes/props/breaker.tscn")
	var ladder_scene: PackedScene = load("res://scenes/props/ladder.tscn")
	var vent_scene: PackedScene = load("res://scenes/props/vent_cover.tscn")
	var elevator_scene: PackedScene = load("res://scenes/props/elevator.tscn")
	var post_scene: PackedScene = load("res://scenes/props/call_post.tscn")
	var release_scene: PackedScene = load("res://scenes/props/switch_panel.tscn")
	var grate_scene: PackedScene = load("res://scenes/props/ceiling_grate.tscn")
	var keycard_scene: PackedScene = load("res://scenes/props/keycard.tscn")
	var console_scene: PackedScene = load("res://scenes/props/switch_console.tscn")
	var switches := {}   # cell -> Switch

	var player_pos := Vector3.ZERO
	var enemy_cells: Array[Vector3i] = []
	var skitter_cells: Array[Vector3i] = []
	var breakers := 0
	var last_breaker: Breaker = null

	# ladders first: their wall cells skip ceiling trim, their landings skip a railing
	for f in floors.size():
		var rows: PackedStringArray = floors[f]
		for r in rows.size():
			for c in rows[r].length():
				var lch := rows[r][c]
				if lch != "l" and lch != "u":
					continue
				var li := -1
				for i in 4:
					var d: Vector2i = MDIRS[i]
					if is_wall(ch(f, c + d.x, r + d.y)) and FLOORS.has(ch(f + 1, c + d.x, r + d.y)):
						li = i
						break
				if li < 0:
					push_warning("ladder at %d,%d floor %d: needs a wall with a floor cell above it" % [c, r, f])
					continue
				if ch(f + 1, c, r) != "^" and ch(f + 1, c, r) != "G":
					push_warning("ladder at %d,%d floor %d: the cell above should be '^' or a grate 'G'" % [c, r, f])
				var d2: Vector2i = MDIRS[li]
				ladder_walls[Vector3i(c + d2.x, f, r + d2.y)] = true
				no_rail["%d,%d,%d,%d" % [c + d2.x, f + 1, r + d2.y, (li + 2) % 4]] = true
				var base := grid.map_to_local(Vector3i(c, f, r)) + Vector3(d2.x, 0, d2.y)
				if lch == "u":
					# climb: crate on the room side, a ledge 2 m up on the wall, short ladder to the grate
					var lad2 := place(ladder_scene, base + Vector3(0, 2.0, 0), (li + 2) % 4, devices) as Ladder
					lad2.height = 2.0
					lad2.name = "Ladder"
					props.set_cell_item(Vector3i(c, f, r), pid["ledge"], orient_k(li, props))
					var cr := place(scenes["x"], grid.map_to_local(Vector3i(c, f, r)) - Vector3(d2.x, 0, d2.y) * 0.45)
					cr.rotation.y = deg_to_rad(8.0)
				else:
					var lad := place(ladder_scene, base, (li + 2) % 4, devices)
					lad.name = "Ladder"

	for f in floors.size():
		var rows: PackedStringArray = floors[f]
		for r in rows.size():
			for c in rows[r].length():
				var s := rows[r][c]
				var cell := Vector3i(c, f, r)
				var pos := grid.map_to_local(cell)
				# ---------------------------------------------------------- walls
				if s == "g":
					var ns := opens(f, c, r - 1) and opens(f, c, r + 1)
					grid.set_cell_item(cell, sid["wall_glass"], 0 if ns else orient_k(1, grid))
					# glass is a wall open both ways: gutter below, chamfer above, on both sides
					trim.set_cell_item(Vector3i(c, 2 * f, r), tid["gutter_auto_5_0"], 0 if ns else orient_k(1, trim))
					trim.set_cell_item(Vector3i(c, 2 * f + 1, r), tid["chamfer_auto_5_0"], 0 if ns else orient_k(1, trim))
					continue
				if is_wall(s):
					var sig := wall_signature(f, c, r)
					if sig[0] == 0 and sig[1] == 0:
						continue                                    # solid interior: nothing
					var cn := canonical(sig[0], sig[1])
					var wori := orient_k((4 - int(cn[3])) % 4, grid)   # canonical -> actual
					var straight: bool = sig[1] == 0 and [1, 2, 4, 8].has(sig[0])
					var face_item := sig_name("wall", cn[1], cn[2])
					var feature: String = WALLS[s]
					var fori := wori
					var mouth := tube_mouth(f, c, r, sig[0], sig[1])
					if not mouth.is_empty():
						face_item = {"d": "wall_duct", "m": "wall_shaft", "i": "wall_hduct"}[mouth[0]]
						fori = orient_k(mouth[1], grid)
						if mouth[0] != "m":
							var vy := 1.8 if mouth[0] == "i" else 0.0
							var vc := place(vent_scene, pos + Vector3(MDIRS[mouth[1]].x, 0, MDIRS[mouth[1]].y) * 0.27 + Vector3(0, vy, 0), mouth[1], devices)
							vc.name = "VentCover"
					elif feature != "":
						if straight:
							face_item = feature
							if feature == "wall_light" and in_rects(pzones, c, r) >= 0:
								face_item = "wall_light_off"
							fori = orient_k([1, 2, 4, 8].find(sig[0]), grid)
						else:
							push_warning("feature '%s' at %d,%d needs a straight run; using plain wall" % [s, c, r])
					grid.set_cell_item(cell, sid[face_item], fori)
					# floor slot: gutter, or nothing where the wall drops into open air
					var cells: Array = sig[2]
					var n_air := 0
					var n_above := 0
					for oc in cells:
						if is_air(f, oc.x, oc.y):
							n_air += 1
						if open_above(f, oc.x, oc.y):
							n_above += 1
					var floor_trim := "gutter_glow" if s == "%" else "gutter"
					if (not mouth.is_empty() and mouth[0] != "i") or (n_air > 0 and n_air < cells.size()):
						floor_trim = "band_floor"
					if n_air < cells.size():
						trim.set_cell_item(Vector3i(c, 2 * f, r), tid[sig_name(floor_trim, cn[1], cn[2])], wori)
					# ceiling slot: chamfer (maybe lit), nothing under open air above
					var chamfer := sig_name("chamfer", cn[1], cn[2])
					var cori := wori
					var dmg := in_rects(zones, c, r) >= 0
					var unpowered := in_rects(pzones, c, r) >= 0
					if n_above == cells.size() or ladder_walls.has(cell):
						chamfer = ""
					elif n_above > 0:
						chamfer = sig_name("band_ceil", cn[1], cn[2])
					elif (s == "!" or s == "?") and straight:
						var broken := s == "?" or (dmg and roll(c, r, 1) < 0.5)
						chamfer = "chamfer_light_broken" if broken else ("chamfer_light_off" if unpowered else "chamfer_light")
						cori = orient_k([1, 2, 4, 8].find(sig[0]), trim)
					elif dmg and roll(c, r, 2) < 0.35:
						chamfer = ""                                 # patchy: missing ceiling trim
					if chamfer != "":
						trim.set_cell_item(Vector3i(c, 2 * f + 1, r), tid[chamfer], cori)
					continue
				# ---------------------------------------------------------- tubes
				if is_tube(s):
					var arms := 0
					for i in 4:
						var d: Vector2i = MDIRS[i]
						var n := ch(f, c + d.x, r + d.y)
						if n == s:
							arms |= 1 << i
						elif is_wall(n) and opens(f, c + d.x * 2, r + d.y * 2) and tube_end(f, c, r) \
								and wall_signature(f, c + d.x, r + d.y)[0] == 1 << i and wall_signature(f, c + d.x, r + d.y)[1] == 0:
							arms |= 1 << i                           # mouth into a room
					if arms == 0:
						arms = 5
					if not TUBES.has(canonical(arms, 0)[1]):
						arms = 5
					var tc := canonical(arms, 0)
					var prefix: String = {"d": "duct", "m": "shaft", "i": "hduct"}[s]
					grid.set_cell_item(cell, sid[prefix + TUBES[tc[1]]], orient_k((4 - int(tc[3])) % 4, grid))
					continue
				# ------------------------------------------------- open-air pieces
				if s == "^" or s == "v" or s == "G" or s == "~":
					if s == "G":
						var gr := place(grate_scene, pos, 0, devices)
						gr.name = "CeilingGrate"
					var item := "void_light" if s == "v" else "void"
					if s == "v" and in_rects(pzones, c, r) >= 0:
						item = "void_light_off"
					if open_above(f, c, r):
						item = "void_open"
					grid.set_cell_item(cell, sid[item], 0)
					continue
				if s == "/":
					if stairs.has(cell):
						var st: Array = stairs[cell]
						# stair pieces ascend toward local -Z: rotate so -Z points along the ascent
						grid.set_cell_item(cell, sid["stair_%d" % st[0]], orient_k((int(st[1]) + 2) % 4, grid))
					else:
						push_warning("'/' at %d,%d floor %d is not part of a [stairs] flight" % [c, r, f])
						grid.set_cell_item(cell, sid["floor"], 0)
					continue
				if s == "Q":
					var below := ch(f - 1, c, r) == "Q"
					var above := ch(f + 1, c, r) == "Q"
					var item := "void_open" if below and above else ("void" if below else ("floor_open" if above else "floor"))
					grid.set_cell_item(cell, sid[item], 0)
					if not below:
						var stops := PackedFloat32Array()
						var ff := f
						while ch(ff, c, r) == "Q":
							stops.append(0.02 + 4.0 * (ff - f))
							ff += 1
						var el := place(elevator_scene, pos, 0, devices) as Elevator
						el.name = "Elevator"
						el.stops = stops
						for si in stops.size():
							var placed := false
							for i in 4:
								var d: Vector2i = MDIRS[i]
								var nc := ch(f + si, c + d.x, r + d.y)
								if FLOORS.has(nc) and nc != "D":
									# call post beside the approach, on the edge shared with the shaft
									var side := Vector3(-d.y, 0, d.x)
									var pp := grid.map_to_local(Vector3i(c + d.x, f + si, r + d.y)) - Vector3(d.x, 0, d.y) * 0.75 + side * 0.72
									var post := place(post_scene, pp, i, devices) as ElevatorPanel
									post.name = "CallPost"
									post.elevator = el
									post.call_stop = si
									placed = true
									break
							if not placed:
								push_warning("elevator at %d,%d: no floor next to stop %d for a call button" % [c, r, si])
					continue
				if not FLOORS.has(s):
					continue
				# ---------------------------------------------------------- floors
				var item: String = FLOORS[s]
				if s == "*":
					if in_rects(zones, c, r) >= 0 and roll(c, r, 3) < 0.5:
						item = "floor"                               # dead ceiling light
					elif in_rects(pzones, c, r) >= 0:
						item = "floor_light_off"
				if open_above(f, c, r) and OPEN_VARIANT.has(item):
					item = OPEN_VARIANT[item]
				var ori := 0
				if s == "_":
					for i in 4:   # line is on the local -Z edge -> point -Z at the wall
						var d: Vector2i = MDIRS[i]
						if is_wall(ch(f, c + d.x, r + d.y)):
							ori = orient_k((i + 2) % 4, grid)
							break
				elif s == "D":
					if ch(f, c + 1, r) == "D" or ch(f, c - 1, r) == "D" or ch(f, c, r + 1) == "D" or ch(f, c, r - 1) == "D":
						item = "door_half"
						if ch(f, c + 1, r) == "D":
							ori = 0                       # jamb on -X
						elif ch(f, c - 1, r) == "D":
							ori = orient_k(2, grid)       # jamb on +X
						elif ch(f, c, r - 1) == "D":
							ori = orient_k(1, grid)
						else:
							ori = orient_k(3, grid)
					elif not (is_wall(ch(f, c - 1, r)) and is_wall(ch(f, c + 1, r))):
						ori = orient_k(1, grid)
				grid.set_cell_item(cell, sid[item], ori)
				s = overlay.get(cell, s)
				# railings: upper-floor walkable cells next to open air
				if f > 0 and s != "D":
					var rmask := 0
					for i in 4:
						var d: Vector2i = MDIRS[i]
						if is_air(f, c + d.x, r + d.y) and not "QG~".contains(ch(f, c + d.x, r + d.y)) and not no_rail.has("%d,%d,%d,%d" % [c, f, r, i]):
							rmask |= 1 << i
					if rmask != 0:
						var rc := canonical(rmask, 0)
						if RAILS.has(rc[1]):
							props.set_cell_item(cell, pid[RAILS[rc[1]]], orient_k((4 - int(rc[3])) % 4, props))
						else:   # opposite edges only
							props.set_cell_item(cell, pid["rail_both"], orient_k(0 if rmask == 5 else 1, props))
						if "o-+tpnj".contains(s):
							push_warning("prop '%s' at %d,%d floor %d replaced by a railing" % [s, c, r, f])
						if s != "k" and s != "l" and not "xXhaEb@es".contains(s):
							continue
				# props / clutter / actors
				match s:
					"o":
						props.set_cell_item(cell, pid["pillar"], 0)
					"-":
						var along_z := (ch(f, c, r - 1) == "-" or ch(f, c, r + 1) == "-") and not (ch(f, c - 1, r) == "-" or ch(f, c + 1, r) == "-")
						props.set_cell_item(cell, pid["beam"], orient_k(1, props) if along_z else 0)
					"+":
						props.set_cell_item(cell, pid["beam_cross"], 0)
					"t":
						var arms := 0
						for i in 4:
							var d: Vector2i = MDIRS[i]
							if ch(f, c + d.x, r + d.y) == "t":
								arms |= 1 << i
						if arms == 0:
							arms = 5
						var tc := canonical(arms, 0)
						props.set_cell_item(cell, pid[TRAYS[tc[1]]], orient_k((4 - int(tc[3])) % 4, props))
					"p":
						var wi := wall_dir(f, c, r)
						if wi >= 0:
							props.set_cell_item(cell, pid["pipes_vertical"], orient_k(wi, props))
					"n":
						var along_z := (ch(f, c, r - 1) == "n" or ch(f, c, r + 1) == "n") and not (ch(f, c - 1, r) == "n" or ch(f, c + 1, r) == "n")
						props.set_cell_item(cell, pid["cover"], orient_k(1, props) if along_z else 0)
					"w", "z":
						var lmask := 0
						var away := Vector2.ZERO
						for i in 4:
							var d: Vector2i = MDIRS[i]
							if is_wall(ch(f, c + d.x, r + d.y)):
								lmask |= 1 << i
								away -= Vector2(d)
						if lmask != 0:
							var lc := canonical(lmask, 0)
							if LEDGES.has(lc[1]):
								props.set_cell_item(cell, pid[LEDGES[lc[1]]], orient_k((4 - int(lc[3])) % 4, props))
							else:
								props.set_cell_item(cell, pid["ledge_both"], orient_k(0 if lmask == 5 else 1, props))
						if s == "z":
							# crate clear of the ledge's footprint, on the room side, so you can stand on it
							var dv := Vector2(signf(away.x), signf(away.y)) if away != Vector2.ZERO else Vector2(0, 1)
							var cz := place(scenes["x"], pos + Vector3(dv.x, 0, dv.y) * 0.72)
							cz.rotation.y = deg_to_rad(6.0)
					"j":
						var wi := wall_dir(f, c, r)
						props.set_cell_item(cell, pid["console_desk"], orient_k((wi + 2) % 4, props) if wi >= 0 else 0)
					"k":
						var wi := wall_dir(f, c, r)
						var d: Vector2i = MDIRS[maxi(wi, 0)]
						var bk := place(breaker_scene, pos + Vector3(d.x, 0, d.y) * 0.95, (maxi(wi, 0) + 2) % 4, devices) as Breaker
						bk.name = "Breaker"
						bk.zone = breakers
						last_breaker = bk
						if breakers >= pzones.size():
							push_warning("breaker %d at %d,%d has no [power] zone" % [breakers, c, r])
						breakers += 1
					"r":
						var wi := wall_dir(f, c, r)
						var d: Vector2i = MDIRS[maxi(wi, 0)]
						var sw := place(release_scene, pos + Vector3(d.x, 0, d.y) * 1.74, (maxi(wi, 0) + 2) % 4, devices) as Switch
						sw.name = "DoorRelease"
						switches[cell] = sw
					"y":
						var wi := wall_dir(f, c, r)
						var dy: Vector2i = MDIRS[wi] if wi >= 0 else Vector2i.ZERO
						# back against the wall so there's no pocket to get shoved into behind it
						var sw := place(console_scene, pos + Vector3(dy.x, 0, dy.y) * 0.7, (wi + 2) % 4 if wi >= 0 else 0, devices) as Switch
						sw.name = "LockdownConsole"
						switches[cell] = sw
					"x", "X":
						var crate := place(scenes[s], pos)
						crate.rotation.y = deg_to_rad(float((c * 37 + r * 91) % 31) - 15.0)
					"b":
						var can := place(scenes[s], pos + Vector3(0.35 * (roll(c, r, 5) - 0.5), 0, 0.35 * (roll(c, r, 6) - 0.5)))
						can.rotation.y = roll(c, r, 7) * TAU
					"h", "a", "E":
						place(scenes[s], pos)
					"q":
						place(keycard_scene, pos).name = "Keycard"
					"@":
						player_pos = pos
					"e":
						enemy_cells.append(cell)
					"s":
						skitter_cells.append(cell)

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
	lroot.add_child(we)
	we.owner = lroot

	var player: Node3D = load("res://scenes/actors/player.tscn").instantiate()
	player.name = "Player"
	player.position = player_pos
	lroot.add_child(player)
	player.owner = lroot

	var enemies := Node3D.new()
	enemies.name = "Enemies"
	lroot.add_child(enemies)
	enemies.owner = lroot
	var drifter: PackedScene = load("res://scenes/actors/drifter.tscn")
	for ec in enemy_cells:
		place(drifter, grid.map_to_local(ec) + Vector3(0, 1.3, 0), 0, enemies)
	var skitter: PackedScene = load("res://scenes/actors/skitter.tscn")
	for sc in skitter_cells:
		place(skitter, grid.map_to_local(sc) + Vector3(0, 0.05, 0), 0, enemies)

	if breakers == 1 and pzones.size() > 1:
		last_breaker.zone = -1          # one breaker, several zones: it powers them all
	for sc in links:
		if not switches.has(sc):
			push_warning("[links] %s has no switch ('r' or 'y') on the map" % sc)
			continue
		var sw: Switch = switches[sc]
		var cells: Array[Vector3i] = []
		cells.assign(links[sc])
		sw.targets = cells
		var reason: String = door_locks.get(cells[0], "") if cells.size() > 0 else ""
		sw.action = {"lockdown": "Lift lockdown", "seal": "Release seal"}.get(reason, "Release door")
	for sc in switches:
		if not links.has(sc):
			push_warning("switch at %s isn't linked to any door ([links])" % sc)

	lroot.bake()

	# screenshot markers
	if sections.shots.size() > 0:
		var shots := Node3D.new()
		shots.name = "Shots"
		lroot.add_child(shots)
		shots.owner = lroot
		for line in sections.shots:
			var t: PackedStringArray = (line as String).strip_edges().split(" ", false)
			if t.size() >= 6 and t[0] == "shot":
				var m := Marker3D.new()
				m.name = t[1]
				var sf := int(t[6]) if t.size() > 6 else 0
				m.position = grid.map_to_local(Vector3i(int(t[2]), sf, int(t[3]))) + Vector3(0, 1.65, 0)
				m.rotation_degrees = Vector3(float(t[5]), float(t[4]), 0)
				m.add_to_group("shots", true)
				shots.add_child(m)
				m.owner = lroot

	var ps := PackedScene.new()
	ps.pack(lroot)
	var out := "res://levels/%s.tscn" % src.get_file().get_basename()
	print("saved ", out, " -> ", ResourceSaver.save(ps, out), "  floors=", floors.size(), " structure=", grid.get_used_cells().size(),
		" trim=", trim.get_used_cells().size(), " props=", props.get_used_cells().size())
	quit()
