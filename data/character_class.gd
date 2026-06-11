class_name CharacterClass
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
## Initial HP/MP pool, keyed by StringName — {&"max_hp": int, &"max_mp": int}.
@export var base_stats: Dictionary = {}
## Skills granted at level 1. Level-up unlocks (M7+) live in a separate table.
@export var starting_skill_ids: Array[StringName] = []
@export var level_curve_id: StringName = &"default"
