class_name Rarity

## Display tiers for items (M15 groundwork — purely cosmetic until M16's loot
## tables/affixes give rarity mechanical weight). Consumed by the inventory
## and shop lists for name coloring.

const COLORS: Dictionary[StringName, Color] = {
	&"common": Color(0.88, 0.88, 0.85),
	&"uncommon": Color(0.45, 0.85, 0.4),
	&"rare": Color(0.4, 0.6, 1.0),
}


## Duck-typed: ConsumableItem and other non-equipment resources carry no
## rarity field and read as common.
static func color_for(item) -> Color:
	if item == null:
		return COLORS[&"common"]
	var rarity = item.get("rarity")
	if rarity == null:
		return COLORS[&"common"]
	return COLORS.get(rarity, COLORS[&"common"])
