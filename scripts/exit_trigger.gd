class_name ExitTrigger
extends Area3D
## End of a section: shows the clear banner with kills and time.

signal reached

var done := false
var start_ms := 0
var total := 0

func _ready() -> void:
	body_entered.connect(_on_body)
	start_ms = Time.get_ticks_msec()
	await get_tree().process_frame
	total = get_tree().get_nodes_in_group("enemies").size()

func _on_body(b: Node) -> void:
	var p := b as Player
	if p == null or done:
		return
	done = true
	var alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Enemy).state != Enemy.State.DEAD:
			alive += 1
	var secs := (Time.get_ticks_msec() - start_ms) / 1000.0
	p.hud.show_banner("SECTION CLEAR\nanomalies %d / %d    time %d:%02d" % [total - alive, total, int(secs) / 60, int(secs) % 60])
	reached.emit()
