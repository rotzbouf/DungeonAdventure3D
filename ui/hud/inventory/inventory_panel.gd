extends PanelContainer

## CLIENT-ONLY inventory panel. Wired up by hud.gd._connect_to_player, same
## pattern as hotbar <-> skill_component. Shows equipped items first (marked
## "[E]", double-click to unequip), then bag items grouped by count
## ("Health Potion x2"). Double-clicking a bag row equips it (equipment),
## uses it (consumable), per the item's type.
##
## M16: single-clicking any row shows a details panel — rarity-colored name,
## stat breakdown (including affix bonuses), sell value, and, for equipment
## with something already worn in the same slot, a stat-delta comparison
## against the currently equipped item.

## EquipmentItem's stats that item_instance_system.gd.total_stat aggregates.
const AGGREGABLE_STATS: Array[StringName] = [&"attack_damage", &"armor", &"crit_chance_bonus", &"attack_interval"]

const STAT_DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"attack_damage": "Attack Damage",
	&"armor": "Armor",
	&"crit_chance_bonus": "Crit Chance",
	&"attack_interval": "Attack Speed",
}

## True if a higher value of this stat is better for the wearer.
## attack_interval is seconds-between-swings, so lower is better.
const STAT_HIGHER_IS_BETTER: Dictionary[StringName, bool] = {
	&"attack_damage": true,
	&"armor": true,
	&"crit_chance_bonus": true,
	&"attack_interval": false,
}

const LINE_COLOR := Color(0.92, 0.85, 0.7)
const IMPROVED_COLOR := Color(0.45, 0.85, 0.4)
const WORSENED_COLOR := Color(0.85, 0.35, 0.35)

@onready var _list: ItemList = $HBox/ItemList
@onready var _details_name: Label = $HBox/Details/NameLabel
@onready var _details_lines: VBoxContainer = $HBox/Details/Lines

var _inventory_component: Node
var _equipment_component: Node
## Parallel to _list's rows: each entry is
## {action: "equip"/"unequip"/"use", iid: String, slot: StringName, instance: Dictionary}.
var _rows: Array[Dictionary] = []


func set_inventory_component(component: Node) -> void:
	_inventory_component = component
	component.inventory_changed.connect(func(_items: Array[Dictionary]) -> void: _refresh())
	component.item_use_rejected.connect(_on_action_rejected)
	_refresh()


func set_equipment_component(component: Node) -> void:
	_equipment_component = component
	component.equipment_changed.connect(func(_slots: Dictionary) -> void: _refresh())
	component.equip_rejected.connect(_on_action_rejected)
	_refresh()


## Rebuilds the whole list from current inventory + equipment state. Reads both
## components fresh (not just signal payloads), so a late joiner opening the
## panel sees the right thing even though it missed the equip RPCs. Bag items
## group by ItemInstanceSystem.signature, so identical commons stack
## ("Health Potion x3") but two differently-rolled rares show separately.
func _refresh() -> void:
	if _inventory_component == null:
		return
	_list.clear()
	_rows.clear()
	_clear_details()

	if _equipment_component != null:
		for slot: StringName in _equipment_component.equipped_slots:
			var instance: Dictionary = _equipment_component.equipped_slots[slot]
			var item_name := ItemInstanceSystem.display_name(instance)
			var row := _list.add_item("[E] %s" % item_name)
			_list.set_item_custom_fg_color(row, Rarity.color_for(instance))
			_rows.append({"action": "unequip", "iid": instance.get("iid", ""), "slot": slot, "instance": instance})

	var groups: Dictionary = {}
	var order: Array[String] = []
	for instance: Dictionary in _inventory_component.items:
		var sig := ItemInstanceSystem.signature(instance)
		if sig not in groups:
			order.append(sig)
			groups[sig] = []
		groups[sig].append(instance)
	for sig in order:
		var group: Array = groups[sig]
		var representative: Dictionary = group[0]
		var item_name := ItemInstanceSystem.display_name(representative)
		var count: int = group.size()
		var label := item_name if count == 1 else "%s x%d" % [item_name, count]
		var row := _list.add_item(label)
		_list.set_item_custom_fg_color(row, Rarity.color_for(representative))
		var action := "equip" if ItemInstanceSystem.base_item(representative) is EquipmentItem else "use"
		_rows.append({"action": action, "iid": representative.get("iid", ""), "slot": &"", "instance": representative})


