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
## Item id carried by the loot drop spawned on death (M10 will resolve this
## against an item content table; M9 just prints it on pickup).
@export var loot_item_id: StringName = &""
@export var visual_scene: PackedScene
