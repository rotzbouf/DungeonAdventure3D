class_name EquipValidationSystem

## Pure rule-evaluation: no scene-tree dependencies, callable identically from
## server validation and (later) client-side previews. First module in
## systems/ — the architecture's home for shared server/client game rules.
##
## Narrow on purpose: validates only what's real today (item exists, slot
## matches). Stat/level gating belongs here too eventually, but StatsComponent/
## LevelComponent don't exist yet (M4 deferred them for the same reason
## CharacterClass.base_stats is still empty) — adding fake gates now would
## mean inventing stat shapes before the systems that give them meaning exist.
## When those land, this signature grows additively: can_equip(item_id, slot,
## stats, level) — not a rewrite.

## Returns "" if the request is valid, or a human-readable rejection reason.
static func can_equip(item_id: StringName, slot: StringName) -> String:
	var item: EquipmentItem = GameDatabase.items.get(item_id)
	if item == null:
		return "Unknown item."
	if item.slot != slot:
		return "That item doesn't go in that slot."
	return ""
