extends Node

## Server-authoritative learned-spell list + spell-casting pipeline.
## Mirrors skill_component's shape: replicated ON_CHANGE + spawn=true,
## request → validate → mutate → broadcast for both learning and casting.
##
## SpellLearningSystem.attempt_learn is server-authoritative; the server always
## re-rolls independently regardless of any client-side preview call.

signal spells_changed(ids: Array[StringName])
signal spell_cast(spell_id: StringName)
signal spell_use_rejected(reason: String)
signal spell_learned(spell_id: StringName, roll: float, threshold: float)
signal spell_learn_failed(spell_id: StringName, reason: String)

var known_spell_ids: Array[StringName] = []:
	set(value):
		known_spell_ids = value
		spells_changed.emit(value)

var _cooldowns: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func initialize(_class_def: CharacterClass) -> void:
	pass  # Spellbook starts empty regardless of class; reserved for future starter spells.


@rpc("any_peer", "call_local", "reliable")
func request_read_scroll(spell_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player := get_parent() as CharacterBody3D
	if sender_id != player.owning_peer_id():
		push_warning("spellbook: rejected read_scroll from non-owning peer %d" % sender_id)
		return

	var spell: Spell = GameDatabase.spells.get(spell_id)
	if spell == null:
		on_learn_result.rpc_id(sender_id, spell_id, false, 0.0, 0.0, "Unknown spell.")
		return
	if spell_id in known_spell_ids:
		on_learn_result.rpc_id(sender_id, spell_id, false, 0.0, 0.0, "Already known.")
		return

	var stats: Node = player.get_node_or_null("StatsComponent")
	var intelligence: int = stats.intelligence if stats != null else 0
	var result := SpellLearningSystem.attempt_learn(spell, intelligence, _rng)

	if result.success:
		var updated := known_spell_ids.duplicate()
		updated.append(spell_id)
		known_spell_ids = updated

	on_learn_result.rpc_id(sender_id, spell_id, result.success, result.roll, result.threshold, "")


@rpc("authority", "call_local", "reliable")
func on_learn_result(spell_id: StringName, success: bool, roll: float, threshold: float, reason: String) -> void:
	if success:
		spell_learned.emit(spell_id, roll, threshold)
	else:
		spell_learn_failed.emit(spell_id, reason if reason != "" else "Learning failed.")


@rpc("any_peer", "call_local", "reliable")
func request_cast_spell(spell_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var player := get_parent() as CharacterBody3D
	if sender_id != player.owning_peer_id():
		push_warning("spellbook: rejected cast from non-owning peer %d" % sender_id)
		return

	if not spell_id in known_spell_ids:
		on_spell_rejected.rpc_id(sender_id, "Spell not known.")
		return

	var now := Time.get_ticks_msec()
	if _cooldowns.get(spell_id, 0) > now:
		on_spell_rejected.rpc_id(sender_id, "Spell on cooldown.")
		return

	var spell: Spell = GameDatabase.spells.get(spell_id)
	if spell == null:
		on_spell_rejected.rpc_id(sender_id, "Spell data not found.")
		return
	var stats: Node = player.get_node_or_null("StatsComponent")
	if stats != null and stats.mp < spell.mp_cost:
		on_spell_rejected.rpc_id(sender_id, "Not enough MP.")
		return

	if stats != null:
		stats.mp = maxi(0, stats.mp - spell.mp_cost)
	_cooldowns[spell_id] = now + int(spell.cooldown_seconds * 1000.0)

	if spell.damage_base > 0:
		var world := get_tree().root.find_child("World", true, false)
		# Spells scale with INT (not weapon damage) — keeps the mage fantasy
		# distinct from gear-driven melee; crit chance still comes from gear.
		var int_bonus: int = (stats.intelligence / 2) if stats != null else 0
		var equipment: Node = player.get_node_or_null("EquipmentComponent")
		var crit_chance: float = equipment.total_crit_chance() if equipment != null else CombatSystem.BASE_CRIT_CHANCE
		world.apply_area_hit(player.global_position, spell.range, spell.damage_base, int_bonus, crit_chance, sender_id)

	on_spell_cast.rpc(spell_id)


@rpc("authority", "call_local", "reliable")
func on_spell_cast(spell_id: StringName) -> void:
	if NetworkMode.is_client():
		print("[spell] %s cast %s" % [get_parent().name, spell_id])
		_maybe_spawn_projectile_vfx(spell_id)
	spell_cast.emit(spell_id)


## Purely cosmetic: spawns a traveling projectile VFX toward the nearest
## in-range enemy when the cast spell defines one. Runs identically on every
## peer since on_spell_cast is broadcast (call_local) from the server.
func _maybe_spawn_projectile_vfx(spell_id: StringName) -> void:
	var spell: Spell = GameDatabase.spells.get(spell_id)
	if spell == null or spell.projectile_vfx == null:
		return

	var caster := get_parent() as Node3D
	var world := get_tree().root.find_child("World", true, false)
	if world == null:
		return
	var enemies_root := world.get_node_or_null("Enemies")
	if enemies_root == null:
		return

	var nearest: CharacterBody3D = null
	var nearest_dist := spell.range
	for child in enemies_root.get_children():
		var enemy := child as CharacterBody3D
		if enemy == null:
			continue
		var dist := caster.global_position.distance_to(enemy.global_position)
		if dist <= nearest_dist:
			nearest_dist = dist
			nearest = enemy
	if nearest == null:
		return

	var projectile := spell.projectile_vfx.instantiate()
	world.add_child(projectile)
	projectile.global_position = caster.global_position + Vector3(0, 1.2, 0)
	projectile.target_position = nearest.global_position + Vector3(0, 1.0, 0)


@rpc("authority", "call_local", "reliable")
func on_spell_rejected(reason: String) -> void:
	spell_use_rejected.emit(reason)
