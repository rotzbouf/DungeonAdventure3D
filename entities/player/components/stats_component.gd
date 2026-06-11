extends Node

## Server-authoritative HP/MP pool. Replicated via MultiplayerSynchronizer
## (spawn=true, ON_CHANGE) so every peer sees the current totals — and late
## joiners get the snapshot without history replay, exactly like equipped_slots.
##
## Initialised deterministically from CharacterClass.base_stats in
## world.gd._spawn_player (runs on every peer), so no init RPC is needed.
## Setters emit signals used by the local player's HUD; the headless server
## emits them too but they have no listeners there.

signal hp_changed(hp: int, max_hp: int)
signal mp_changed(mp: int, max_mp: int)
signal intelligence_changed(value: int)

var hp: int = 0:
	set(value):
		hp = value
		hp_changed.emit(hp, max_hp)

var max_hp: int = 0:
	set(value):
		max_hp = value

var mp: int = 0:
	set(value):
		mp = value
		mp_changed.emit(mp, max_mp)

var max_mp: int = 0:
	set(value):
		max_mp = value

var intelligence: int = 0:
	set(value):
		intelligence = value
		intelligence_changed.emit(intelligence)


func initialize(class_def: CharacterClass) -> void:
	max_hp = class_def.base_stats.get(&"max_hp", 100)
	hp = max_hp
	max_mp = class_def.base_stats.get(&"max_mp", 50)
	mp = max_mp
	intelligence = class_def.base_stats.get(&"intelligence", 5)
