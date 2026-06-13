class_name EquipmentItem
extends Resource

## Designer-authored equipment definition, loaded by GameDatabase from
## res://content/items/*.tres. id must be unique and non-empty (see
## GameDatabase._load_category) and is what RPC payloads/replicated state
## reference — visual_scene itself never crosses the network.
##
## Combat stats (M15) are read server-side only, via equipment_component.gd's
## aggregation helpers — the stats themselves are never replicated, since
## `equipped_slots` (item ids) already is and every peer re-resolves id ->
## EquipmentItem through GameDatabase.

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

## Combat stats (M15). Defaults are inert so pre-M15 .tres files load
## unchanged; non-weapon items leave attack_* at their defaults and only
## contribute armor/crit bonuses.
@export var attack_damage: int = 0
## Seconds between basic-attack swings (player_controller.gd).
@export var attack_interval: float = 1.2
## Basic-attack reach in world units; the bow's 7.0 is what makes it ranged.
@export var attack_range: float = 1.8
## Flat damage mitigation (CombatSystem.compute_hit) when the wearer is hit.
@export var armor: int = 0
## Added to CombatSystem.BASE_CRIT_CHANCE for the wearer's attacks.
@export var crit_chance_bonus: float = 0.0

## Display tier consumed by ui (data/rarity.gd colors). Gameplay-inert in M15;
## M16's loot tables/affixes give it mechanical meaning.
@export var rarity: StringName = &"common"
