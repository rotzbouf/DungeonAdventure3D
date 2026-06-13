extends Node

## Server-only combat/movement tuning for this enemy, copied from its
## EnemyDefinition at spawn time. Not replicated — clients never need these
## values directly; they only observe their effects (position, hp).

var attack_damage: int = 0
var move_speed: float = 2.5
var aggro_radius: float = 6.0
var attack_range: float = 1.5
var xp_reward: int = 0

# Combat variety (M15) — see enemy_definition.gd for field semantics.
var armor: int = 0
var crit_chance: float = 0.0
var attack_interval: float = 1.5
var inflict_status: StringName = &""
var inflict_status_duration: float = 0.0
var inflict_status_magnitude: float = 0.0
var inflict_status_chance: float = 1.0

# Boss-only fields (M13) — harmless zeros/defaults for non-boss enemies.
var is_boss: bool = false
var phase2_hp_ratio: float = 0.5
var fire_breath_damage: int = 0
var fire_breath_range: float = 6.0
var fire_breath_cone_degrees: float = 60.0
var fire_breath_cooldown: float = 4.0


func initialize(def: EnemyDefinition) -> void:
	attack_damage = def.attack_damage
	move_speed = def.move_speed
	aggro_radius = def.aggro_radius
	attack_range = def.attack_range
	xp_reward = def.xp_reward
	armor = def.armor
	crit_chance = def.crit_chance
	attack_interval = def.attack_interval
	inflict_status = def.inflict_status
	inflict_status_duration = def.inflict_status_duration
	inflict_status_magnitude = def.inflict_status_magnitude
	inflict_status_chance = def.inflict_status_chance
	is_boss = def.is_boss
	phase2_hp_ratio = def.phase2_hp_ratio
	fire_breath_damage = def.fire_breath_damage
	fire_breath_range = def.fire_breath_range
	fire_breath_cone_degrees = def.fire_breath_cone_degrees
	fire_breath_cooldown = def.fire_breath_cooldown
