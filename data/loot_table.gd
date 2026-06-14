class_name LootTable
extends Resource

## Designer-authored loot table, loaded by GameDatabase from
## res://content/loot_tables/*.tres. Rolled by loot_roll_system.gd into
## item instances (item_instance_system.gd) when an enemy dies
## (enemy_definition.gd.loot_table).

@export var id: StringName = &""

## item id (GameDatabase.items key) -> relative weight. Higher weight = more
## likely to be picked for a given roll.
@export var item_weights: Dictionary[StringName, float] = {}

## Rarity id -> relative weight, applied only when the rolled item resolves
## to an EquipmentItem (consumables always roll &"common" with no affixes).
@export var rarity_weights: Dictionary[StringName, float] = {
	&"common": 70.0, &"uncommon": 25.0, &"rare": 5.0,
}

## Number of independent drop attempts.
@export var rolls: int = 1

## Probability (0..1) that each roll produces a drop at all.
@export var drop_chance: float = 1.0
