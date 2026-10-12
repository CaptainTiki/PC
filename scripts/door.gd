class_name Door
extends Node3D
## Sliding door. Baked into levels by Level for each door / door_half cell.

@export var slab_mesh: Mesh
## local offset when fully open (default: slide up into the header)
@export var open_offset := Vector3(0, 3.1, 0)
@export var slab_width := 1.5
@export var slab_center_x := 0.0
@export var open_distance := 4.5
@export var speed := 1.4

@onready var body: AnimatableBody3D = $Body
@onready var mesh_instance: MeshInstance3D = $Body/Mesh
@onready var shape: CollisionShape3D = $Body/Shape

var open_amount := 0.0
var player: Node3D

func _ready() -> void:
	mesh_instance.mesh = slab_mesh
	var box := BoxShape3D.new()
	box.size = Vector3(slab_width, 3.25, 0.16)
	shape.shape = box
	shape.position = Vector3(slab_center_x, 1.625, 0)
	if Engine.is_editor_hint():
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	var target := 0.0
	if player and player.global_position.distance_to(global_position) < open_distance:
		target = 1.0
	open_amount = move_toward(open_amount, target, delta * speed)
	body.position = open_offset * smoothstep(0.0, 1.0, open_amount)
