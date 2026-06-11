extends Node

## Server-authoritative HP pool for an enemy. Mirrors stats_component.gd's
## shape: replicated via MultiplayerSynchronizer (spawn=true, ON_CHANGE) so
## every peer (incl. late joiners) sees current HP, and emits `died` once
## when HP first reaches zero so enemy.gd can broadcast the death sequence.

signal hp_changed(hp: int, max_hp: int)
signal died()
signal hit(amount: int)

var hp: int = 0:
	set(value):
		var was_alive := hp > 0
		hp = value
		hp_changed.emit(hp, max_hp)
		if was_alive and hp <= 0:
			died.emit()

var max_hp: int = 0:
	set(value):
		max_hp = value
		hp_changed.emit(hp, max_hp)

## Set by world.gd.apply_area_hit so a kill can award XP to the right player.
## Server-only, never replicated.
var last_attacker_peer_id: int = -1


func initialize(def: EnemyDefinition) -> void:
	max_hp = def.max_hp
	hp = max_hp


func apply_damage(amount: int, attacker_peer_id: int = -1) -> void:
	if not NetworkMode.is_server():
		return
	if attacker_peer_id >= 0:
		last_attacker_peer_id = attacker_peer_id
	if amount > 0 and hp > 0:
		hit.emit(amount)
	hp = maxi(0, hp - amount)
