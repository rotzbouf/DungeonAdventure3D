extends Area3D

## Server-only teleport trigger (dungeon <-> town). A player walking into
## this area is reset to `target_position` via player_controller.gd's
## reset_to() -- the same mechanism player.gd._respawn() already uses, so
## position/velocity/nav-agent reset and replication "just work" with no new
## RPCs. Always active (unlike exit_portal.gd, which waits for the boss to
## die) -- both ends of a dungeon<->town portal pair are usable immediately.

@export var target_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	if NetworkMode.is_server():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.name.begins_with("Player_"):
		return
	body.get_node("Controller").reset_to(target_position)
