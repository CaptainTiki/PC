extends Node
## Dev tooling (`-- --deckcheck`): walks deck03's three chains with teleports between
## steps, checking every gate, climb, drop and switch. PASS/FAIL per step, shots/deck_*.png.

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
	await _chain1()
	await _chain2()
	await _chain3()
	print("---- deck03 check done ----")
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _check(name: String, ok: bool, info := "") -> void:
	print("PASS " if ok else "FAIL ", name, "  ", info)

func _cap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/deck_%s.png" % [dir, tag])

func _pos(c: int, f: int, r: int) -> Vector3:
	return level.grid.to_global(level.grid.map_to_local(Vector3i(c, f, r)))

func _put(c: int, f: int, r: int, yaw: float, pitch := 0.0, off := Vector3.ZERO) -> void:
	p.global_position = _pos(c, f, r) + Vector3(0, 0.05, 0) + off
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

func _pop_near(at: Vector3) -> void:
	var best: VentCover = null
	for g in level.find_children("*", "VentCover", true, false):
		if best == null or (g as Node3D).global_position.distance_to(at) < best.global_position.distance_to(at):
			best = g
	best.take_hit(5.0, at, Vector3.DOWN, p)

func _in(c: Vector3i, x0: int, x1: int, f: int, r0: int, r1: int) -> bool:
	return c.x >= x0 and c.x <= x1 and c.y == f and c.z >= r0 and c.z <= r1

func _chain1() -> void:
	var cmd := level.door_at(Vector3i(10, 1, 19))
	var seal := level.door_at(Vector3i(28, 1, 20))
	_put(10, 1, 20, 0, 0)
	await _wait(1.2)
	await _cap("1_command_door")
	_check("command room locked from the corridor", cmd.lock == "oneway" and cmd.open_amount == 0.0 and _prompt() == "Opens from the other side", "'%s'" % _prompt())
	_put(27, 1, 20, -90, 0)
	await _wait(1.0)
	_check("seal blocks Corridor A", seal.lock == "seal" and _prompt() == "Pressure seal", "'%s'" % _prompt())
	# storeroom A: crate -> ledge -> high vent -> duct -> riser -> ladder
	_put(16, 1, 25, 135, 0)
	await _wait(0.3)
	p.intent.move = Vector2(0, -1)
	await _wait(0.1)
	p.intent.jump = true
	await _wait(0.7)
	p.intent.jump = true
	await _wait(0.9)
	p.intent.move = Vector2.ZERO
	await _wait(0.3)
	_check("storeroom A: crate and ledge", p.global_position.y > 1.5, "y %.2f" % p.global_position.y)
	await _cap("1_ledge")
	_put(19, 1, 23, -90, 0, Vector3(0.3, 1.8, 0))
	await _wait(0.3)
	_pop_near(_pos(20, 1, 23) + Vector3(0, 2.4, 0))
	_pop_near(_pos(23, 1, 23) + Vector3(0, 2.4, 0))
	p.intent.crouch = true
	await _wait(0.3)
	await _move(Vector2(0, -1), 4.5)
	p.intent.crouch = false
	await _wait(0.8)
	var rc := level.cell_of(p.global_position)
	_check("high duct into the riser", _in(rc, 24, 25, 1, 23, 24) and p.global_position.y < 4.5, "cell %s y %.2f" % [rc, p.global_position.y])
	_put(24, 1, 24, 180, 10)
	p.intent.move = Vector2(0, -1)
	await _wait(2.6)
	p.intent.move = Vector2.ZERO
	await _wait(0.5)
	await _cap("1_landing")
	_check("riser ladder up to maintenance", p.global_position.y > 7.9 and p.is_on_floor(), "y %.2f cell %s" % [p.global_position.y, level.cell_of(p.global_position)])
	# maintenance west: shaft -> pump closet -> fan room -> over the command room
	_put(25, 2, 23, 90, 0)
	await _move(Vector2(0, -1), 6.0)
	var sc := level.cell_of(p.global_position)
	_check("shaft to the pump closet", sc.x <= 16 and sc.y == 2, "cell %s" % sc)
	_put(15, 2, 21, 0, 0)
	await _move(Vector2(0, -1), 2.5)
	sc = level.cell_of(p.global_position)
	_check("pump closet door to the fan room", sc.z <= 19 and sc.y == 2, "cell %s" % sc)
	await _cap("1_fanroom")
	_put(12, 2, 17, 90, 0)
	await _move(Vector2(0, -1), 2.5)
	sc = level.cell_of(p.global_position)
	_check("fan room door to the room over the command room", sc.x <= 10, "cell %s" % sc)
	_put(8, 2, 16, -90, -40)
	await _wait(0.3)
	_pop_near(_pos(9, 2, 16))
	await _wait(0.3)
	await _move(Vector2(0, -1), 1.0)
	await _wait(1.2)
	await _cap("1_dropped")
	rc = level.cell_of(p.global_position)
	_check("drop into the command room", _in(rc, 7, 11, 1, 15, 18) and p.global_position.y < 4.5, "cell %s" % rc)
	_put(9, 1, 15, 0, -10)
	await _wait(0.4)
	var pr := _prompt()
	await _use()
	_check("red console releases the seal", seal.lock == "none" and pr == "Release seal", "'%s'" % pr)
	_put(10, 1, 18, 180, 0)
	await _wait(2.5)
	_check("command room door opens from inside", cmd.lock == "none" and cmd.open_amount > 0.9, "open %.2f" % cmd.open_amount)

