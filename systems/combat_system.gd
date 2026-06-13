class_name CombatSystem

## Pure damage-resolution helper, shared identically by player skills/spells
## (skill_component.gd / spellbook_component.gd, via world.gd.apply_area_hit),
## player basic attacks (player_controller.gd) and enemy attacks
## (enemy_controller.gd / dragon_controller.gd / world.gd.apply_cone_hit).
##
## All rolls happen on the SERVER only — every caller is already server-gated,
## and clients only ever see the resulting amount via broadcast damage events
## (enemy.gd.on_enemy_hit / player.gd.on_player_hit), never a re-roll.

## Uniform damage spread around the authored value, so repeated hits read as
## distinct numbers instead of a metronome.
const VARIANCE := 0.15

## Everyone can crit a little even bare-handed; weapons add on top
## (equipment_component.total_crit_chance / EnemyDefinition.crit_chance).
const BASE_CRIT_CHANCE := 0.05
const CRIT_MULTIPLIER := 2.0


## Resolves one hit: (base + attack_bonus), ±VARIANCE, crit roll, then flat
## armor mitigation — clamped so a connecting hit always deals at least 1.
## Returns {"amount": int, "is_crit": bool}.
static func compute_hit(base_damage: int, attack_bonus: int, armor: int,
		crit_chance: float, rng: RandomNumberGenerator) -> Dictionary:
	var raw := float(base_damage + attack_bonus) * rng.randf_range(1.0 - VARIANCE, 1.0 + VARIANCE)
	var is_crit := rng.randf() < crit_chance
	if is_crit:
		raw *= CRIT_MULTIPLIER
	return {"amount": maxi(1, roundi(raw) - armor), "is_crit": is_crit}
