extends StaticBody3D

## Per-player private storage. Server-only `_storage` dict (peer_id ->
## item ids), NEVER replicated -- each peer's contents are sent only to that
## peer via targeted RPCs, mirroring chest.gd's on_chest_opened shape but
## per-peer instead of per-session, and persisting only for the lifetime of
## the server process (no save/load system exists yet).
##
## `sender_id` (server-verified, can't be spoofed) is both the storage key
## and the Players/Player_<id> lookup key, so a peer can only ever touch its
## own storage/inventory -- no extra ownership check needed.

signal storage_updated(items: Array[Dictionary])

var _storage: Dictionary = {}  # int (peer_id) -> Array[Dictionary]


## Client-local: opens the HUD's StoragePanel, which itself sends
## request_open_storage to fetch this peer's contents -- mirrors merchant.gd.
func interact(player: Node) -> void:
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud != null:
		hud.open_storage(self, player)


@rpc("any_peer", "call_local", "reliable")
func request_open_storage() -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var stored := _stored_items(sender_id)
	on_storage_updated.rpc_id(sender_id, stored)


@rpc("any_peer", "call_local", "reliable")
func request_deposit_item(iid: String) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var inventory := _inventory_for(sender_id)
	if inventory == null:
		return
	var index := ItemInstanceSystem.find_index_by_iid(inventory.items, iid)
	if index == -1:
		return
	var instance: Dictionary = inventory.items[index]
	inventory.items.remove_at(index)
	var stored := _stored_items(sender_id)
	stored.append(instance)
	_storage[sender_id] = stored
	on_storage_updated.rpc_id(sender_id, stored)


@rpc("any_peer", "call_local", "reliable")
func request_withdraw_item(iid: String) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var stored := _stored_items(sender_id)
	var index := ItemInstanceSystem.find_index_by_iid(stored, iid)
	if index == -1:
		return
	var inventory := _inventory_for(sender_id)
	if inventory == null:
		return
	var instance: Dictionary = stored[index]
	stored.remove_at(index)
	_storage[sender_id] = stored
	inventory.add_item(instance)
	on_storage_updated.rpc_id(sender_id, stored)


@rpc("authority", "call_local", "reliable")
func on_storage_updated(items: Array[Dictionary]) -> void:
	storage_updated.emit(items)


func _inventory_for(peer_id: int) -> Node:
	var world := get_tree().root.find_child("World", true, false)
	var player := world.get_node_or_null("Players/Player_%d" % peer_id)
	if player == null:
		return null
	return player.get_node_or_null("InventoryComponent")


## _storage.get(peer_id, []) can't be assigned directly to an Array[Dictionary]
## (the [] default is an untyped Array, which fails the typed-array check at
## runtime) -- this does the has-check instead.
func _stored_items(peer_id: int) -> Array[Dictionary]:
	if _storage.has(peer_id):
		return _storage[peer_id]
	return []
