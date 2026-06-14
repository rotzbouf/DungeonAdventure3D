class_name EnemyDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: int = 50
@export var attack_damage: int = 5
@export var move_speed: float = 2.5
@export var aggro_radius: float = 6.0
@export var attack_range: float = 1.5
@export var xp_reward: int = 20
## Loot table (content/loot_tables/*.tres) rolled on death (M16).
@export var loot_table: LootTable = null
@export var visual_scene: PackedScene

## Combat variety (M15). Inert defaults — content gives each enemy a
## distinguishing trait (skeleton: armor, goblin: fast crits, zombie: poison)
## without any new code per enemy type.
@export var armor: int = 0
@export var crit_chance: float = 0.0
## Seconds between melee attacks (was the hardcoded ATTACK_COOLDOWN 1.5).
@export var attack_interval: float = 1.5
## Status effect rolled on each landed melee hit (status_effect_component.gd
## ids: &"poison", &"burn", &"slow", &"stun"). Empty = never.
@export var inflict_status: StringName = &""
@export var inflict_status_duration: float = 0.0
## poison/burn: damage per 1s tick; slow: speed multiplier; stun: unused.
@export var inflict_status_magnitude: float = 0.0
@export var inflict_status_chance: float = 1.0

## Boss-only fields (M13). Inert defaults for non-boss enemies — only
## dragon.tres sets these to non-default values.
@export var is_boss: bool = false
@export var phase2_hp_ratio: float = 0.5
@export var fire_breath_damage: int = 0
@export var fire_breath_range: float = 6.0
@export var fire_breath_cone_degrees: float = 60.0
@export var fire_breath_cooldown: float = 4.0
