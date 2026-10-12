class_name Enemy
extends CharacterBody3D
## Flat sprite anomaly. Floats, keeps its preferred range, lobs slow projectiles.
## All damage arrives through take_hit().

enum State { IDLE, CHASE, WINDUP, PAIN, DEAD }

const MASK_WORLD := 1

@export var data: EnemyData

@onready var sprite: MeshInstance3D = $Sprite
@onready var eye: Marker3D = $Eye
@onready var glow: OmniLight3D = $Glow
@onready var shape: CollisionShape3D = $Shape

var state := State.IDLE
var health := 0.0
var target: Node3D
var state_t := 0.0
var attack_t := 0.0
var anim_t := 0.0
var flash := 0.0
var home_y := 0.0
var rng := RandomNumberGenerator.new()
var mat: ShaderMaterial
var strafe_dir := 1.0

func _ready() -> void:
	add_to_group("enemies")
	health = data.max_health
	mat = sprite.get_active_material(0) as ShaderMaterial
	rng.randomize()
	attack_t = rng.randf_range(0.6, data.attack_interval)
	home_y = global_position.y
	anim_t = rng.randf() * 4.0

func _physics_process(delta: float) -> void:
	state_t += delta
	anim_t += delta
	flash = move_toward(flash, 0.0, delta * 8.0)
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	match state:
		State.IDLE:
			_set_frame(data.frames_idle[int(anim_t * data.anim_fps) % data.frames_idle.size()])
			if target and global_position.distance_to(target.global_position) < data.wake_range and _can_see():
				_enter(State.CHASE)
		State.CHASE:
			_set_frame(data.frames_idle[int(anim_t * data.anim_fps) % data.frames_idle.size()])
			_steer(delta)
			attack_t -= delta
			if attack_t <= 0.0 and _can_see():
				_enter(State.WINDUP)
		State.WINDUP:
			_set_frame(data.frame_attack)
			velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
			move_and_slide()
			if state_t >= data.attack_windup:
				_fire()
				attack_t = data.attack_interval * rng.randf_range(0.8, 1.2)
				_enter(State.CHASE)
		State.PAIN:
			_set_frame(data.frame_pain)
			velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
			move_and_slide()
			if state_t > 0.18:
				_enter(State.CHASE)
		State.DEAD:
			var f := int(state_t * 10.0)
			_set_frame(data.frames_death[mini(f, data.frames_death.size() - 1)])
			glow.light_energy = maxf(0.0, glow.light_energy - delta * 6.0)
			if f >= data.frames_death.size() + 2:
				queue_free()
	if mat:
		mat.set_shader_parameter("flash", flash)

func _enter(s: State) -> void:
	state = s
	state_t = 0.0

func _set_frame(f: int) -> void:
	if mat:
		mat.set_shader_parameter("frame", f)

func _can_see() -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye.global_position, target.global_position + Vector3(0, 1.5, 0), MASK_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _steer(delta: float) -> void:
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := to / maxf(dist, 0.001)
	var side := Vector3(-fwd.z, 0, fwd.x) * strafe_dir
	if rng.randf() < delta * 0.4:
		strafe_dir = -strafe_dir
	var push := 0.0
	if dist > data.preferred_range + 1.5:
		push = 1.0
	elif dist < data.preferred_range - 2.0:
		push = -0.7
	var want := (fwd * push + side * 0.45).normalized() * data.move_speed
	var bob := sin(anim_t * 2.2) * 0.25
	want.y = (home_y + bob - global_position.y) * 3.0
	velocity = velocity.move_toward(want, 10.0 * delta)
	move_and_slide()

func _fire() -> void:
	if data.projectile == null or target == null:
		return
	var p: Projectile = data.projectile.instantiate()
	get_tree().current_scene.add_child(p)
	var aim := target.global_position + Vector3(0, 1.3, 0)
	p.launch(eye.global_position, (aim - eye.global_position).normalized() * data.projectile_speed, data.projectile_damage, self)

## Single damage chokepoint.
func take_hit(amount: float, _point: Vector3, dir: Vector3, _source: Node) -> void:
	if state == State.DEAD:
		return
	health -= amount
	flash = 1.0
	velocity += dir
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if health <= 0.0:
		_die()
	elif state != State.WINDUP and rng.randf() < data.pain_chance:
		_enter(State.PAIN)
	elif state == State.IDLE:
		_enter(State.CHASE)

func _die() -> void:
	_enter(State.DEAD)
	shape.set_deferred("disabled", true)
	collision_layer = 0
	velocity = Vector3.ZERO
	if data.death_fx:
		var fx: Node3D = data.death_fx.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position
