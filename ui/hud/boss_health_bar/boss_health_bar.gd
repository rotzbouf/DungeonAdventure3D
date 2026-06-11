extends PanelContainer

## Top-center HP bar for the dragon boss. Hidden until the local player enters
## the Boss Chamber (see hud.gd's BossChamberArea body_entered/exited
## handling); update_hp mirrors stats_bar.gd's HP bar update.

@onready var _hp_bar: TextureProgressBar = $HpBar
@onready var _hp_label: Label = $HpBar/HpLabel


func update_hp(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_label.text = "Dragon HP  %d / %d" % [hp, max_hp]
