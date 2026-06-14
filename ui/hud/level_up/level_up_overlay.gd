extends PanelContainer

## CLIENT-ONLY modal shown when level_component emits level_up_choice_offered
## (a level-2 talent pick — currently the only level with >=2 choices_at
## options, see skill_unlock_system.gd.choices_at). Unlike storage_panel/
## shop_panel (opened by a player interaction), this is driven entirely by a
## server RPC: hud.gd._connect_to_player wires the signal to show_choice().

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _option_buttons: Array[Button] = [$VBox/Option1, $VBox/Option2]

var _level_component: Node
var _level: int = 0
var _option_ids: Array[StringName] = []


func show_choice(level_component: Node, level: int, options: Array[StringName]) -> void:
	_level_component = level_component
	_level = level
	_option_ids = options
	_title_label.text = "Level Up! Choose a skill:"
	for i in _option_buttons.size():
		var button := _option_buttons[i]
		if i < options.size():
			button.text = _describe_skill(GameDatabase.skills.get(options[i]))
			button.visible = true
		else:
			button.visible = false
	visible = true


## "Cleave — 22 dmg, 3.0s cooldown" / "Frost Nova — 12 dmg, Stun 1.5s, 4.0s cooldown".
func _describe_skill(skill: Skill) -> String:
	var parts: Array[String] = ["%d dmg" % skill.damage_base]
	if skill.inflict_status != &"":
		parts.append("%s %.1fs" % [String(skill.inflict_status).capitalize(), skill.inflict_status_duration])
	parts.append("%.1fs cooldown" % skill.cooldown_seconds)
	return "%s — %s" % [skill.display_name, ", ".join(parts)]


func _on_option_1_pressed() -> void:
	_choose(0)


func _on_option_2_pressed() -> void:
	_choose(1)


func _choose(index: int) -> void:
	if index >= _option_ids.size():
		return
	_level_component.request_choose_skill.rpc_id(1, _level, _option_ids[index])
	visible = false
