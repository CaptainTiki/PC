class_name Player
extends CharacterBody3D
## Boomer-shooter walker: brisk, not twitchy. All damage comes in via take_hit().

signal died

@export var speed := 7.0
@export var accel := 60.0
@export var max_health := 100.0

@onready var intent: PlayerInput = $Intent
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var weapon: Weapon = $Head/Camera/Weapon
@onready var hud: Hud = $Hud

var health := 100.0
var dead := false

func _ready() -> void:
	add_to_group("player")
	health = max_health
	camera.make_current()
	if not intent.bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_health(health, max_health)
	weapon.ammo_changed.connect(hud.set_ammo)
	hud.set_ammo(weapon.ammo, weapon.data.max_ammo)

func _physics_process(delta: float) -> void:
	if dead:
		velocity = velocity.move_toward(Vector3.ZERO, accel * delta)
		move_and_slide()
		return
	var l := intent.consume_look()
	rotate_y(l.x)
	head.rotation.x = clampf(head.rotation.x + l.y, -1.4, 1.4)
	var dir := (transform.basis * Vector3(intent.move.x, 0, intent.move.y))
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()
	weapon.set_motion(Vector2(velocity.x, velocity.z).length() / speed, delta)
	if intent.fire:
		weapon.try_fire()

## Single damage chokepoint.
func take_hit(amount: float, _point: Vector3, dir: Vector3, _source: Node) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	velocity += dir * 3.0
	hud.set_health(health, max_health)
	hud.flash_damage(clampf(amount / 25.0, 0.3, 1.0))
	if health <= 0.0:
		dead = true
		died.emit()
		var t := create_tween()
		t.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_QUAD)
		t.tween_interval(1.4)
		t.tween_callback(get_tree().reload_current_scene)

func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	hud.set_health(health, max_health)
