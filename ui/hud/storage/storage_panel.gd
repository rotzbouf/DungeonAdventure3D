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
## Representative iids (one per ItemInstanceSystem.signature group), parallel
## to each list's rows.
var _inventory_iids: Array[String] = []
var _storage_iids: Array[String] = []


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


func _on_inventory_changed(items: Array[Dictionary]) -> void:
	_inventory_iids = _populate_list(_inventory_list, items)


func _on_storage_updated(items: Array[Dictionary]) -> void:
	_storage_iids = _populate_list(_storage_list, items)


## Groups by ItemInstanceSystem.signature so identical commons stack
## ("Health Potion x3") but two differently-rolled rares show separately.
func _populate_list(list: ItemList, items: Array[Dictionary]) -> Array[String]:
	var groups: Dictionary = {}
	var order: Array[String] = []
	for instance: Dictionary in items:
		var sig := ItemInstanceSystem.signature(instance)
		if sig not in groups:
			order.append(sig)
			groups[sig] = []
		groups[sig].append(instance)

	list.clear()
	var iids: Array[String] = []
	for sig in order:
		var group: Array = groups[sig]
		var representative: Dictionary = group[0]
		var item_name := ItemInstanceSystem.display_name(representative)
		var count: int = group.size()
		list.add_item(item_name if count == 1 else "%s x%d" % [item_name, count])
		iids.append(representative.get("iid", ""))
	return iids


func _on_inventory_list_item_activated(index: int) -> void:
	if index < 0 or index >= _inventory_iids.size():
		return
	_storage_chest.request_deposit_item.rpc_id(1, _inventory_iids[index])


func _on_storage_list_item_activated(index: int) -> void:
	if index < 0 or index >= _storage_iids.size():
		return
	_storage_chest.request_withdraw_item.rpc_id(1, _storage_iids[index])


func _on_close_button_pressed() -> void:
	visible = false
