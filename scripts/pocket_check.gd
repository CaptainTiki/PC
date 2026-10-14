extends Node
## Dev tooling (`-- --pocketcheck c f r ...`): for each cell, puts the player at points
## around the cell's edges (where a prop meets a wall) and tries to walk back to the
## cell centre. Reports any spot it can stand in but not leave.

func _ready() -> void:
	await get_tree().physics_frame
	var level := get_tree().current_scene as Level
	for e in get_tree().current_scene.get_node("Enemies").get_children():
		e.queue_free()
	var p := get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	var args := OS.get_cmdline_user_args()
	var i := args.find("--pocketcheck") + 1
	while i + 2 < args.size():
		var cell := Vector3i(int(args[i]), int(args[i + 1]), int(args[i + 2]))
		var centre := level.grid.to_global(level.grid.map_to_local(cell))
		for off in [Vector3(-1.3, 0, -1.3), Vector3(1.3, 0, -1.3), Vector3(-1.3, 0, 1.3), Vector3(1.3, 0, 1.3), Vector3(-1.3, 0, 0), Vector3(1.3, 0, 0), Vector3(0, 0, -1.3), Vector3(0, 0, 1.3)]:
			p.global_position = centre + off + Vector3(0, 0.05, 0)
			p.velocity = Vector3.ZERO
			p.intent.move = Vector2.ZERO
			await get_tree().create_timer(0.3, true, true).timeout
			var start := p.global_position
			# a spot the body already overlaps isn't somewhere you can be shoved into
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = (p.get_node("Shape") as CollisionShape3D).shape
			q.transform = (p.get_node("Shape") as CollisionShape3D).global_transform
			q.collision_mask = 1
			q.exclude = [p.get_rid()]
			if not p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
				continue
			# try to walk out in 8 directions; the spot is a trap if none gets anywhere
			var best := 0.0
			for k in 8:
				p.global_position = start
				p.velocity = Vector3.ZERO
				p.rotation.y = k * PI / 4.0
				p.intent.move = Vector2(0, -1)
				await get_tree().create_timer(0.4, true, true).timeout
				p.intent.move = Vector2.ZERO
				best = maxf(best, p.global_position.distance_to(start))
			print("FAIL" if best < 0.8 else "PASS", " cell ", cell, " stand ", start - centre, " best move %.2f" % best)
		i += 3
	get_tree().quit()
