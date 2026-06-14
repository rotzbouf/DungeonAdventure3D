extends Node

## Server-authoritative buy/sell against GameDatabase.shops. Mirrors
## inventory_component's request -> validate -> mutate shape: gold and items
## are both already-replicated properties (StatsComponent.gold,
## InventoryComponent.items), so a successful trade needs no broadcast of its
## own -- the property replication carries the change. Rejections use a
## targeted RPC, same as inventory_component.on_item_use_rejected.

signal trade_rejected(reason: String)

@onready var _stats: Node = get_parent().get_node("StatsComponent")
@onready var _inventory: Node = get_parent().get_node("InventoryComponent")


@rpc("any_peer", "call_local", "reliable")
func request_buy_item(shop_id: StringName, item_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player := get_parent() as CharacterBody3D
	if sender_id != player.owning_peer_id():
		push_warning("shop_component: rejected buy request from non-owning peer %d" % sender_id)
		return

	var shop: Resource = GameDatabase.shops.get(shop_id)
	if shop == null or item_id not in shop.stock:
		on_trade_rejected.rpc_id(sender_id, "Item not sold here")
		return

	var item: Resource = GameDatabase.items.get(item_id)
	if item == null:
		on_trade_rejected.rpc_id(sender_id, "Unknown item")
		return

	if _stats.gold < item.value:
		on_trade_rejected.rpc_id(sender_id, "Not enough gold")
		return

	_stats.gold -= item.value
	_inventory.add_item(ItemInstanceSystem.create(item_id))


@rpc("any_peer", "call_local", "reliable")
func request_sell_item(iid: String) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player := get_parent() as CharacterBody3D
	if sender_id != player.owning_peer_id():
		push_warning("shop_component: rejected sell request from non-owning peer %d" % sender_id)
		return

	var index := ItemInstanceSystem.find_index_by_iid(_inventory.items, iid)
	if index == -1:
		on_trade_rejected.rpc_id(sender_id, "Item not in inventory")
		return

	var instance: Dictionary = _inventory.items[index]
	_inventory.items.remove_at(index)
	_stats.gold += ItemInstanceSystem.sell_value(instance)


@rpc("authority", "call_local", "reliable")
func on_trade_rejected(reason: String) -> void:
	trade_rejected.emit(reason)
