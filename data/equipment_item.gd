class_name EquipmentItem
extends Resource

## Designer-authored equipment definition, loaded by GameDatabase from
## res://content/items/*.tres. id must be unique and non-empty (see
## GameDatabase._load_category) and is what RPC payloads/replicated state
## reference — visual_scene itself never crosses the network.
##
## Identity + slot + visual only — stat/effect fields are deferred to M6,
## like CharacterClass deferred base_stats: inventing them now would mean
## guessing at a shape before StatsComponent exists to give it meaning.

@export var id: StringName = &""
@export var display_name: String = ""

## Equipment slot this item occupies (e.g. &"main_hand"). Must match a key in
## the wearer's RaceModel.attachment_points for the visual to attach anywhere.
## Always StringName — see equip_validation_system.gd for why mixing String/
## StringName here is the likeliest silent-failure bug in this system.
@export var slot: StringName = &""

@export var visual_scene: PackedScene

## Base shop value in gold. Buy price = value; sell price = value / 2
## (integer division), computed by shop_component.gd.
@export var value: int = 0
