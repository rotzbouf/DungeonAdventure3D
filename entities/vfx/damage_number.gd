class_name DamageNumber

## Floating 3D damage/heal number, shared by enemy hits (enemy.gd.on_enemy_hit)
## and player hits (player.gd.on_player_hit). Purely cosmetic: every amount
## shown here was rolled on the server and broadcast — never recomputed locally.
##
## Built in code (no scene) and parented under World, NOT under the entity it
## describes — so a label outlives an enemy that despawns 0.6s after death and
## its tween never captures a freed node (lesson: tweens/lambdas must not
## outlive what they reference).

const LabelFont := preload("res://assets/fonts/Cinzel-Variable.ttf")

const COLOR_PHYSICAL := Color(1, 1, 1, 1)
const COLOR_PHYSICAL_ON_PLAYER := Color(1, 0.25, 0.25, 1)
const COLOR_CRIT := Color(1, 0.82, 0.2, 1)
const COLOR_POISON := Color(0.4, 0.9, 0.3, 1)
const COLOR_BURN := Color(1, 0.55, 0.15, 1)
const COLOR_HEAL := Color(0.35, 1, 0.45, 1)


## `target_is_player` only affects the physical-damage color (red when a
## player is the victim, white against enemies).
static func spawn(world: Node, pos: Vector3, amount: int, is_crit: bool,
		damage_type: StringName, target_is_player: bool = false) -> void:
	if world == null:
		return
	var label := Label3D.new()
	label.text = ("+%d" % amount) if damage_type == &"heal" else str(amount)
	label.font = LabelFont
	label.font_size = 76 if is_crit else 48
	label.modulate = _color_for(is_crit, damage_type, target_is_player)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	world.add_child(label)
	label.global_position = pos + Vector3(0, 2.0, 0)

	var duration := 1.3 if is_crit else 1.0
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.0, duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, duration)
	tween.tween_callback(label.queue_free)


static func _color_for(is_crit: bool, damage_type: StringName, target_is_player: bool) -> Color:
	if is_crit:
		return COLOR_CRIT
	match damage_type:
		&"poison":
			return COLOR_POISON
		&"burn":
			return COLOR_BURN
		&"heal":
			return COLOR_HEAL
		_:
			return COLOR_PHYSICAL_ON_PLAYER if target_is_player else COLOR_PHYSICAL
