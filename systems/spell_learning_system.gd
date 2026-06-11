class_name SpellLearningSystem

## attempt_learn is pure — the server calls it authoritatively; the client may
## call it for an odds preview (advisory only; the server always re-rolls
## independently and the client's number is never trusted).
##
## Returns {success: bool, roll: float, threshold: float}.
## threshold = base_chance + (intelligence - int_requirement) * 0.05, clamped
## to [0.05, 0.95] so there is always a small chance of failure or success.
static func attempt_learn(spell: Spell, intelligence: int, rng: RandomNumberGenerator) -> Dictionary:
	var threshold := clampf(
		spell.base_chance + (intelligence - spell.int_requirement) * 0.05,
		0.05, 0.95
	)
	var roll := rng.randf()
	return {success = roll < threshold, roll = roll, threshold = threshold}
