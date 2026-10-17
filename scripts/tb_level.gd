class_name TbLevel
extends Node3D
## Root for TrenchBroom-built levels (levels/tb/*.tscn). The geometry, lights, doors,
## player start and screenshot markers all come from the .map via FuncGodot; this
## script only adds the dev-tool entry points the GridMap levels have.
##
##   godot ... <scene> -- --capture   -> renders every Marker3D in group "shots" to shots/

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		_capture.call_deferred()
	elif "--playtest" in args:
		add_child(Playtest.new())
	elif "--notetest" in args:   # dev: drop one pin without a keyboard, then quit
		var np := NotePins.new()
		add_child(np)
		await get_tree().process_frame
		await get_tree().process_frame
		np._open()
		np._on_submit("notetest pin from --notetest")
		print("pins now: ", np.pins.size(), " -> ", np._notes_path())
		get_tree().quit()
	else:
		add_child(NotePins.new())   # Q drops a note pin; see scripts/note_pins.gd

func _capture() -> void:
	var cam := Camera3D.new()
	cam.fov = 80
	add_child(cam)
	cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene_name := scene_file_path.get_file().get_basename()
	for m in get_tree().get_nodes_in_group("shots"):
		cam.global_transform = (m as Node3D).global_transform
		for i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var path := "%s/%s_%s.png" % [out_dir, scene_name, m.name]
		img.save_png(path)
		print("captured ", path)
	get_tree().quit()
