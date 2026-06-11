extends StaticBody3D

## A pickup dropped by a defeated enemy (enemy.gd.on_died ->
## world.gd.spawn_loot_drop) or a chest (chest.gd.on_chest_opened ->
## world.gd.spawn_loot_drop). Mirrors spell_scroll.gd's interact() ->
## rpc_id(1, ...) pattern. request_pickup grants the item to the requesting
## peer's InventoryComponent and despawns.

## Set by world.gd._spawn_loot on the freshly instantiated node, BEFORE it
## enters the tree — same deterministic-reconstruction pattern as
## enemy.gd.definition_id.
var item_id: StringName = &""

## Server-only: guards against a second request_pickup arriving before
## queue_free() (deferred) actually removes this node.
var _picked_up: bool = false


func _ready() -> void:
	var item: Resource = GameDatabase.items.get(item_id)
	if item != null and "visual_scene" in item and item.visual_scene != null:
		$MeshInstance3D.visible = false
		add_child(item.visual_scene.instantiate())


func interact(_player: Node) -> void:
	request_pickup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func request_pickup() -> void:
	if not NetworkMode.is_server() or _picked_up:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var world := get_tree().get_root().get_node_or_null("GameRoot/World")
	var player: Node = world.get_node_or_null("Players/Player_%d" % peer_id) if world else null
	var inventory: Node = player.get_node_or_null("InventoryComponent") if player else null
	if inventory == null:
		return
	_picked_up = true
	inventory.add_item(item_id)
	queue_free()
