extends PanelContainer

## CLIENT-ONLY inventory panel. Wired up by hud.gd._connect_to_player, same
## pattern as hotbar <-> skill_component. Shows equipped items first (marked
## "[E]", double-click to unequip), then bag items grouped by count
## ("Health Potion x2"). Double-clicking a bag row equips it (equipment),
## uses it (consumable), per the item's type.

@onready var _list: ItemList = $ItemList

var _inventory_component: Node
var _equipment_component: Node
## Parallel to _list's rows: each entry is
## {action: "equip"/"unequip"/"use", item_id: StringName, slot: StringName}.
var _rows: Array[Dictionary] = []


func set_inventory_component(component: Node) -> void:
	_inventory_component = component
	component.inventory_changed.connect(func(_items: Array[StringName]) -> void: _refresh())
	component.item_use_rejected.connect(_on_action_rejected)
	_refresh()


func set_equipment_component(component: Node) -> void:
	_equipment_component = component
	component.equipment_changed.connect(func(_slots: Dictionary) -> void: _refresh())
	component.equip_rejected.connect(_on_action_rejected)
	_refresh()


## Rebuilds the whole list from current inventory + equipment state. Reads both
## components fresh (not just signal payloads), so a late joiner opening the
## panel sees the right thing even though it missed the equip RPCs.
func _refresh() -> void:
	if _inventory_component == null:
		return
	_list.clear()
	_rows.clear()

	if _equipment_component != null:
		for slot: StringName in _equipment_component.equipped_slots:
			var item_id: StringName = _equipment_component.equipped_slots[slot]
			var item: Resource = GameDatabase.items.get(item_id)
			var item_name: String = item.display_name if item != null else String(item_id)
			var row := _list.add_item("[E] %s" % item_name)
			_list.set_item_custom_fg_color(row, Rarity.color_for(item))
			_rows.append({"action": "unequip", "item_id": item_id, "slot": slot})

	var counts: Dictionary = {}
	var order: Array[StringName] = []
	for id in _inventory_component.items:
		if id not in counts:
			order.append(id)
		counts[id] = counts.get(id, 0) + 1
	for id in order:
		var item: Resource = GameDatabase.items.get(id)
		var item_name: String = item.display_name if item != null else String(id)
		var count: int = counts[id]
		var label := item_name if count == 1 else "%s x%d" % [item_name, count]
		var row := _list.add_item(label)
		_list.set_item_custom_fg_color(row, Rarity.color_for(item))
		var action := "equip" if item is EquipmentItem else "use"
		_rows.append({"action": action, "item_id": id, "slot": &""})


func _on_item_list_item_activated(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	match row.action:
		"equip":
			_equipment_component.request_equip.rpc_id(1, row.item_id)
		"unequip":
			_equipment_component.request_unequip.rpc_id(1, row.slot)
		"use":
			_inventory_component.request_use_item.rpc_id(1, row.item_id)


func _on_action_rejected(reason: String) -> void:
	print("[inventory] %s" % reason)
