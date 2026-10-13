extends Node
## Dev tooling (`-- --chaincheck`): plays the mini chain in levels/chain_test step by
## step: one-way door, seal, crate jump + ledge ladder through a ceiling grate,
## maintenance shaft, grate drop, seal release, keycard door. PASS/FAIL per step,
## shots/chain_*.png along the way.

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
	await _gates()
	await _climb()
	await _shaft()
	await _drop()
	await _release()
	await _keycard()
	print("---- chain check done ----")
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _check(name: String, ok: bool, info := "") -> void:
	print("PASS " if ok else "FAIL ", name, "  ", info)

func _cap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/chain_%s.png" % [dir, tag])

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

func _pop_grate_near(at: Vector3) -> void:
	var best: VentCover = null
	for g in level.find_children("*", "VentCover", true, false):
		if best == null or (g as Node3D).global_position.distance_to(at) < best.global_position.distance_to(at):
			best = g
	best.take_hit(5.0, at, Vector3.DOWN, p)

func _gates() -> void:
	var cmd := level.door_at(Vector3i(9, 0, 7))
	_put(9, 0, 8, 0, 0)
	await _wait(1.2)
	await _cap("oneway_outside")
	_check("one-way door shut from outside", cmd.lock == "oneway" and cmd.open_amount == 0.0, "lock %s open %.2f" % [cmd.lock, cmd.open_amount])
	_check("one-way prompt", _prompt() == "Opens from the other side", "'%s'" % _prompt())
	var kd := level.door_at(Vector3i(31, 0, 8))
	_put(30, 0, 8, -90, 0)
	await _wait(1.0)
	_check("keycard door prompt", _prompt() == "Crew keycard required" and kd.open_amount == 0.0, "'%s'" % _prompt())

func _climb() -> void:
	_put(13, 0, 11, 180, 0)
	await _wait(0.3)
	_pop_grate_near(_pos(13, 1, 13))
	await _cap("storeroom")
	p.intent.move = Vector2(0, -1)
	await _wait(0.15)
	p.intent.jump = true
	await _wait(0.9)
	var y_crate := p.global_position.y
	_check("jump onto the crate (or the ladder)", y_crate > 1.1, "y %.2f" % y_crate)
	await _wait(2.5)
	p.intent.move = Vector2.ZERO
	await _wait(0.5)
	await _cap("roomA")
	var y := p.global_position.y
	_check("ledge ladder up through the grate", y > 3.9 and p.is_on_floor(), "y %.2f cell %s" % [y, level.cell_of(p.global_position)])

func _shaft() -> void:
	_put(14, 1, 14, 0, 0)
	await _move(Vector2(0, -1), 5.0)
	await _cap("roomC")
	var z := p.global_position.z
	_check("maintenance shaft to room C", z < _pos(14, 1, 5).z + 1.0, "z %.2f" % z)

func _drop() -> void:
	_put(6, 1, 5, -90, -40)
	await _wait(0.3)
	_pop_grate_near(_pos(7, 1, 5))
	await _wait(0.3)
	await _cap("grate_open")
	await _move(Vector2(0, -1), 1.0)
	await _wait(1.2)
	await _cap("dropped")
	var c := level.cell_of(p.global_position)
	_check("drop through the grate into the command room", p.global_position.y < 0.5 and c.x >= 6 and c.x <= 10 and c.z >= 3 and c.z <= 6, "cell %s" % c)

func _release() -> void:
	var seal := level.door_at(Vector3i(16, 0, 8))
	_put(8, 0, 3, 0, -10)
	await _wait(0.4)
	var pr := _prompt()
	await _use()
	_check("seal release from the command room", seal.lock == "none" and pr == "Release seal", "'%s'" % pr)
	var cmd := level.door_at(Vector3i(9, 0, 7))
	_put(9, 0, 6, 180, 0)
	await _wait(2.5)
	_check("one-way door opens from inside", cmd.lock == "none" and cmd.open_amount > 0.9, "open %.2f" % cmd.open_amount)
	_put(9, 0, 9, 0, 0)
	await _wait(1.0)
	_check("and stays open as a shortcut", cmd.open_amount > 0.9)

func _keycard() -> void:
	var kd := level.door_at(Vector3i(31, 0, 8))
	_put(22, 0, 4, 0, 0)
	await _wait(0.6)
	_check("pick up the keycard", p.has_key("crew"))
	_put(29, 0, 8, -90, 0)
	await _wait(2.5)
	await _cap("keycard_open")
	_check("keycard door opens", kd.lock == "none" and kd.open_amount > 0.9, "open %.2f" % kd.open_amount)
