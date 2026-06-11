extends Node

## Server-authoritative known-skill list + skill-use pipeline. Mirrors
## equipment_component's shape: request → validate → mutate → broadcast.
##
## known_skill_ids is replicated (spawn=true, ON_CHANGE). Its setter fires on
## clients for both the spawn snapshot and level-up updates — the same ordering
## hazard as equipped_slots doesn't apply here because there's no visual to
## attach; the setter just emits a signal for the HUD.
##
## _cooldowns is server-only and not replicated; clients infer cooldown state
## from on_skill_cast broadcasts (or future cooldown-sync for the hotbar).

signal skills_changed(ids: Array[StringName])
signal skill_cast(skill_id: StringName)
signal skill_use_rejected(reason: String)

var known_skill_ids: Array[StringName] = []:
	set(value):
		known_skill_ids = value
		skills_changed.emit(value)

## skill_id -> Time.get_ticks_msec() expiry. Server-only, never replicated.
var _cooldowns: Dictionary = {}


func initialize(class_def: CharacterClass) -> void:
	known_skill_ids = SkillUnlockSystem.newly_unlocked_at(class_def, 1)


@rpc("any_peer", "call_local", "reliable")
func request_use_skill(skill_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player := get_parent() as CharacterBody3D
	if sender_id != player.owning_peer_id():
		push_warning("skill_component: rejected use request from non-owning peer %d" % sender_id)
		return

	var stats: Node = player.get_node_or_null("StatsComponent")
	var current_mp: int = stats.mp if stats != null else 0
	var reason := SkillUseSystem.can_use(skill_id, known_skill_ids, _cooldowns, current_mp)
	if reason != "":
		on_skill_rejected.rpc_id(sender_id, reason)
		return

	var skill: Skill = GameDatabase.skills.get(skill_id)
	# Deduct MP and set cooldown.
	if stats != null:
		stats.mp = maxi(0, stats.mp - skill.mp_cost)
	_cooldowns[skill_id] = Time.get_ticks_msec() + int(skill.cooldown_seconds * 1000.0)

	# Award XP.
	var level_comp: Node = player.get_node_or_null("LevelComponent")
	if level_comp != null:
		level_comp.gain_xp(skill.xp_reward)

	if skill.damage_base > 0:
		var world := get_tree().root.find_child("World", true, false)
		world.apply_area_hit(player.global_position, skill.range, CombatSystem.compute_damage(skill.damage_base), sender_id)

	on_skill_cast.rpc(skill_id)


## Broadcast to all peers + server (call_local). In M6 just emits a signal;
## M7+ will trigger an animation on the caster's model_view.
@rpc("authority", "call_local", "reliable")
func on_skill_cast(skill_id: StringName) -> void:
	if NetworkMode.is_client():
		print("[skill] %s cast %s" % [get_parent().name, skill_id])
	skill_cast.emit(skill_id)


@rpc("authority", "call_local", "reliable")
func on_skill_rejected(reason: String) -> void:
	skill_use_rejected.emit(reason)
