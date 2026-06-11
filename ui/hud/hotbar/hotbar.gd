extends Control

## CLIENT-ONLY. Shows up to 10 hotbar slots (keys 1-0). Slots are filled with
## skills first, then known spells. Pressing a bound key dispatches to the
## appropriate component (SkillComponent for skills, SpellbookComponent for spells).

const HOTBAR_SIZE := 10
const HOTBAR_ACTIONS := [
	"hotbar_1","hotbar_2","hotbar_3","hotbar_4","hotbar_5",
	"hotbar_6","hotbar_7","hotbar_8","hotbar_9","hotbar_0",
]

var _skill_component: Node = null
var _spellbook_component: Node = null
var _skill_ids: Array[StringName] = []
var _spell_ids: Array[StringName] = []
var _slots: Array = []  # Array of {id: StringName, type: StringName}

@onready var _slot_labels: Array = _collect_slot_labels()


func set_skill_component(comp: Node) -> void:
	_skill_component = comp


func set_spellbook_component(comp: Node) -> void:
	_spellbook_component = comp


func update_skills(ids: Array[StringName]) -> void:
	_skill_ids = ids.duplicate()
	_rebuild_slots()


func update_spells(ids: Array[StringName]) -> void:
	_spell_ids = ids.duplicate()
	_rebuild_slots()


func _collect_slot_labels() -> Array:
	var labels: Array = []
	for slot_node in $Slots.get_children():
		labels.append(slot_node.get_node("VBox/SkillLabel"))
	return labels


func _rebuild_slots() -> void:
	_slots.clear()
	for id in _skill_ids:
		if _slots.size() >= HOTBAR_SIZE:
			break
		_slots.append({id = id, type = &"skill"})
	for id in _spell_ids:
		if _slots.size() >= HOTBAR_SIZE:
			break
		_slots.append({id = id, type = &"spell"})
	_refresh_labels()


func _refresh_labels() -> void:
	for i in HOTBAR_SIZE:
		if i >= _slot_labels.size():
			break
		var label: Label = _slot_labels[i]
		if i >= _slots.size():
			label.text = ""
			continue
		var slot: Dictionary = _slots[i]
		var display := ""
		if slot.type == &"skill":
			var skill = GameDatabase.skills.get(slot.id)
			display = skill.display_name if skill != null else str(slot.id)
		else:
			var spell = GameDatabase.spells.get(slot.id)
			display = spell.display_name if spell != null else str(slot.id)
		label.text = display


func _unhandled_input(event: InputEvent) -> void:
	for i in HOTBAR_ACTIONS.size():
		if event.is_action_pressed(HOTBAR_ACTIONS[i]):
			if i >= _slots.size():
				return
			var slot: Dictionary = _slots[i]
			if slot.type == &"skill" and _skill_component != null:
				_skill_component.request_use_skill.rpc_id(1, slot.id)
			elif slot.type == &"spell" and _spellbook_component != null:
				_spellbook_component.request_cast_spell.rpc_id(1, slot.id)
			return
