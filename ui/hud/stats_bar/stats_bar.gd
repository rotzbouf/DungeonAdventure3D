extends Control

@onready var _level_label: Label = $VBox/LevelLabel
@onready var _hp_bar: TextureProgressBar = $VBox/HpBar
@onready var _hp_label: Label = $VBox/HpBar/HpLabel
@onready var _mp_bar: TextureProgressBar = $VBox/MpBar
@onready var _mp_label: Label = $VBox/MpBar/MpLabel
@onready var _gold_label: Label = $VBox/GoldLabel


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
