class_name CombatSystem

## Pure damage-resolution helper, shared identically by player skills/spells
## (skill_component.gd / spellbook_component.gd, via world.gd.apply_area_hit)
## and enemy attacks (enemy_controller.gd). The single seam for future
## modifiers (defense, crit, elemental resistance) — currently a direct
## passthrough of the attack's authored damage_base, clamped non-negative.
static func compute_damage(base_damage: int) -> int:
	return maxi(0, base_damage)
