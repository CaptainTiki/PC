class_name Ladder
extends Area3D
## Climbable ladder. While the player is inside the volume, forward climbs, back
## descends, and letting go hangs on. Baked by tools/build_level.gd ([ladders] / `l`).

## climb height (floor to floor)
@export var height := 4.0

func _ready() -> void:
	body_entered.connect(func(b: Node): if b is Player: (b as Player).ladder = self)
	body_exited.connect(func(b: Node): if b is Player and (b as Player).ladder == self: (b as Player).ladder = null)
