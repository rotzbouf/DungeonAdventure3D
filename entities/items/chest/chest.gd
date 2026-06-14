extends StaticBody3D

## Opens once per session, plays the "Open" animation on every peer, and
## spawns loot via World.spawn_loot_drop. Mirrors spell_scroll.gd's
## interact() -> rpc_id(1, ...) pattern. Chests are static children of World
## (parent="." in world.tscn, like SpellScroll_Fireball), so get_parent() is
## World directly -- no path lookups needed.

@export var loot_item_ids: Array[StringName] = [&"health_potion", &"health_potion"]

## Server-only, not replicated -- one-time interaction per session.
var _opened: bool = false


func interact(_player: Node) -> void:
	request_open.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_open() -> void:
	if not NetworkMode.is_server() or _opened:
		return
	_opened = true
	on_chest_opened.rpc()


@rpc("authority", "call_local", "reliable")
func on_chest_opened() -> void:
	$ChestModel/AnimationPlayer.play("Open")
	if NetworkMode.is_server():
		var world := get_parent()
		for item_id in loot_item_ids:
			world.spawn_loot_drop(global_position + Vector3(0, 0.6, 0.6), ItemInstanceSystem.create(item_id))
