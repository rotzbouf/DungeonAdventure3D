extends PanelContainer

## CLIENT-ONLY inventory panel. Wired up by hud.gd._connect_to_player, same
## pattern as hotbar <-> skill_component. Groups duplicate item ids by count
## for display ("Health Potion x2"); double-clicking a row requests the
## server use that item.

@onready var _list: ItemList = $ItemList

var _inventory_component: Node
## Unique item ids in display order, parallel to _list's rows.
var _unique_ids: Array[StringName] = []


func set_inventory_component(component: Node) -> void:
	_inventory_component = component
	component.inventory_changed.connect(_on_inventory_changed)
	component.item_use_rejected.connect(_on_item_use_rejected)
	_on_inventory_changed(component.items)


func _on_inventory_changed(items: Array[StringName]) -> void:
	var counts: Dictionary = {}
	_unique_ids.clear()
	for id in items:
		if id not in counts:
			_unique_ids.append(id)
		counts[id] = counts.get(id, 0) + 1

	_list.clear()
	for id in _unique_ids:
		var item: Resource = GameDatabase.items.get(id)
		var item_name: String = item.display_name if item != null else String(id)
		var count: int = counts[id]
		var row := _list.add_item(item_name if count == 1 else "%s x%d" % [item_name, count])
		_list.set_item_custom_fg_color(row, Rarity.color_for(item))


func _on_item_list_item_activated(index: int) -> void:
	if index < 0 or index >= _unique_ids.size():
		return
	_inventory_component.request_use_item.rpc_id(1, _unique_ids[index])


func _on_item_use_rejected(reason: String) -> void:
	print("[inventory] %s" % reason)
