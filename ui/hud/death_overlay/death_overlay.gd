extends PanelContainer

## Centered "You Died" banner shown while the local player's HP is 0
## (hud.gd connects this to StatsComponent.hp_changed, which is already
## replicated to every peer — no extra RPC needed). Stays fully visible until
## hide_overlay is called once hp recovers (player.gd's respawn), then fades
## out — same tween-based fade as floor_cleared_overlay.

const FADE_OUT_TIME := 0.5

@onready var _label: Label = $Label


func show_overlay() -> void:
	_label.text = "You Died\nRespawning..."
	modulate.a = 1.0


func hide_overlay() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_TIME)
