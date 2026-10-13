class_name Door
extends Node3D
## Sliding door. Baked into levels by Level for each door / door_half cell.
## A door can be locked for a reason; the lamp over it and the prompt you get by
## looking at it say which. Switches and breakers unlock doors through Level.

## lock reason -> [prompt, lamp colour, lamp energy]
const LOCKS := {
	"none": ["", Color(0.35, 0.9, 1.0), 0.4],
	"power": ["No power", Color(0.0, 0.0, 0.0), 0.0],
	"jammed": ["Jammed", Color(1.0, 0.6, 0.15), 1.1],
	"inside": ["Locked from the inside", Color(1.0, 0.15, 0.1), 0.9],
	"lockdown": ["Lockdown", Color(0.95, 0.25, 0.9), 1.0],
	"seal": ["Pressure seal", Color(0.65, 0.85, 1.0), 0.9],
}

@export var slab_mesh: Mesh
## local offset when fully open (default: slide up into the header)
@export var open_offset := Vector3(0, 3.1, 0)
@export var slab_width := 1.5
@export var slab_center_x := 0.0
@export var open_distance := 4.5
@export var speed := 1.4
## why the door won't open ("none" = it opens when you walk up)
@export_enum("none", "power", "jammed", "inside", "lockdown", "seal") var lock := "none":
	set(v):
		lock = v
		if is_node_ready():
			_update_lamp()
## compatibility: true = locked for lack of power
var locked: bool:
	get:
		return lock != "none"
	set(v):
		lock = "power" if v else "none"

@onready var body: AnimatableBody3D = $Body
@onready var mesh_instance: MeshInstance3D = $Body/Mesh
@onready var shape: CollisionShape3D = $Body/Shape
@onready var lamp: OmniLight3D = $Lamp
@onready var sparks: CPUParticles3D = $Sparks
@onready var lamp_glow: MeshInstance3D = $LampGlow

var open_amount := 0.0
var player: Node3D
var _t := 0.0

func _ready() -> void:
	mesh_instance.mesh = slab_mesh
	var box := BoxShape3D.new()
	box.size = Vector3(slab_width, 3.25, 0.16)
	shape.shape = box
	shape.position = Vector3(slab_center_x, 1.625, 0)
	_update_lamp()
	if Engine.is_editor_hint():
		set_physics_process(false)

func _update_lamp() -> void:
	var d: Array = LOCKS.get(lock, LOCKS["none"])
	lamp.light_color = d[1]
	lamp.light_energy = d[2]
	lamp.visible = d[2] > 0.0
	sparks.emitting = lock == "jammed"
	var m := (lamp_glow.mesh as BoxMesh).material as ShaderMaterial
	m.set_shader_parameter("color", d[1] if d[2] > 0.0 else Color(0.08, 0.08, 0.09))
	m.set_shader_parameter("energy", 2.5 if d[2] > 0.0 else 1.0)

## Looking at a door: nothing to do, but a locked one says why.
func interact(_p: Node) -> void:
	pass

func can_use() -> bool:
	return false

func prompt() -> String:
	return LOCKS.get(lock, LOCKS["none"])[0]

func _physics_process(delta: float) -> void:
	_t += delta
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	var target := 0.0
	if lock == "none" and player and player.global_position.distance_to(global_position) < open_distance:
		target = 1.0
	open_amount = move_toward(open_amount, target, delta * speed)
	body.position = open_offset * smoothstep(0.0, 1.0, open_amount)
	# jammed: the slab shudders and the lamp stutters; lockdown: the lamp pulses
	if lock == "jammed":
		body.position.x = sin(_t * 31.0) * 0.012 * (1.0 if fmod(_t, 2.3) < 0.4 else 0.0)
		lamp.light_energy = 1.1 if fmod(_t * 7.3, 1.0) > 0.15 else 0.2
	elif lock == "lockdown":
		lamp.light_energy = 0.5 + 0.5 * absf(sin(_t * 3.0))
