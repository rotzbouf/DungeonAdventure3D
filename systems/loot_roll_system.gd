class_name LootRollSystem

## Pure rolling logic for LootTable -> item instances (item_instance_system.gd).
## Called server-side only, via world.gd.roll_loot (enemy.gd.on_died).

const AFFIX_COUNT_BY_RARITY: Dictionary[StringName, int] = {
	&"common": 0, &"uncommon": 1, &"rare": 2,
}


## Rolls `loot_table.rolls` independent drops, each gated by `drop_chance`.
## Equipment drops also roll a rarity (from `rarity_weights`) and that
## rarity's affix count from distinct-stat affixes valid for the item's slot.
## Non-equipment drops (consumables) always come back &"common" with no
## affixes — rarity rolls are equipment-only.
static func roll(loot_table: LootTable, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if loot_table == null:
		return drops
	for i in loot_table.rolls:
		if rng.randf() > loot_table.drop_chance:
			continue
		var item_id: StringName = _weighted_pick(loot_table.item_weights, rng)
		if item_id == &"":
			continue
		var base: Resource = GameDatabase.items.get(item_id)
		if base is EquipmentItem:
			var rarity: StringName = _weighted_pick(loot_table.rarity_weights, rng)
			var affixes := _roll_affixes(rarity, base.slot, rng)
			drops.append(ItemInstanceSystem.create(item_id, rarity, affixes))
		else:
			drops.append(ItemInstanceSystem.create(item_id))
	return drops


## Weighted random key from `weights` (key -> relative weight). Returns &""
## if `weights` is empty or all-zero.
static func _weighted_pick(weights: Dictionary[StringName, float], rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for w in weights.values():
		total += w
	if total <= 0.0:
		return &""
	var roll := rng.randf() * total
	var cumulative := 0.0
	for key: StringName in weights:
		cumulative += weights[key]
		if roll < cumulative:
			return key
	return weights.keys()[-1]


## Picks `AFFIX_COUNT_BY_RARITY[rarity]` affixes valid for `slot`, each on a
## distinct `stat` (so a rare item's bonuses are varied, not e.g. two
## attack_damage rolls), with magnitudes rolled from each affix's
## [min_value, max_value].
static func _roll_affixes(rarity: StringName, slot: StringName, rng: RandomNumberGenerator) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	var count: int = AFFIX_COUNT_BY_RARITY.get(rarity, 0)
	if count <= 0:
		return result
	var candidates: Array[AffixDefinition] = []
	for affix_id in GameDatabase.affixes:
		var affix: AffixDefinition = GameDatabase.affixes[affix_id]
		if slot in affix.slots:
			candidates.append(affix)
	var used_stats: Dictionary[StringName, bool] = {}
	while result.size() < count and not candidates.is_empty():
		var index := rng.randi_range(0, candidates.size() - 1)
		var affix: AffixDefinition = candidates[index]
		candidates.remove_at(index)
		if affix.stat in used_stats:
			continue
		used_stats[affix.stat] = true
		result[affix.id] = rng.randf_range(affix.min_value, affix.max_value)
	return result
