extends Node
## Dev tooling (`-- --doorcheck`): scripted checks for door states, switches and
## the duct / riser / ladder detour in levels/kit03_test. Prints PASS/FAIL per
## check and saves shots/door_*.png.

var p: Player
var level: Level
var dir := ""

func _ready() -> void:
	dir = ProjectSettings.globalize_path("res://shots")
	await get_tree().physics_frame
	level = get_tree().current_scene as Level
	for e in get_tree().current_scene.get_node("Enemies").get_children():
		e.queue_free()
	p = get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	await _wait(0.3)
	await _jammed()
	await _duct_down()
	await _ladder_up()
	await _inside()
	await _lockdown()
	await _seal()
	print("---- door check done ----")
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _check(name: String, ok: bool, info := "") -> void:
	print("PASS " if ok else "FAIL ", name, "  ", info)

func _cap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/door_%s.png" % [dir, tag])

func _pos(c: int, f: int, r: int) -> Vector3:
	return level.grid.to_global(level.grid.map_to_local(Vector3i(c, f, r)))

func _put(c: int, f: int, r: int, yaw: float, pitch := 0.0) -> void:
	p.global_position = _pos(c, f, r) + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(yaw)
	p.head.rotation.x = deg_to_rad(pitch)
	p.intent.move = Vector2.ZERO
	p.intent.crouch = false

func _move(v: Vector2, secs: float) -> void:
	p.intent.move = v
	await _wait(secs)
	p.intent.move = Vector2.ZERO

func _prompt() -> String:
	var t: Object = p._look_target
	return t.prompt() if t and t.has_method("prompt") else ""

func _use() -> void:
	p.intent.use = true
	await get_tree().physics_frame
	await get_tree().physics_frame

func _pop_covers_near(at: Vector3, n: int) -> void:
	var covers := level.find_children("*", "VentCover", true, false)
	covers.sort_custom(func(a, b): return (a as Node3D).global_position.distance_to(at) < (b as Node3D).global_position.distance_to(at))
	for i in mini(n, covers.size()):
		(covers[i] as VentCover).take_hit(5.0, at, Vector3.FORWARD, p)

func _jammed() -> void:
	_put(17, 1, 8, -90, 0)
	await _wait(1.5)
	await _cap("jammed")
	var d := level.door_at(Vector3i(18, 1, 8))
	_check("jammed door stays shut", d.lock == "jammed" and d.open_amount == 0.0, "open %.2f" % d.open_amount)
	_check("jammed prompt", _prompt() == "Jammed", "'%s'" % _prompt())
	_check("jammed cell blocks the flow field", not level.is_walkable(Vector3i(18, 1, 8)))

func _duct_down() -> void:
	_put(14, 1, 5, 0, -10)
	await _wait(0.3)
	_pop_covers_near(_pos(16, 1, 2), 2)
	p.intent.crouch = true
	await _wait(0.3)
	await _move(Vector2(0, -1), 1.8)
	await _cap("duct_corner")
	var z := p.global_position.z
	_check("crawl into the utility duct", z < _pos(14, 1, 3).z - 0.5, "z %.2f" % z)
	p.rotation.y = deg_to_rad(-90)
	await _move(Vector2(0, -1), 3.5)
	p.intent.crouch = false
	await _wait(0.4)
	var x := p.global_position.x
	_check("crawl to the riser landing", x > _pos(19, 1, 2).x - 0.8 and p.global_position.y > 3.5, "x %.2f y %.2f" % [x, p.global_position.y])
	await _cap("riser")
	p.head.rotation.x = deg_to_rad(-60)
	await _move(Vector2(0, -1), 3.0)
	await _wait(0.8)
	await _cap("ladder_down")
	var y := p.global_position.y
	_check("down the riser ladder into maintenance", y < 0.6, "y %.2f" % y)

func _ladder_up() -> void:
	_put(21, 0, 6, 90, 10)
	await _wait(0.3)
	p.intent.move = Vector2(0, -1)
	await _wait(2.6)
	p.intent.move = Vector2.ZERO
	await _wait(0.5)
	await _cap("closet")
	var y := p.global_position.y
	var cl := level.cell_of(p.global_position)
	_check("up the ladder into the closet", y > 3.8 and p.is_on_floor(), "y %.2f cell %s" % [y, cl])

func _inside() -> void:
	var door := level.door_at(Vector3i(23, 1, 10))
	_put(23, 1, 9, 180, -5)
	await _wait(1.2)
	await _cap("inside_locked")
	_check("inside-locked door stays shut", door.lock == "inside" and door.open_amount == 0.0)
	_check("inside-locked prompt", _prompt() == "Locked from the inside", "'%s'" % _prompt())
	# round through the rec room duct
	_put(29, 1, 12, 90, -5)
	await _wait(0.3)
	_pop_covers_near(_pos(27, 1, 12), 2)
	p.intent.crouch = true
	await _wait(0.3)
	await _move(Vector2(0, -1), 3.0)
	p.intent.crouch = false
	await _wait(0.4)
	var x := p.global_position.x
	_check("crawl from the rec room into the security post", x < _pos(24, 1, 12).x + 0.8, "x %.2f" % x)
	_put(21, 1, 12, 90, -10)
	await _wait(0.4)
	await _cap("release_panel")
	var pr := _prompt()
	await _use()
	_check("door release", door.lock == "none" and pr == "Release door", "prompt '%s', lock %s" % [pr, door.lock])
	_put(23, 1, 11, 0, 0)
	await _wait(2.5)
	_check("released door opens", door.open_amount > 0.9, "open %.2f" % door.open_amount)

func _lockdown() -> void:
	var a := level.door_at(Vector3i(36, 1, 8))
	var b := level.door_at(Vector3i(36, 1, 9))
	_put(23, 1, 12, 180, -25)
	await _wait(0.4)
	await _cap("console")
	var pr := _prompt()
	await _use()
	_check("lockdown console", a.lock == "none" and b.lock == "none" and pr == "Lift lockdown", "prompt '%s'" % pr)

func _seal() -> void:
	var d := level.door_at(Vector3i(31, 1, 7))
	_put(31, 1, 8, 0, -5)
	await _wait(0.8)
	await _cap("seal_locked")
	_check("seal prompt from the corridor", _prompt() == "Pressure seal" and d.open_amount == 0.0, "'%s'" % _prompt())
	_put(35, 1, 4, -90, -10)
	await _wait(0.4)
	var pr := _prompt()
	await _use()
	_check("seal release", d.lock == "none" and pr == "Release seal", "prompt '%s'" % pr)
	_check("seal cell walkable again", level.is_walkable(Vector3i(31, 1, 7)))
