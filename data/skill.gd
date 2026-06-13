class_name Skill
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var mp_cost: int = 0
@export var cooldown_seconds: float = 1.0
@export var xp_reward: int = 10
@export var range: float = 2.0
@export var damage_base: int = 0

## Status effect applied to every enemy hit by this skill (M15) — same
## catalog/semantics as EnemyDefinition.inflict_status. Inert by default;
## shield_bash.tres stuns for 1s.
@export var inflict_status: StringName = &""
@export var inflict_status_duration: float = 0.0
@export var inflict_status_magnitude: float = 0.0
