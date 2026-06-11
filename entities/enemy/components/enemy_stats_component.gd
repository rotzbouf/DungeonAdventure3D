extends Node

## Server-only combat/movement tuning for this enemy, copied from its
## EnemyDefinition at spawn time. Not replicated — clients never need these
## values directly; they only observe their effects (position, hp).

var attack_damage: int = 0
var move_speed: float = 2.5
var aggro_radius: float = 6.0
var attack_range: float = 1.5
var xp_reward: int = 0


func initialize(def: EnemyDefinition) -> void:
	attack_damage = def.attack_damage
	move_speed = def.move_speed
	aggro_radius = def.aggro_radius
	attack_range = def.attack_range
	xp_reward = def.xp_reward
