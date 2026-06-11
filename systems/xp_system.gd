class_name XPSystem

## Pure, deterministic XP → level computation. No randomness, no side effects.
## current_xp is XP accumulated *within* the current level (resets on level-up).
static func compute_gain(current_xp: int, current_level: int, amount: int, curve: LevelCurve) -> Dictionary:
	var new_xp := current_xp + amount
	var new_level := current_level
	while new_level - 1 < curve.xp_per_level.size():
		var threshold: int = curve.xp_per_level[new_level - 1]
		if new_xp >= threshold:
			new_xp -= threshold
			new_level += 1
		else:
			break
	return {
		"new_xp": new_xp,
		"new_level": new_level,
		"leveled_up": new_level > current_level,
	}
