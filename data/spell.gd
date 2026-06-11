class_name Spell
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var int_requirement: int = 1
@export var base_chance: float = 0.5
@export var mp_cost: int = 10
@export var cooldown_seconds: float = 2.0
@export var range: float = 2.0
@export var damage_base: int = 0
@export var projectile_vfx: PackedScene = null
