extends PanelContainer

## CLIENT-ONLY storage panel, opened by storage_chest.gd via hud.gd.open_storage().
## Mirrors shop_panel.gd's group-by-id/double-click pattern: the inventory
## list (left) shows the player's items, the storage list (right) shows this
## peer's chest contents (fetched via request_open_storage on open).
## Double-clicking either deposits/withdraws the item.

@onready var _inventory_list: ItemList = $VBox/Lists/InventoryColumn/InventoryList
@onready var _storage_list: ItemList = $VBox/Lists/StorageColumn/StorageList

var _storage_chest: Node
var _inventory_component: Node
var _unique_inventory_ids: Array[StringName] = []
var _unique_storage_ids: Array[StringName] = []


func open_storage(storage_chest: Node, inventory_component: Node) -> void:
	if _inventory_component != null and _inventory_component.inventory_changed.is_connected(_on_inventory_changed):
		_inventory_component.inventory_changed.disconnect(_on_inventory_changed)
	if _storage_chest != null and _storage_chest.storage_updated.is_connected(_on_storage_updated):
		_storage_chest.storage_updated.disconnect(_on_storage_updated)

	_storage_chest = storage_chest
	_inventory_component = inventory_component

	_inventory_component.inventory_changed.connect(_on_inventory_changed)
	_storage_chest.storage_updated.connect(_on_storage_updated)
	_on_inventory_changed(_inventory_component.items)

	visible = true
	_storage_chest.request_open_storage.rpc_id(1)


func _on_inventory_changed(items: Array[StringName]) -> void:
	_unique_inventory_ids = _populate_list(_inventory_list, items)


func _on_storage_updated(items: Array[StringName]) -> void:
	_unique_storage_ids = _populate_list(_storage_list, items)


func _populate_list(list: ItemList, items: Array[StringName]) -> Array[StringName]:
	var counts: Dictionary = {}
	var unique_ids: Array[StringName] = []
	for id in items:
		if id not in counts:
			unique_ids.append(id)
		counts[id] = counts.get(id, 0) + 1

	list.clear()
	for id in unique_ids:
		var item: Resource = GameDatabase.items.get(id)
		var item_name: String = item.display_name if item != null else String(id)
		var count: int = counts[id]
		list.add_item(item_name if count == 1 else "%s x%d" % [item_name, count])
	return unique_ids


func _on_inventory_list_item_activated(index: int) -> void:
	if index < 0 or index >= _unique_inventory_ids.size():
		return
	_storage_chest.request_deposit_item.rpc_id(1, _unique_inventory_ids[index])


func _on_storage_list_item_activated(index: int) -> void:
	if index < 0 or index >= _unique_storage_ids.size():
		return
	_storage_chest.request_withdraw_item.rpc_id(1, _unique_storage_ids[index])


func _on_close_button_pressed() -> void:
	visible = false
