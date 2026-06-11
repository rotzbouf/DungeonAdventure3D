extends Node

## Server-authoritative level and XP tracking. `level` and `current_xp` are
## replicated via MultiplayerSynchronizer (spawn=true, ON_CHANGE) so HUDs
## update without explicit broadcast.
##
## gain_xp() is server-only; skill_component calls it after a valid skill use.
## on_level_up is sent to the owning peer only (private feedback — new skills,
## level number). Level-badge updates for other peers ride the replicated `level`.

signal level_changed(new_level: int)
signal xp_changed(new_xp: int)
## Emitted on the owning client when a level-up RPC arrives.
signal leveled_up(new_level: int, new_skill_ids: Array[StringName])

var level: int = 1:
	set(value):
		level = value
		level_changed.emit(level)

var current_xp: int = 0:
	set(value):
		current_xp = value
		xp_changed.emit(current_xp)

## Stored so gain_xp can look up the right LevelCurve without needing a parameter.
## Set by initialize() in world.gd._spawn_player before the node enters the tree.
var _class_id: StringName = &""


func initialize(class_def: CharacterClass) -> void:
	_class_id = class_def.id
	level = 1
	current_xp = 0


## Server-only. Called by SkillComponent (or any future XP source).
func gain_xp(amount: int) -> void:
	if not NetworkMode.is_server():
		return
	if _class_id == &"":
		push_warning("level_component: _class_id not set, cannot gain XP")
		return
	var player_class: CharacterClass = GameDatabase.classes.get(_class_id)
	if player_class == null:
		return
	var curve: LevelCurve = GameDatabase.level_curves.get(player_class.level_curve_id)
	if curve == null:
		push_warning("level_component: no curve '%s' for class %s" % [player_class.level_curve_id, _class_id])
		return

	var old_level := level
	var result := XPSystem.compute_gain(current_xp, level, amount, curve)
	current_xp = result.new_xp

	if result.leveled_up:
		level = result.new_level
		var new_skills: Array[StringName] = []
		for lvl in range(old_level + 1, result.new_level + 1):
			new_skills.append_array(SkillUnlockSystem.newly_unlocked_at(player_class, lvl))

		if not new_skills.is_empty():
			var skill_comp: Node = get_parent().get_node_or_null("SkillComponent")
			if skill_comp != null:
				var updated: Array[StringName] = skill_comp.known_skill_ids.duplicate()
				for s in new_skills:
					if not s in updated:
						updated.append(s)
				skill_comp.known_skill_ids = updated

		on_level_up.rpc_id(get_parent().owning_peer_id(), result.new_level, new_skills)


@rpc("authority", "call_local", "reliable")
func on_level_up(new_level: int, new_skill_ids: Array[StringName]) -> void:
	leveled_up.emit(new_level, new_skill_ids)