func _on_item_list_item_activated(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	match row.action:
		"equip":
			_equipment_component.request_equip.rpc_id(1, row.iid)
		"unequip":
			_equipment_component.request_unequip.rpc_id(1, row.slot)
		"use":
			_inventory_component.request_use_item.rpc_id(1, row.iid)


func _on_item_list_item_selected(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_show_details(_rows[index].instance)


func _on_action_rejected(reason: String) -> void:
	print("[inventory] %s" % reason)


## Populates the details panel for `instance`: rarity-colored name, non-zero
## base stats, one line per affix bonus, sell value, and — for equipment with
## something already worn in the same slot — a stat-delta comparison.
func _show_details(instance: Dictionary) -> void:
	var base := ItemInstanceSystem.base_item(instance)
	_details_name.text = ItemInstanceSystem.display_name(instance)
	_details_name.add_theme_color_override("font_color", Rarity.color_for(instance))

	_clear_lines()

	for stat_name in AGGREGABLE_STATS:
		var base_value: float = float(base.get(stat_name)) if base != null and stat_name in base else 0.0
		if base_value != 0.0:
			_add_line("%s: %s" % [STAT_DISPLAY_NAMES[stat_name], _format_value(stat_name, base_value)])

	var affixes: Dictionary = instance.get("affixes", {})
	for affix_id in affixes:
		var affix: AffixDefinition = GameDatabase.affixes.get(affix_id)
		if affix != null:
			var stat_label: String = STAT_DISPLAY_NAMES.get(affix.stat, String(affix.stat))
			_add_line("%s %s from %s" % [_format_signed(affix.stat, affixes[affix_id]), stat_label, affix.display_name])

	_add_line("Value: %d gold" % ItemInstanceSystem.sell_value(instance))

	if base is EquipmentItem and _equipment_component != null:
		var equipped: Dictionary = _equipment_component.equipped_slots.get(base.slot, {})
		if not equipped.is_empty() and equipped.get("iid", "") != instance.get("iid", ""):
			_add_line("Compared to equipped %s:" % ItemInstanceSystem.display_name(equipped))
			for stat_name in AGGREGABLE_STATS:
				var delta: float = ItemInstanceSystem.total_stat(instance, stat_name) - ItemInstanceSystem.total_stat(equipped, stat_name)
				if delta == 0.0:
					continue
				var improved := (delta > 0.0) == STAT_HIGHER_IS_BETTER[stat_name]
				var color := IMPROVED_COLOR if improved else WORSENED_COLOR
				_add_line("%s: %s" % [STAT_DISPLAY_NAMES[stat_name], _format_signed(stat_name, delta)], color)


func _clear_details() -> void:
	_details_name.text = ""
	_clear_lines()


func _clear_lines() -> void:
	for child in _details_lines.get_children():
		child.queue_free()


func _add_line(text: String, color: Color = LINE_COLOR) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	_details_lines.add_child(label)


## Plain magnitude for a "base stats" line, e.g. "Attack Damage: 8", "Crit
## Chance: 5%", "Attack Speed: 1.20s".
func _format_value(stat_name: StringName, value: float) -> String:
	match stat_name:
		&"crit_chance_bonus":
			return "%.0f%%" % (value * 100.0)
		&"attack_interval":
			return "%.2fs" % value
		_:
			return str(int(value))


## Signed magnitude for affix and comparison lines, e.g. "+3", "+5%", "-0.10s".
func _format_signed(stat_name: StringName, value: float) -> String:
	match stat_name:
		&"crit_chance_bonus":
			return "%+.0f%%" % (value * 100.0)
		&"attack_interval":
			return "%+.2fs" % value
		_:
			return "%+d" % int(round(value))
