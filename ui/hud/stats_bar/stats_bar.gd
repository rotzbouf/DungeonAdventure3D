extends Control

@onready var _level_label: Label = $VBox/LevelLabel
@onready var _hp_bar: TextureProgressBar = $VBox/HpBar
@onready var _hp_label: Label = $VBox/HpBar/HpLabel
@onready var _mp_bar: TextureProgressBar = $VBox/MpBar
@onready var _mp_label: Label = $VBox/MpBar/MpLabel
@onready var _gold_label: Label = $VBox/GoldLabel
@onready var _status_effects: HBoxContainer = $VBox/StatusEffects

## Display name + color per status id (status_effect_component.gd catalog).
const STATUS_DISPLAY: Dictionary[StringName, Array] = {
	&"poison": ["POISONED", Color(0.4, 0.9, 0.3)],
	&"burn": ["BURNING", Color(1, 0.55, 0.15)],
	&"slow": ["SLOWED", Color(0.5, 0.7, 1)],
	&"stun": ["STUNNED", Color(1, 0.85, 0.3)],
}


## Driven by the local player's StatusEffectComponent.effects_changed
## (replicated active_effects) — see hud.gd._connect_to_player.
func update_status_effects(ids: Array[StringName]) -> void:
	for child in _status_effects.get_children():
		child.queue_free()
	for effect_id in ids:
		var display: Array = STATUS_DISPLAY.get(effect_id, [String(effect_id).to_upper(), Color.WHITE])
		var label := Label.new()
		label.text = display[0]
		label.modulate = display[1]
		label.add_theme_font_size_override("font_size", 12)
		_status_effects.add_child(label)


func update_level(new_level: int) -> void:
	_level_label.text = "Lv %d" % new_level


func update_hp(hp: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_label.text = "HP  %d / %d" % [hp, max_hp]


func update_mp(mp: int, max_mp: int) -> void:
	_mp_bar.max_value = max_mp
	_mp_bar.value = mp
	_mp_label.text = "MP  %d / %d" % [mp, max_mp]


func update_gold(gold: int) -> void:
	_gold_label.text = "Gold: %d" % gold
