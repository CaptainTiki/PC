class_name Weapon
extends Node3D
## Hitscan weapon held by the camera. Data comes from a WeaponData resource.

signal ammo_changed(ammo: int, max_ammo: int)
signal fired

const MASK_WORLD := 1
const MASK_ENEMY := 4

@export var data: WeaponData
@export var impact_fx: PackedScene
@export var tracer_fx: PackedScene

@onready var viewmodel: MeshInstance3D = $Viewmodel
@onready var muzzle: Marker3D = $Viewmodel/Muzzle
@onready var flash_light: OmniLight3D = $Viewmodel/Muzzle/FlashLight
@onready var flash_mesh: MeshInstance3D = $Viewmodel/Muzzle/FlashMesh

var ammo := 0
var cooldown := 0.0
var recoil := 0.0
var bob_t := 0.0
var bob_amount := 0.0
var rng := RandomNumberGenerator.new()
var flash_t := 0.0
var flash_frames := 0

func _ready() -> void:
	ammo = data.start_ammo
	viewmodel.mesh = data.viewmodel
	viewmodel.position = data.viewmodel_offset
	flash_light.visible = false
	flash_mesh.visible = false

func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	recoil = move_toward(recoil, 0.0, delta * 5.0)
	var r := ease(recoil, 0.6)
	bob_t += delta * 9.0 * bob_amount
	var bob := Vector3(cos(bob_t) * 0.012, absf(sin(bob_t)) * 0.016, 0) * bob_amount
	viewmodel.position = data.viewmodel_offset + bob + Vector3(0, 0.01, data.recoil_kick) * r
	viewmodel.rotation.x = deg_to_rad(data.recoil_pitch_deg) * r
	if flash_light.visible:
		flash_t -= delta
		flash_frames += 1
		if flash_t <= 0.0 and flash_frames > 2:
			flash_light.visible = false
			flash_mesh.visible = false

func set_motion(amount: float, delta: float) -> void:
	bob_amount = move_toward(bob_amount, clampf(amount, 0.0, 1.0), delta * 6.0)

func add_ammo(n: int) -> void:
	ammo = mini(ammo + n, data.max_ammo)
	ammo_changed.emit(ammo, data.max_ammo)

func try_fire() -> bool:
	if cooldown > 0.0 or ammo < data.ammo_per_shot:
		return false
	cooldown = data.fire_interval
	ammo -= data.ammo_per_shot
	ammo_changed.emit(ammo, data.max_ammo)
	recoil = 1.0
	flash_light.visible = true
	flash_mesh.visible = true
	flash_t = 0.05
	flash_frames = 0
	flash_mesh.rotation.z = rng.randf() * TAU
	_shoot()
	fired.emit()
	return true

func _shoot() -> void:
	var cam := get_parent() as Node3D
	var origin := cam.global_position
	var basis := cam.global_basis
	var space := get_world_3d().direct_space_state
	var shooter := owner as CollisionObject3D
	var hits := {}
	for i in data.pellets:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * deg_to_rad(data.spread_deg)
		var dir := (basis * Vector3(cos(a) * tan(r), sin(a) * tan(r), -1.0)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * data.max_range, MASK_WORLD | MASK_ENEMY)
		if shooter:
			q.exclude = [shooter.get_rid()]
		var res := space.intersect_ray(q)
		var end: Vector3 = origin + dir * data.max_range
		if res:
			end = res.position
			var col: Object = res.collider
			if col.has_method("take_hit"):
				hits[col] = hits.get(col, 0.0) + data.damage
				col.take_hit(data.damage, res.position, dir * data.knockback / data.pellets, owner)
			elif impact_fx:
				_spawn(impact_fx, res.position, res.normal)
		if tracer_fx:
			var t: Tracer = tracer_fx.instantiate()
			get_tree().current_scene.add_child(t)
			t.setup(muzzle.global_position, end, data.tracer_color)

func _spawn(scene: PackedScene, pos: Vector3, normal: Vector3) -> void:
	var fx: Node3D = scene.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = pos + normal * 0.05
	if normal.cross(Vector3.UP).length() > 0.01:
		fx.look_at(pos + normal, Vector3.UP)
