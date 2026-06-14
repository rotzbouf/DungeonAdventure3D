class_name ItemInstanceSystem

## Pure functions over "item instances" — the Dictionary shape that replaces
## bare StringName item ids throughout InventoryComponent.items,
## EquipmentComponent.equipped_slots, loot drops, storage, and shop trades
## (M16):
##
##   {
##     "iid": "<unique string>",        # identifies THIS instance, never the base item
##     "id": &"sword",                  # base item id -> GameDatabase.items
##     "rarity": &"rare",                # may differ from the base .tres's own rarity
##     "affixes": {&"of_power": 3.0},   # affix id -> rolled magnitude
##   }
##
## Confirmed (Phase 0a spike) that Array[Dictionary] / Dictionary[StringName,
## Dictionary] replicate correctly via both MultiplayerSynchronizer
## (ON_CHANGE + spawn) and MultiplayerSpawner spawn-data, including late
## joiners — so this Dictionary shape is also the wire format, unchanged.

## Builds a new item instance. `rarity` defaults to the base item's own
## .rarity field (duck-typed like rarity.gd.color_for) when not given —
## e.g. buying an Elven Sword from a shop yields a &"rare" instance even
## with no affixes, matching its authored rarity.
static func create(base_id: StringName, rarity: Variant = null, affixes: Dictionary[StringName, float] = {}) -> Dictionary:
	var resolved_rarity: StringName = rarity if rarity != null else _base_rarity(base_id)
	return {
		"iid": "%d_%d" % [Time.get_ticks_usec(), randi()],
		"id": base_id,
		"rarity": resolved_rarity,
		"affixes": affixes,
	}


static func _base_rarity(base_id: StringName) -> StringName:
	var base: Resource = GameDatabase.items.get(base_id)
	if base == null:
		return &"common"
	var rarity: Variant = base.get("rarity")
	return rarity if rarity != null else &"common"


## The base EquipmentItem/ConsumableItem resource this instance was rolled
## from, or null if `id` doesn't resolve.
static func base_item(instance: Dictionary) -> Resource:
	return GameDatabase.items.get(instance.get("id", &""))


## Rarity-prefixed, affix-suffixed display name, e.g.
## "Rare Sword of Power of Haste". Common-rarity items with no affixes show
## just the base display_name.
static func display_name(instance: Dictionary) -> String:
	var base := base_item(instance)
	var name: String = base.display_name if base != null else String(instance.get("id", &""))
	var rarity: StringName = instance.get("rarity", &"common")
	if rarity != &"common":
		name = "%s %s" % [String(rarity).capitalize(), name]
	var affixes: Dictionary = instance.get("affixes", {})
	for affix_id in affixes:
		var affix: AffixDefinition = GameDatabase.affixes.get(affix_id)
		if affix != null:
			name += " %s" % affix.display_name
	return name


## Base item's value for `stat_name` plus the sum of any affix magnitudes
## that target the same stat. Callers cast to int() for attack_damage/armor.
static func total_stat(instance: Dictionary, stat_name: StringName) -> float:
	var base := base_item(instance)
	var total: float = 0.0
	if base != null and stat_name in base:
		total = float(base.get(stat_name))
	var affixes: Dictionary = instance.get("affixes", {})
	for affix_id in affixes:
		var affix: AffixDefinition = GameDatabase.affixes.get(affix_id)
		if affix != null and affix.stat == stat_name:
			total += affixes[affix_id]
	return total


## Grouping key for inventory display: identical id+rarity+affixes stack
## ("Health Potion x3"), but two differently-rolled rares show separately.
static func signature(instance: Dictionary) -> String:
	var affixes: Dictionary = instance.get("affixes", {})
	var affix_keys: Array = affixes.keys()
	affix_keys.sort()
	var parts: Array[String] = [String(instance.get("id", &"")), String(instance.get("rarity", &"common"))]
	for affix_id in affix_keys:
		parts.append("%s:%s" % [affix_id, affixes[affix_id]])
	return "|".join(parts)


## Index of the instance whose "iid" matches, or -1 if not found.
static func find_index_by_iid(instances: Array, iid: String) -> int:
	for i in instances.size():
		if instances[i].get("iid", "") == iid:
			return i
	return -1


## Gold received when selling this instance. Affixes don't add value —
## rarity alone scales the base item's value.
static func sell_value(instance: Dictionary) -> int:
	var base := base_item(instance)
	if base == null:
		return 0
	const RARITY_SELL_MULT: Dictionary[StringName, float] = {
		&"common": 1.0, &"uncommon": 1.5, &"rare": 2.5,
	}
	var rarity: StringName = instance.get("rarity", &"common")
	var mult: float = RARITY_SELL_MULT.get(rarity, 1.0)
	return int(base.value * mult / 2.0)
