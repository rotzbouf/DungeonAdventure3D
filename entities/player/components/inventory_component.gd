extends Node

## Server-authoritative item bag. Mirrors skill_component's shape: a
## replicated array of ids + a request -> validate -> mutate -> (no broadcast
## needed, the replicated property carries the change) RPC for consuming items.
##
## items is replicated (spawn=true, ON_CHANGE) via player.gd._setup_replication.
## The server mutates it in place (append/erase) — `items.append(...)` does NOT
## invoke the setter below, only whole-property assignment does (same
## convention as equipment_component's equipped_slots). On clients, the setter
## fires for both the spawn snapshot and live updates and just emits a signal
## for the inventory panel.

signal inventory_changed(items: Array[StringName])
signal item_use_rejected(reason: String)

var items: Array[StringName] = []:
	set(value):
		if NetworkMode.is_client() and value.size() > items.size():
			AudioManager.play_sfx(&"item_pickup")
		items = value
		if NetworkMode.is_client():
			inventory_changed.emit(items)


## Server-only: called directly by loot_drop.gd on pickup (already running on
## the server, so this is a plain method, not an RPC).
func add_item(item_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	items.append(item_id)


@rpc("any_peer", "call_local", "reliable")
func request_use_item(item_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player := get_parent() as CharacterBody3D
	if sender_id != player.owning_peer_id():
		push_warning("inventory_component: rejected use request from non-owning peer %d" % sender_id)
		return

	var reason := ItemUseSystem.can_use(item_id, items)
	if reason != "":
		on_item_use_rejected.rpc_id(sender_id, reason)
		return

	ItemUseSystem.apply_use(item_id, player.get_node("StatsComponent"))
	items.erase(item_id)


@rpc("authority", "call_local", "reliable")
func on_item_use_rejected(reason: String) -> void:
	item_use_rejected.emit(reason)
