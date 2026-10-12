class_name PlayerInput
extends Node
## Intent component: the only place that reads devices. Player consumes the
## intent fields; a bot (playtest) can drive them instead by setting bot = true.

@export var mouse_sensitivity := 0.0022
var bot := false
var move := Vector2.ZERO       # x = strafe, y = forward(-)/back(+)
var look := Vector2.ZERO       # radians this frame (yaw, pitch)
var fire := false

func _unhandled_input(e: InputEvent) -> void:
	if bot:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look += Vector2(-e.relative.x, -e.relative.y) * mouse_sensitivity
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	if bot:
		return
	move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	fire = Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func consume_look() -> Vector2:
	var l := look
	look = Vector2.ZERO
	return l
