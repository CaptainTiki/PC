extends Node
## Dev tooling (`-- --topdown`): orthographic camera high on +Y looking straight
## down (-Y), framed to the level's grid bounds, rendered off-screen at high res.
## Output: shots/<scene>_topdown.png  (north / row 0 at the top)

const PX_PER_M := 16

func _ready() -> void:
	await get_tree().process_frame
	var level := get_tree().current_scene as Level
	var grid := level.grid
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for c in grid.get_used_cells():
		var p := grid.map_to_local(c)
		mn = Vector3(minf(mn.x, p.x - 1), 0, minf(mn.z, p.z - 1))
		mx = Vector3(maxf(mx.x, p.x + 1), 0, maxf(mx.z, p.z + 1))
	var size := mx - mn
	# lights fade with distance from the camera in normal play; the plan camera is 40m up
	for l in level.find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).distance_fade_enabled = false
	var hud := get_tree().get_first_node_in_group("player").get_node_or_null("Hud") as CanvasLayer
	if hud:
		hud.visible = false
	var vp := SubViewport.new()
	vp.size = Vector2i(int(size.x * PX_PER_M), int(size.z * PX_PER_M))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = size.z
	cam.near = 0.05
	cam.far = 100.0
	cam.position = Vector3((mn.x + mx.x) * 0.5, 40.0, (mn.z + mx.z) * 0.5)
	cam.rotation_degrees = Vector3(-90, 0, 0)       # looking straight down -Y, -Z (north) up
	# same look as the level, minus fog (40m of fog would wash the plan out)
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		var env := we.environment.duplicate() as Environment
		env.fog_enabled = false
		cam.environment = env
	vp.add_child(cam)
	cam.make_current()
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := ProjectSettings.globalize_path("res://shots/%s_topdown.png" % level.scene_file_path.get_file().get_basename())
	img.save_png(path)
	print("top-down saved ", path, " ", vp.size)
	get_tree().quit()
