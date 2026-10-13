extends Node
## Dev tooling (`-- --flashcheck`): from each "shots" marker, capture with the
## flashlight off and on -> shots/flash_<marker>_off/on.png

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var p := get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	p.set_physics_process(false)
	var dir := ProjectSettings.globalize_path("res://shots")
	for m in get_tree().get_nodes_in_group("shots"):
		var mk := m as Node3D
		p.global_position = mk.global_position - Vector3(0, 1.65, 0)
		p.rotation.y = mk.rotation.y
		p.head.rotation.x = mk.rotation.x
		for state in ["off", "on"]:
			p.flashlight.visible = state == "on"
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png("%s/flash_%s_%s.png" % [dir, mk.name, state])
	get_tree().quit()
