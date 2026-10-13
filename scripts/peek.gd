extends Node
## Dev tooling (`-- --peek c f r yaw pitch [c f r yaw pitch ...]`): drops the player at
## grid cells, looks that way and captures shots/peek_<n>.png for each. Enemies removed.

func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://shots")
	await get_tree().physics_frame
	var level := get_tree().current_scene as Level
	for e in get_tree().current_scene.get_node("Enemies").get_children():
		e.queue_free()
	var p := get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	p.flashlight.visible = true
	var args := OS.get_cmdline_user_args()
	var i := args.find("--peek") + 1
	var n := 0
	while i + 4 < args.size():
		var cell := Vector3i(int(args[i]), int(args[i + 1]), int(args[i + 2]))
		p.global_position = level.grid.to_global(level.grid.map_to_local(cell)) + Vector3(0, 0.05, 0)
		p.velocity = Vector3.ZERO
		p.rotation.y = deg_to_rad(float(args[i + 3]))
		p.head.rotation.x = deg_to_rad(float(args[i + 4]))
		if i + 5 < args.size() and args[i + 5] == "open":
			for d in level.find_children("*", "Door", true, false):
				d.lock = "none"
				d.open_amount = 1.0
				d.body.position = d.open_offset
				d.set_physics_process(false)
			i += 1
		await get_tree().create_timer(0.6, true, true).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png("%s/peek_%d.png" % [dir, n])
		print("peek ", n, " ", cell)
		n += 1
		i += 5
	get_tree().quit()
