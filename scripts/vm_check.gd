extends Node
## Dev tooling (`-- --vmcheck`): stand still, fire once, capture frames 0..3 after.

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var p := get_tree().get_first_node_in_group("player") as Player
	p.intent.bot = true
	var dir := ProjectSettings.globalize_path("res://shots")
	await _cap(dir + "/vm_0_idle.png")
	p.weapon.try_fire()
	for i in 4:
		await _cap(dir + "/vm_%d_fire.png" % (i + 1))
	get_tree().quit()

func _cap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
