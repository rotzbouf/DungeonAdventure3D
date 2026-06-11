class_name ConsumableItem
extends Resource

## Designer-authored consumable definition, loaded by GameDatabase from
## res://content/items/*.tres alongside EquipmentItem (GameDatabase._load_category
## is duck-typed on `id`, so both Resource types share the `items` category).
##
## use_effect maps an effect key to a magnitude, e.g. {&"restore_hp": 40}.
## ItemUseSystem.apply_use is the single place these keys are interpreted.

@export var id: StringName = &""
@export var display_name: String = ""
@export var use_effect: Dictionary = {}

## World pickup visual, instantiated by loot_drop.gd — mirrors
## EquipmentItem.visual_scene (never crosses the network, re-resolved
## locally on every peer from the item id).
@export var visual_scene: PackedScene

## Base shop value in gold. Buy price = value; sell price = value / 2
## (integer division), computed by shop_component.gd.
@export var value: int = 0
