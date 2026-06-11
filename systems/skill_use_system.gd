class_name SkillUseSystem

## Returns "" on success, or a rejection reason string.
## `cooldowns` maps skill_id -> Time.get_ticks_msec() expiry (server-only dict,
## never replicated — clients rely on on_skill_cast for visual cooldown feedback).
static func can_use(skill_id: StringName, known_ids: Array[StringName], cooldowns: Dictionary, current_mp: int) -> String:
	if not skill_id in known_ids:
		return "You don't know that skill."
	var skill: Skill = GameDatabase.skills.get(skill_id)
	if skill == null:
		return "Unknown skill."
	var cd_expiry: int = cooldowns.get(skill_id, 0)
	if Time.get_ticks_msec() < cd_expiry:
		return "That skill is on cooldown."
	if current_mp < skill.mp_cost:
		return "Not enough mana."
	return ""
