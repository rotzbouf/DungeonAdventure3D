class_name LevelCurve
extends Resource

## xp_per_level[i] = XP needed to advance from level (i+1) to (i+2).
## Index 0 = XP required to go from level 1 to level 2.
@export var id: StringName = &""
@export var xp_per_level: Array[int] = []
