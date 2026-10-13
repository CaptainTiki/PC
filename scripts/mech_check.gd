extends Node
## Dev tooling (`-- --mechcheck`): scripted checks of the traversal / device kit in
## the current level (built for levels/deck02). Enemies are removed first. Prints
## PASS/FAIL per mechanic and saves shots/mech_*.png along the way.

var p: Player
var level: Level
var results: PackedStringArray = []
var dir := ""

func _ready() -> void:
	print("mech check start")
	dir = ProjectSettings.globalize_path("res://shots")
	await get_tree().physics_frame
	level = get_tree().current_scene as Level
	for e in get_tree().current_scene.get_node("Enemies").get_children():
		e.queue_free()
	p = get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	await _wait(0.3)
	await _explosives()
	await _duct()
	await _ladder()
	await _elevator()
	await _breaker()
	print("---- mech check ----")
	for r in results:
		print(r)
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _check(name: String, ok: bool, info := "") -> void:
	print("PASS " if ok else "FAIL ", name, "  ", info)
	results.append("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])

func _cap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/mech_%s.png" % [dir, tag])

func _put(cell: Vector3i, yaw_deg: float, pitch := 0.0) -> void:
	p.global_position = level.grid.to_global(level.grid.map_to_local(cell)) + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(yaw_deg)
	p.head.rotation.x = deg_to_rad(pitch)
	p.intent.move = Vector2.ZERO
	p.intent.crouch = false

func _move(v: Vector2, secs: float) -> void:
	p.intent.move = v
	await _wait(secs)
	p.intent.move = Vector2.ZERO

func _explosives() -> void:
	var cans: Array[Node] = level.find_children("*", "Explosive", true, false)
	var a: Explosive = null
	var target := level.grid.to_global(level.grid.map_to_local(Vector3i(18, 0, 3)))
	for c in cans:
		if a == null or (c as Node3D).global_position.distance_to(target) < a.global_position.distance_to(target):
			a = c
	_put(Vector3i(21, 0, 3), 90, -10)       # looking west at the pair
	await _wait(0.4)
	await _cap("explode_0")
	var before := level.find_children("*", "Explosive", true, false).size()
	a.take_hit(20.0, a.global_position, Vector3.ZERO, p)
	await get_tree().physics_frame
	await _cap("explode_1")
	await _wait(0.25)
	await _cap("explode_2")
	await _wait(0.6)
	var after := level.find_children("*", "Explosive", true, false).size()
	_check("explosive chain", before - after >= 2, "canisters %d -> %d, player hp %.0f" % [before, after, p.health])

func _duct() -> void:
	# room A, facing the duct mouth in the south wall
	_put(Vector3i(3, 0, 6), 180, -8)
	await _wait(0.3)
	await _cap("duct_0")
	await _move(Vector2(0, -1), 1.2)
	var z_stand := p.global_position.z
	var mouth_z := level.grid.to_global(level.grid.map_to_local(Vector3i(3, 0, 7))).z
	_check("vent cover blocks", z_stand < mouth_z, "z %.2f (mouth %.2f)" % [z_stand, mouth_z])
	var cover: VentCover = null
	for v in level.find_children("*", "VentCover", true, false):
		if cover == null or (v as Node3D).global_position.distance_to(p.global_position) < cover.global_position.distance_to(p.global_position):
			cover = v
	cover.take_hit(5.0, cover.global_position, Vector3(0, 0, 1), p)
	await _wait(0.4)
	await _move(Vector2(0, -1), 1.2)
	var z_up := p.global_position.z
	_check("standing can't enter duct", z_up < mouth_z + 0.3, "z %.2f" % z_up)
	p.intent.crouch = true
	await _wait(0.3)
	await _move(Vector2(0, -1), 2.0)
	await _cap("duct_1")
	var z_in := p.global_position.z
	var duct_z := level.grid.to_global(level.grid.map_to_local(Vector3i(3, 0, 8))).z
	_check("crouch into duct", z_in > duct_z - 0.6, "z %.2f (duct %.2f)" % [z_in, duct_z])
	# turn east along the duct and crawl to the far end (atrium)
	p.rotation.y = deg_to_rad(-90)
	p.head.rotation.x = 0
	await _move(Vector2(0, -1), 7.0)
	await _cap("duct_2")
	var x_end := p.global_position.x
	var exit_x := level.grid.to_global(level.grid.map_to_local(Vector3i(13, 0, 8))).x
	_check("crawl the duct", x_end > exit_x - 1.0, "x %.2f (end %.2f)" % [x_end, exit_x])
	p.intent.crouch = false
	await _wait(0.3)

func _ladder() -> void:
	var lad := level.find_child("Ladder", true, false) as Node3D
	var bottom := lad.global_position + lad.global_transform.basis.z * 1.0
	p.global_position = bottom + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.rotation.y = lad.global_rotation.y
	p.head.rotation.x = deg_to_rad(10)
	await _wait(0.3)
	await _cap("ladder_0")
	p.intent.move = Vector2(0, -1)
	await _wait(1.0)
	await _cap("ladder_1")
	await _wait(2.0)
	p.intent.move = Vector2.ZERO
	await _wait(0.5)
	await _cap("ladder_2")
	var y := p.global_position.y - lad.global_position.y
	_check("climb ladder", y > 3.8 and p.is_on_floor(), "height %.2f on_floor %s" % [y, p.is_on_floor()])

func _elevator() -> void:
	var el := level.find_child("Elevator", true, false) as Elevator
	var post: ElevatorPanel = null
	for n in level.find_children("*", "ElevatorPanel", true, false):
		if (n as ElevatorPanel).call_stop == 0:
			post = n
	# go to the mezzanine (stop 1), call the lift up, step on, ride down
	el.go_to(1)
	await _wait(2.5)
	_check("call button", post != null and post.prompt() != "", post.prompt() if post else "no post")
	post.interact(p)          # call it back down to stop 0
	await _wait(2.5)
	_check("elevator called", el.stop == 0 and not el.moving, el.status())
	p.global_position = el.global_position + Vector3(-0.3, 0.3, 0.3)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(180)
	p.head.rotation.x = deg_to_rad(5)
	await _wait(0.5)
	var panel := el.get_node("Platform/RidePanel") as ElevatorPanel
	panel.interact(p)
	await _wait(0.8)
	await _cap("elevator_0")
	await _wait(2.5)
	await _cap("elevator_1")
	var y := p.global_position.y - el.global_position.y
	_check("ride elevator", y > 3.8, "player height %.2f, %s" % [y, el.status()])

func _breaker() -> void:
	var b := level.find_child("Breaker", true, false) as Breaker
	var doors := get_tree().get_nodes_in_group("power_%d" % b.zone).filter(func(n): return n is Door)
	var locked_before := doors.filter(func(d): return d.locked).size()
	var lights_before := get_tree().get_nodes_in_group("power_%d" % b.zone).filter(func(n): return n is Light3D and n.visible).size()
	_put(Vector3i(16, 0, 5), 90, 10)
	await _wait(0.4)
	await _cap("power_0")
	b.interact(p)
	await _wait(0.6)
	await _cap("power_1")
	var locked_after := doors.filter(func(d): return d.locked).size()
	var lights_after := get_tree().get_nodes_in_group("power_%d" % b.zone).filter(func(n): return n is Light3D and n.visible).size()
	_check("breaker restores power", locked_before > 0 and locked_after == 0 and lights_after > lights_before,
		"locked %d -> %d, lights %d -> %d" % [locked_before, locked_after, lights_before, lights_after])
