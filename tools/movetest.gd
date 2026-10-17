extends Node
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var intent = p.get_node("Intent")
	intent.bot = true
	print("start ", p.global_position, " on_floor=", p.is_on_floor(), " vel=", p.velocity)
	intent.move = Vector2(0, -1)
	for i in 60:
		await get_tree().physics_frame
	print("after fwd ", p.global_position, " on_floor=", p.is_on_floor(), " vel=", p.velocity, " slides=", p.get_slide_collision_count())
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i); print("  hit ", c.get_collider().name, " n=", c.get_normal())
	intent.move = Vector2(1, 0)
	for i in 60:
		await get_tree().physics_frame
	print("after right ", p.global_position)
	get_tree().quit()
