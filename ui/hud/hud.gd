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
@onready var _boss_health_bar = $BossHealthBar
@onready var _floor_cleared_overlay = $FloorClearedOverlay
@onready var _death_overlay = $DeathOverlay
@onready var _shop_panel = $ShopPanel
@onready var _storage_panel = $StoragePanel
@onready var _level_up_overlay = $LevelUpOverlay

var _connected := false
var _searching := false  # becomes true only after connected_to_server fires
var _world_connected := false
var _dragon_connected := false
var _local_player: Node


func _ready() -> void:
	NetworkManager.connected_to_server.connect(func(): _searching = true, CONNECT_ONE_SHOT)
	# connected_to_server is a client-side ENet signal and never fires for the
	# listen host itself — it is "connected" from the start, so begin searching
	# immediately (same listen-host special case as character_creation_screen).
	if NetworkMode.mode == NetworkMode.Mode.LISTEN_HOST:
		_searching = true


func _process(_delta: float) -> void:
	if not _searching:
		return
	var world := get_tree().get_root().get_node_or_null("GameRoot/World")
	if world == null:
		return
	if not _world_connected:
		world.floor_cleared.connect(_floor_cleared_overlay.show_overlay)
		_world_connected = true
	if not _dragon_connected:
		_connect_to_dragon(world)
	if _connected:
		return
	var peer_id := multiplayer.get_unique_id()
	var player := world.get_node_or_null("Players/Player_%d" % peer_id)
	if player == null:
		return
	_local_player = player
	_connect_to_player(player)


## Finds the dragon boss under World/Enemies (if spawned yet) and wires its
## HP to the boss health bar, plus the Boss Chamber trigger that toggles the
## bar's visibility for the local player.
func _connect_to_dragon(world: Node) -> void:
	for enemy in world.get_node("Enemies").get_children():
		if enemy.definition_id != &"dragon":
			continue
		var health: Node = enemy.get_node_or_null("HealthComponent")
		if health == null:
			return  # Not ready yet — retry next frame.
		_boss_health_bar.update_hp(health.hp, health.max_hp)
		health.hp_changed.connect(_boss_health_bar.update_hp)
		var boss_area: Area3D = world.get_node("BossChamberArea")
		boss_area.body_entered.connect(_on_boss_chamber_entered)
		boss_area.body_exited.connect(_on_boss_chamber_exited)
		_dragon_connected = true
		return


func _on_boss_chamber_entered(body: Node3D) -> void:
	if body == _local_player:
		_boss_health_bar.visible = true


func _on_boss_chamber_exited(body: Node3D) -> void:
	if body == _local_player:
		_boss_health_bar.visible = false


func _connect_to_player(player: Node) -> void:
	var stats: Node = player.get_node_or_null("StatsComponent")
	var level_comp: Node = player.get_node_or_null("LevelComponent")
	var skill_comp: Node = player.get_node_or_null("SkillComponent")
	var spellbook: Node = player.get_node_or_null("SpellbookComponent")
	var inventory: Node = player.get_node_or_null("InventoryComponent")
	var status: Node = player.get_node_or_null("StatusEffectComponent")
	var equipment: Node = player.get_node_or_null("EquipmentComponent")
	if stats == null or level_comp == null or skill_comp == null or spellbook == null or inventory == null or status == null or equipment == null:
		return  # Components not yet ready — retry next frame.

	_stats_bar.update_level(level_comp.level)
	_stats_bar.update_hp(stats.hp, stats.max_hp)
	_stats_bar.update_mp(stats.mp, stats.max_mp)
	_stats_bar.update_gold(stats.gold)
	_hotbar.update_skills(skill_comp.known_skill_ids)
	_hotbar.set_skill_component(skill_comp)
	_hotbar.update_spells(spellbook.known_spell_ids)
	_hotbar.set_spellbook_component(spellbook)
	_inventory.set_inventory_component(inventory)
	_inventory.set_equipment_component(equipment)

	stats.hp_changed.connect(_stats_bar.update_hp)
	stats.hp_changed.connect(_on_hp_changed)
	stats.mp_changed.connect(_stats_bar.update_mp)
	stats.gold_changed.connect(_stats_bar.update_gold)
	level_comp.level_changed.connect(_stats_bar.update_level)
	level_comp.leveled_up.connect(_on_leveled_up)
	level_comp.level_up_choice_offered.connect(func(level: int, options: Array[StringName]) -> void:
		_level_up_overlay.show_choice(level_comp, level, options))
	skill_comp.skills_changed.connect(_hotbar.update_skills)
	skill_comp.skill_use_rejected.connect(_on_skill_rejected)
	skill_comp.skill_cast.connect(func(_id: StringName) -> void: AudioManager.play_sfx(&"sword_swing"))
	_stats_bar.update_status_effects(status.active_effects)
	status.effects_changed.connect(_stats_bar.update_status_effects)
	spellbook.spells_changed.connect(_hotbar.update_spells)
	spellbook.spell_learned.connect(_on_spell_learned)
	spellbook.spell_use_rejected.connect(_on_skill_rejected)
	spellbook.spell_cast.connect(func(_id: StringName) -> void: AudioManager.play_sfx(&"spell_cast"))

	_connected = true


## Mirrors player.gd's death/respawn flow purely via the already-replicated
## hp value: 0 -> show "You Died", recovering from 0 -> fade it back out.
func _on_hp_changed(hp: int, _max_hp: int) -> void:
	if hp <= 0:
		_death_overlay.show_overlay()
	elif _death_overlay.modulate.a > 0.0:
		_death_overlay.hide_overlay()


func _on_leveled_up(new_level: int, _new_skill_ids: Array[StringName]) -> void:
	print("[hud] Level up! Now level %d" % new_level)


func _on_skill_rejected(reason: String) -> void:
	print("[hud] Skill/spell rejected: %s" % reason)


func _on_spell_learned(spell_id: StringName, roll: float, threshold: float) -> void:
	print("[hud] Learned spell: %s (roll %.2f vs threshold %.2f)" % [spell_id, roll, threshold])
	AudioManager.play_sfx(&"spell_learn")


## Called by merchant.gd's interact() (client-local, no RPC -- opening a UI
## is pure presentation). `player` is always the local player here, since
## interact() is only ever invoked from the owning client's player_input.gd.
func open_shop(shop_id: StringName, player: Node) -> void:
	var shop_component: Node = player.get_node_or_null("ShopComponent")
	var inventory: Node = player.get_node_or_null("InventoryComponent")
	if shop_component == null or inventory == null:
		return
	_shop_panel.open_shop(shop_id, shop_component, inventory)
	AudioManager.play_sfx(&"ui_click")


## Called by storage_chest.gd's interact() (client-local, mirrors open_shop).
func open_storage(storage_chest: Node, player: Node) -> void:
	var inventory: Node = player.get_node_or_null("InventoryComponent")
	if inventory == null:
		return
	_storage_panel.open_storage(storage_chest, inventory)
	AudioManager.play_sfx(&"ui_click")


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
