extends Node

## SERVER-AUTHORITATIVE status effects (M15), shared by players and enemies —
## added as a child of player.tscn / enemy.tscn / dragon.tscn. Fixed catalog:
##
##   &"poison"  magnitude = damage per tick (green numbers)
##   &"burn"    magnitude = damage per tick (orange numbers)
##   &"slow"    magnitude = speed multiplier (e.g. 0.5), consumed by the
##              victim's movement code via speed_multiplier()
##   &"stun"    full action lockout, via is_stunned()
##
## The authoritative `_effects` dict is server-only. Clients only receive
## `active_effects` (ids, for HUD display) — DoT damage rides the normal
## damage pipeline (stats_component/enemy_health_component.apply_damage), so
## ticks produce the same broadcast numbers/flashes as any other hit.

signal effects_changed(ids: Array[StringName])

const TICK_INTERVAL := 1.0

## Replicated (ON_CHANGE + spawn=true, registered by player.gd/enemy.gd's
## _setup_replication). The setter fires on clients for both the late-joiner
## spawn snapshot and live updates — it must only emit (never touch the tree):
## on late joiners it can run before _ready/parenting, the same early-setter
## hazard as equipped_slots. Always reassigned whole (never mutated in place):
## in-place Array mutation neither trips ON_CHANGE nor invokes this setter.
var active_effects: Array[StringName] = []:
	set(value):
		active_effects = value
		effects_changed.emit(value)

## Server-only: effect_id -> {expires_msec, magnitude, tick_accum,
## attacker_peer_id}. attacker_peer_id keeps DoT kill credit working through
## enemy_health_component.last_attacker_peer_id.
var _effects: Dictionary = {}


func _ready() -> void:
	set_physics_process(NetworkMode.is_server())


## Server-only. Reapplying an active effect refreshes its duration (and takes
## the new magnitude) rather than stacking.
func apply_effect(effect_id: StringName, duration: float, magnitude: float,
		attacker_peer_id := -1) -> void:
	if not NetworkMode.is_server():
		return
	if effect_id == &"" or duration <= 0.0:
		return
	_effects[effect_id] = {
		"expires_msec": Time.get_ticks_msec() + int(duration * 1000.0),
		"magnitude": magnitude,
		"tick_accum": 0.0,
		"attacker_peer_id": attacker_peer_id,
	}
	_publish_active_effects()


## Server-only: wipe everything (player death/respawn — a respawned player
## must not keep ticking poison).
func clear_all() -> void:
	if not NetworkMode.is_server():
		return
	if _effects.is_empty():
		return
	_effects.clear()
	_publish_active_effects()


func is_stunned() -> bool:
	return _effects.has(&"stun")


## Combined movement multiplier from active slows (just &"slow" today).
func speed_multiplier() -> float:
	var slow = _effects.get(&"slow")
	if slow == null:
		return 1.0
	return clampf(slow.magnitude, 0.05, 1.0)


func _physics_process(delta: float) -> void:
	if _effects.is_empty():
		return
	var now := Time.get_ticks_msec()
	var expired: Array[StringName] = []
	for effect_id: StringName in _effects:
		var effect: Dictionary = _effects[effect_id]
		if effect_id == &"poison" or effect_id == &"burn":
			effect.tick_accum += delta
			while effect.tick_accum >= TICK_INTERVAL:
				effect.tick_accum -= TICK_INTERVAL
				_apply_tick_damage(effect_id, roundi(effect.magnitude), effect.attacker_peer_id)
		if now >= int(effect.expires_msec):
			expired.append(effect_id)
	if not expired.is_empty():
		for effect_id in expired:
			_effects.erase(effect_id)
		_publish_active_effects()


## Routes one DoT tick through the victim's normal damage entry point, so the
## tick broadcasts like any other hit (numbers/flash on every client) and —
## for enemies — keeps kill-XP attribution via attacker_peer_id.
func _apply_tick_damage(damage_type: StringName, amount: int, attacker_peer_id: int) -> void:
	if amount <= 0:
		return
	var victim := get_parent()
	var player_stats: Node = victim.get_node_or_null("StatsComponent")
	var enemy_health: Node = victim.get_node_or_null("HealthComponent")
	if enemy_health != null:
		if enemy_health.hp > 0:
			enemy_health.apply_damage(amount, attacker_peer_id, false, damage_type)
	elif player_stats != null:
		if player_stats.hp > 0:
			player_stats.apply_damage(amount, false, damage_type)


## Whole-array reassignment so the setter runs and ON_CHANGE replication
## notices — see the property comment above.
func _publish_active_effects() -> void:
	var ids: Array[StringName] = []
	for effect_id: StringName in _effects:
		ids.append(effect_id)
	ids.sort()
	active_effects = ids
