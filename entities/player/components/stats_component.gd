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
signal gold_changed(gold: int)

## Emitted when hp transitions from > 0 to <= 0 (player.gd handles the
## server-side respawn; the HUD's death overlay listens to hp_changed
## directly since that's already replicated to every peer).
signal died()

## SERVER-ONLY: emitted by apply_damage before hp mutates, so player.gd can
## broadcast the hit (amount/crit/type) for client-side feedback — the hp
## value itself still replicates via the existing ON_CHANGE sync.
signal damaged(amount: int, is_crit: bool, damage_type: StringName)

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

var gold: int = 0:
	set(value):
		gold = value
		gold_changed.emit(gold)


## The one damage entry point for players (M15) — enemy controllers and
## world.apply_cone_hit call this instead of mutating hp directly, so every
## hit produces exactly one `damaged` event. Mirrors
## enemy_health_component.apply_damage.
func apply_damage(amount: int, is_crit := false, damage_type := &"physical") -> void:
	if not NetworkMode.is_server():
		return
	if amount > 0 and hp > 0:
		damaged.emit(amount, is_crit, damage_type)
	hp = maxi(0, hp - amount)


func initialize(class_def: CharacterClass) -> void:
	max_hp = class_def.base_stats.get(&"max_hp", 100)
	hp = max_hp
	max_mp = class_def.base_stats.get(&"max_mp", 50)
	mp = max_mp
	intelligence = class_def.base_stats.get(&"intelligence", 5)
	gold = 100