func _chain2() -> void:
	var key_door := level.door_at(Vector3i(30, 1, 19))
	var sec := level.door_at(Vector3i(47, 1, 17))
	var shutter := level.door_at(Vector3i(46, 1, 26))
	var store_b := level.door_at(Vector3i(67, 1, 20))
	_put(30, 1, 20, 0, 0)
	await _wait(1.0)
	await _cap("2_keycard_door")
	_check("transit stem wants the keycard", key_door.lock == "keycard" and _prompt() == "Crew keycard required", "'%s'" % _prompt())
	_put(46, 1, 19, 0, 4)
	await _wait(1.0)
	await _cap("2_security_glass")
	_check("security post locked from the commons", sec.lock == "oneway" and sec.open_amount == 0.0)
	_check("stair shutter on lockdown", shutter.lock == "lockdown")
	_check("storeroom B has no power yet", store_b.lock == "power")
	# gym locker room hatch down to F0
	_put(44, 1, 31, 90, -60)
	await _move(Vector2(0, -1), 2.5)
	await _wait(1.0)
	var rc := level.cell_of(p.global_position)
	_check("locker room hatch down to maintenance", rc.y == 0 and p.global_position.y < 0.5, "cell %s y %.2f" % [rc, p.global_position.y])
	await _cap("2_f0")
	# power room breaker
	_put(48, 0, 26, -90, -5)
	await _wait(0.4)
	var pr := _prompt()
	await _use()
	await _wait(0.5)
	_check("breaker restores power", pr == "Restore power" and store_b.lock == "none", "'%s' storeroom B lock %s" % [pr, store_b.lock])
	# storeroom B ladder up, crawl over Corridor B to the room over the security post
	_put(70, 1, 22, 180, 10)
	p.intent.move = Vector2(0, -1)
	await _wait(2.6)
	p.intent.move = Vector2.ZERO
	await _wait(0.5)
	_check("storeroom B ladder up", p.global_position.y > 7.9 and p.is_on_floor(), "y %.2f" % p.global_position.y)
	_put(69, 2, 21, 90, 0)
	await _move(Vector2(0, -1), 7.5)
	rc = level.cell_of(p.global_position)
	_check("crawl west over Corridor B", rc.x <= 51 and rc.y == 2, "cell %s" % rc)
	_put(50, 2, 20, 0, 0)
	await _move(Vector2(0, -1), 3.0)
	rc = level.cell_of(p.global_position)
	_check("crawl north into the room over the post", rc.z <= 15 and rc.y == 2, "cell %s" % rc)
	await _cap("2_over_post")
	_put(44, 2, 15, -90, -40)
	await _wait(0.3)
	_pop_near(_pos(45, 2, 15))
	await _wait(0.3)
	await _move(Vector2(0, -1), 1.0)
	await _wait(1.2)
	rc = level.cell_of(p.global_position)
	_check("drop into the security post", _in(rc, 44, 47, 1, 14, 16) and p.global_position.y < 4.5, "cell %s" % rc)
	_put(45, 1, 15, 0, 0)
	await _wait(0.6)
	_check("keycard picked up", p.has_key("crew"))
	_put(46, 1, 15, 180, -25, Vector3(0, 0, 0.7))
	await _wait(0.4)
	pr = _prompt()
	await _use()
	_check("lockdown console raises the stair shutter", pr == "Lift lockdown" and shutter.lock == "none", "'%s'" % pr)
	_put(47, 1, 16, 180, 0)
	await _wait(2.5)
	_check("security post door opens from inside", sec.lock == "none" and sec.open_amount > 0.9)
	_put(30, 1, 21, 0, 0)
	await _wait(2.5)
	await _cap("2_keycard_open")
	_check("keycard opens the transit stem", key_door.lock == "none" and key_door.open_amount > 0.9)

func _chain3() -> void:
	_put(46, 1, 27, 0, 0)
	await _move(Vector2(0, -1), 4.0)
	await _wait(0.5)
	var rc := level.cell_of(p.global_position)
	_check("stairs up to the gallery", p.global_position.y > 7.9 and rc.y == 2, "y %.2f cell %s" % [p.global_position.y, rc])
	await _cap("3_gallery")
	_put(36, 2, 17, 0, 0)
	await _move(Vector2(0, -1), 4.0)
	await _wait(1.5)
	rc = level.cell_of(p.global_position)
	await _cap("3_dropped_c")
	_check("Corridor D's broken floor drops into Corridor C past the collapse", rc.y == 1 and rc.z >= 7 and rc.z <= 9 and rc.x >= 35, "cell %s y %.2f" % [rc, p.global_position.y])
	var ex := level.find_child("Exit", true, false) as Node3D
	_check("transit lift exit is east of the drop", ex != null and ex.global_position.x > p.global_position.x)
