class_name ItemUseSystem

## Returns "" on success, or a rejection reason string.
static func can_use(item_id: StringName, items: Array[Dictionary]) -> String:
	if not items.any(func(i: Dictionary) -> bool: return i.id == item_id):
		return "You don't have that item."
	var item: Resource = GameDatabase.items.get(item_id)
	if item == null or not (item is ConsumableItem):
		return "That item can't be used."
	return ""


## Applies item.use_effect to `stats` in place. Caller (inventory_component)
## removes the item from the inventory afterwards.
static func apply_use(item_id: StringName, stats: Node) -> void:
	var item: ConsumableItem = GameDatabase.items[item_id]
	if &"restore_hp" in item.use_effect:
		stats.hp = mini(stats.max_hp, stats.hp + int(item.use_effect[&"restore_hp"]))
	if &"restore_mp" in item.use_effect:
		stats.mp = mini(stats.max_mp, stats.mp + int(item.use_effect[&"restore_mp"]))
