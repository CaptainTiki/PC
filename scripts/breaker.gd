class_name Breaker
extends StaticBody3D
## Power breaker: restores power to its Level power zone (lights + locked doors).

@export var zone := 0
@onready var lever: Node3D = $Lever
var thrown := false

func interact(_p: Node) -> void:
	if thrown:
		return
	thrown = true
	var t := create_tween()
	t.tween_property(lever, "rotation_degrees:x", -70.0, 0.25).set_trans(Tween.TRANS_BACK)
	var level := owner as Level
	if level == null:
		level = get_tree().current_scene as Level
	if level:
		level.power_on(zone)

func prompt() -> String:
	return "" if thrown else "Restore power"
