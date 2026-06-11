class_name SkillUnlockSystem

## Returns skills newly unlocked AT `level` (not all known skills — caller accumulates).
## M6: level 1 grants the class's starting set. M11: level 2 adds a per-class
## bonus skill. Higher-level unlock tables are added when the level-cap design
## is finalised.
static func newly_unlocked_at(class_def: CharacterClass, level: int) -> Array[StringName]:
	if level == 1:
		return class_def.starting_skill_ids.duplicate()
	if level == 2:
		match class_def.id:
			&"warrior": return [&"shield_bash"]
			&"rogue": return [&"evasion"]
	return []
