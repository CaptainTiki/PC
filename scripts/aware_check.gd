extends Node
## Dev tooling (`-- --awarecheck`, deck03): spawns skitters in Corridor A and checks
## the awareness rules: dormant behind a door, slow notice at range, instant up
## close, instant when shot, hears gunfire through walls, and goes dormant again
## after losing the player.

var p: Player
var level: Level
const SKITTER := preload("res://scenes/actors/skitter.tscn")

func _ready() -> void:
	await get_tree().physics_frame
	level = get_tree().current_scene as Level
	for e in get_tree().current_scene.get_node("Enemies").get_children():
		e.queue_free()
	p = get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	await _wait(0.3)
	await _run()
	print("---- aware check done ----")
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

func _check(name: String, ok: bool, info := "") -> void:
	print("PASS " if ok else "FAIL ", name, "  ", info)

func _pos(c: int, f: int, r: int) -> Vector3:
	return level.grid.to_global(level.grid.map_to_local(Vector3i(c, f, r)))

func _put(c: int, f: int, r: int, yaw: float) -> void:
	p.global_position = _pos(c, f, r) + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(yaw)
	p.head.rotation.x = 0.0
	p.intent.move = Vector2.ZERO

func _spawn(c: int, f: int, r: int) -> Enemy:
	var e: Enemy = SKITTER.instantiate()
	get_tree().current_scene.get_node("Enemies").add_child(e)
	e.global_position = _pos(c, f, r) + Vector3(0, 0.05, 0)
	return e

func _run() -> void:
	# 1. behind a closed cabin door, player in the corridor outside (beyond the door's
	#    auto-open range): stays idle
	var a := _spawn(4, 1, 17)          # inside the cabin north of (4,19)
	_put(7, 1, 21, 0)
	await _wait(2.5)
	_check("idle behind a closed door", a.state == Enemy.State.IDLE, "state %d" % a.state)
	a.queue_free()
	# 2. in plain sight down Corridor A at ~18 m: not instant, but noticed within notice_time-ish
	var b := _spawn(22, 1, 20)
	_put(13, 1, 20, -90)
	await _wait(0.25)
	_check("far sighting is not instant", b.state == Enemy.State.IDLE, "state %d susp %.2f" % [b.state, b.suspicion])
	await _wait(2.0)
	_check("far sighting is noticed in a couple of seconds", b.state != Enemy.State.IDLE, "state %d susp %.2f" % [b.state, b.suspicion])
	_check("notice phase delays the charge", b.state == Enemy.State.NOTICE or b.state == Enemy.State.CHASE, "state %d" % b.state)
	b.queue_free()
	await _wait(0.2)
	# 3. close sighting: instant
	var c := _spawn(16, 1, 20)
	_put(14, 1, 20, -90)
	await _wait(0.25)
	_check("close sighting is instant", c.state != Enemy.State.IDLE, "state %d" % c.state)
	c.queue_free()
	await _wait(0.2)
	# 4. shot while idle: skips the notice twitch
	var d := _spawn(22, 1, 20)
	_put(13, 1, 20, -90)
	await get_tree().physics_frame
	d.take_hit(1.0, d.global_position, Vector3.ZERO, p)
	_check("being shot wakes it straight into the chase", d.state == Enemy.State.CHASE, "state %d" % d.state)
	# 5. gunfire wakes a neighbour through the wall within hear_radius, not one further away
	var near := _spawn(14, 1, 17)      # cabin at (14,19), ~6 m through the wall
	var far := _spawn(20, 1, 17)       # cabin at (20,19), ~12 m
	d.queue_free()
	await _wait(0.2)
	p.weapon.fired.emit()
	await _wait(0.2)
	_check("hears the gun through a wall nearby", near.state != Enemy.State.IDLE, "state %d" % near.state)
	_check("but not from far away", far.state == Enemy.State.IDLE, "state %d" % far.state)
	near.queue_free()
	far.queue_free()
	await _wait(0.2)
	# 6. lose the player: wakes, player teleports out of reach, it searches then goes dormant
	var g := _spawn(16, 1, 20)
	_put(14, 1, 20, -90)
	await _wait(0.4)
	_check("chasing", g.state == Enemy.State.NOTICE or g.state == Enemy.State.CHASE, "state %d" % g.state)
	_put(63, 1, 9, 0)                  # transit lobby, far away and out of sight
	g.sees = false                     # (the 0.15 s sight cache would otherwise "see" the teleport)
	_check("still hunting the last known spot", g.state != Enemy.State.IDLE, "state %d" % g.state)
	await _wait(g.data.lose_time + 1.5)
	_check("gives up and goes dormant", g.state == Enemy.State.IDLE, "state %d unseen %.1f at %s last_seen %s" % [g.state, g.unseen_t, g.global_position, g.last_seen])
	g.queue_free()
