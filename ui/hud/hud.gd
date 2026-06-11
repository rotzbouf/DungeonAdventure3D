extends CanvasLayer

## CLIENT-ONLY master HUD. Polls in _process until the local player node
## appears in the scene tree, then connects to StatsComponent/LevelComponent/
## SkillComponent signals for live updates. Uses the same node-path convention
## as world.gd ("Player_<peer_id>" under World/Players) to find the right node.
##
## Panel toggles (I/Q/T/M) are handled here since they're pure UI state with
## no networking concern.

@onready var _stats_bar = $StatsBar
@onready var _hotbar = $Hotbar
@onready var _inventory = $InventoryPanel
@onready var _quest_log = $QuestLogPanel
@onready var _travel = $TravelPanel
@onready var _map = $MapPanel

var _connected := false
var _searching := false  # becomes true only after connected_to_server fires


func _ready() -> void:
	NetworkManager.connected_to_server.connect(func(): _searching = true, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if _connected or not _searching:
		return
	var world := get_tree().get_root().get_node_or_null("GameRoot/World")
	if world == null:
		return
	var peer_id := multiplayer.get_unique_id()
	var player := world.get_node_or_null("Players/Player_%d" % peer_id)
	if player == null:
		return
	_connect_to_player(player)


func _connect_to_player(player: Node) -> void:
	var stats: Node = player.get_node_or_null("StatsComponent")
	var level_comp: Node = player.get_node_or_null("LevelComponent")
	var skill_comp: Node = player.get_node_or_null("SkillComponent")
	var spellbook: Node = player.get_node_or_null("SpellbookComponent")
	var inventory: Node = player.get_node_or_null("InventoryComponent")
	if stats == null or level_comp == null or skill_comp == null or spellbook == null or inventory == null:
		return  # Components not yet ready — retry next frame.

	_stats_bar.update_level(level_comp.level)
	_stats_bar.update_hp(stats.hp, stats.max_hp)
	_stats_bar.update_mp(stats.mp, stats.max_mp)
	_hotbar.update_skills(skill_comp.known_skill_ids)
	_hotbar.set_skill_component(skill_comp)
	_hotbar.update_spells(spellbook.known_spell_ids)
	_hotbar.set_spellbook_component(spellbook)
	_inventory.set_inventory_component(inventory)

	stats.hp_changed.connect(_stats_bar.update_hp)
	stats.mp_changed.connect(_stats_bar.update_mp)
	level_comp.level_changed.connect(_stats_bar.update_level)
	level_comp.leveled_up.connect(_on_leveled_up)
	skill_comp.skills_changed.connect(_hotbar.update_skills)
	skill_comp.skill_use_rejected.connect(_on_skill_rejected)
	skill_comp.skill_cast.connect(func(_id: StringName) -> void: AudioManager.play_sfx(&"sword_swing"))
	spellbook.spells_changed.connect(_hotbar.update_spells)
	spellbook.spell_learned.connect(_on_spell_learned)
	spellbook.spell_use_rejected.connect(_on_skill_rejected)
	spellbook.spell_cast.connect(func(_id: StringName) -> void: AudioManager.play_sfx(&"spell_cast"))

	_connected = true


func _on_leveled_up(new_level: int, _new_skill_ids: Array[StringName]) -> void:
	print("[hud] Level up! Now level %d" % new_level)


func _on_skill_rejected(reason: String) -> void:
	print("[hud] Skill/spell rejected: %s" % reason)


func _on_spell_learned(spell_id: StringName, roll: float, threshold: float) -> void:
	print("[hud] Learned spell: %s (roll %.2f vs threshold %.2f)" % [spell_id, roll, threshold])
	AudioManager.play_sfx(&"spell_learn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_inventory.visible = not _inventory.visible
		AudioManager.play_sfx(&"ui_click")
	elif event.is_action_pressed("toggle_quest_log"):
		_quest_log.visible = not _quest_log.visible
		AudioManager.play_sfx(&"ui_click")
	elif event.is_action_pressed("toggle_travel"):
		_travel.visible = not _travel.visible
		AudioManager.play_sfx(&"ui_click")
	elif event.is_action_pressed("toggle_map"):
		_map.visible = not _map.visible
		AudioManager.play_sfx(&"ui_click")
