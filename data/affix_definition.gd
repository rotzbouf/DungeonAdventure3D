class_name AffixDefinition
extends Resource

## Designer-authored random-affix definition, loaded by GameDatabase from
## res://content/affixes/*.tres. Rolled onto rare/uncommon equipment instances
## by loot_roll_system.gd; the rolled magnitude (a float in [min_value,
## max_value]) is summed onto `stat` by item_instance_system.gd.total_stat,
## on top of the base EquipmentItem's own value for that stat.

@export var id: StringName = &""

## Suffix shown after the item name, e.g. "of Power" -> "Rare Sword of Power".
@export var display_name: String = ""

## One of EquipmentItem's aggregable stats: attack_damage, armor,
## crit_chance_bonus, attack_interval. attack_interval affixes should use a
## negative range (lower interval = faster attacks = better).
@export var stat: StringName = &""

@export var min_value: float = 0.0
@export var max_value: float = 0.0

## Equipment slots this affix can roll onto. main_hand is currently the only
## equippable slot (see content/items/*.tres).
@export var slots: Array[StringName] = [&"main_hand"]
