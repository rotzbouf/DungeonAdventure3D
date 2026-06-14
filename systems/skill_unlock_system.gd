class_name SkillUnlockSystem

## Returns skills newly unlocked AT `level` (not all known skills — caller accumulates).
## M6: level 1 grants the class's starting set. Level 2+ unlocks are presented
## as a choice (see choices_at) rather than auto-granted.
static func newly_unlocked_at(class_def: CharacterClass, level: int) -> Array[StringName]:
	if level == 1:
		return class_def.starting_skill_ids.duplicate()
	return []


## Returns the talent options offered AT `level`, or [] if that level grants
## nothing (or auto-grants via newly_unlocked_at). M16: level 2 gives every
## class a 2-option choice between an existing skill and a new alternative.
static func choices_at(class_def: CharacterClass, level: int) -> Array[StringName]:
	if level == 2:
		match class_def.id:
			&"warrior": return [&"shield_bash", &"cleave"]
			&"rogue": return [&"evasion", &"poison_blade"]
			&"mage": return [&"arcane_bolt", &"frost_nova"]
	return []
