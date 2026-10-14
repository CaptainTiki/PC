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
	# swap to the sidearm (slot 1), fire it, and check the ammo bookkeeping
	var a0 := p.weapon.ammo
	p.weapon.switch_to(1)
	await get_tree().create_timer(0.16).timeout
	await _cap(dir + "/vm_5_swap.png")
	await get_tree().create_timer(0.4).timeout
	await _cap(dir + "/vm_6_pistol.png")
	var ok := p.weapon.try_fire()
	await _cap(dir + "/vm_7_pistol_fire.png")
	print("PASS " if ok and p.weapon.data.display_name == "Sidearm" else "FAIL ", "sidearm fires  ", p.weapon.data.display_name)
	p.weapon.switch_to(0)
	await get_tree().create_timer(0.5).timeout
	print("PASS " if p.weapon.ammo == a0 else "FAIL ", "scattergun ammo kept across the swap  ", p.weapon.ammo, " vs ", a0)
	get_tree().quit()

func _cap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
