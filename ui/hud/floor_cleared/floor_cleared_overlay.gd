extends PanelContainer

## Centered "Floor Cleared!" banner shown to a player who walks into the
## activated ExitPortal (world.gd's floor_cleared signal, connected in
## hud.gd). Starts fully transparent; show_overlay snaps to visible, holds,
## then fades out — same tween-based fade as enemy.gd._spawn_damage_label.

const HOLD_TIME := 2.0
const FADE_OUT_TIME := 1.0

@onready var _label: Label = $Label


func show_overlay(xp_reward: int) -> void:
	_label.text = "Floor Cleared!\n+%d XP" % xp_reward
	modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_TIME)
