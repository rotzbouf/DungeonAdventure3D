extends CharacterBody3D

## Orchestrator for a networked player character. Branches on NetworkMode and
## on whether this peer owns the character to decide which parts run where:
##
##   Server          -> authoritative Controller only (no camera/input/HUD: headless-safe)
##   Owning client   -> Controller (renders replicated result) + Input + CameraRig
##   Other clients   -> Controller (renders replicated result) only
##
## The body itself and its Controller are server-authoritative (authority = 1);
## the Input node's authority is the owning peer — this is the "split
## authority (input -> peer, logic -> server)" the architecture relies on.
## Spawned (and named "Player_<peer_id>") by the world's MultiplayerSpawner.

## Chosen-at-creation identity. Set by world.gd._spawn_player on the freshly
## instantiated node, BEFORE it enters the tree (no _enter_tree/_ready
## ordering hazard). Intentionally NOT in the MultiplayerSynchronizer config:
## _spawn_player is a deterministic pure function of the replicated spawn
## `data` dict (see world.gd), so every peer — including late joiners —
## reconstructs byte-identical values without runtime sync, exactly like
## `name` (Player_<peer_id>) already does. Don't "fix" this by adding sync.
var race_id: StringName
var class_id: StringName
var character_name: String

## Server-only: how long a player stays at 0 HP (HUD shows the death overlay
## during this window — see hud.gd's hp_changed handler) before respawning at
## SpawnPoints[0] with full HP.
const RESPAWN_DELAY := 3.0

@onready var _controller: Node = $Controller
@onready var _input: Node = $Input
@onready var _camera_rig: Node3D = $CameraRig
@onready var _stats: Node = $StatsComponent
@onready var _inventory: Node = $InventoryComponent


func _enter_tree() -> void:
	set_multiplayer_authority(1)
	# Must happen before MultiplayerSynchronizer's own _enter_tree/_ready (children
	# are readied bottom-up) — otherwise replication starts with a null config.
	# @onready vars aren't populated yet here, so fetch the node directly.
	_setup_replication(get_node("MultiplayerSynchronizer"))


func _ready() -> void:
	var owning_peer := owning_peer_id()
	_controller.set_multiplayer_authority(1)
	_input.set_multiplayer_authority(owning_peer)

	var is_owner := owning_peer == multiplayer.get_unique_id() and NetworkMode.is_client()
	_input.set_active(is_owner)
	_camera_rig.set_active(is_owner)

	if NetworkMode.is_server():
		_stats.died.connect(_on_died)


## Server-only: HP hit 0 (stats_component.gd's died signal). After
## RESPAWN_DELAY, heal to full and return to the entry spawn point — the HUD's
## death overlay (hud.gd, driven by the same replicated hp_changed signal)
## covers the in-between feedback, so no extra RPC is needed here.
func _on_died() -> void:
	_drop_inventory_on_death()
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_respawn)


## Server-only: scatter the player's bag as lootable pickups at the death
## spot (before _respawn moves the body away) so it can be retrieved later.
## Equipped gear is kept.
func _drop_inventory_on_death() -> void:
	var world := get_tree().root.find_child("World", true, false)
	var death_position := global_position
	for item_id: StringName in _inventory.items:
		var offset := Vector3(randf_range(-0.75, 0.75), 0.0, randf_range(-0.75, 0.75))
		world.spawn_loot_drop(death_position + offset, item_id)
	_inventory.items.clear()


func _respawn() -> void:
	var world := get_tree().root.find_child("World", true, false)
	_controller.reset_to(world.get_spawn_position(0))
	_stats.hp = _stats.max_hp


## Public so sibling components (e.g. equipment_component.gd's request_equip)
## can verify a sender owns this character without duplicating the
## name-parsing — mirrors how player_input.gd checks its own authority.
func owning_peer_id() -> int:
	var parts := name.split("_")
	if parts.size() >= 2 and parts[-1].is_valid_int():
		return int(parts[-1])
	return 1


func _setup_replication(synchronizer: MultiplayerSynchronizer) -> void:
	var config := SceneReplicationConfig.new()
	for prop_path in [NodePath(".:position"), NodePath(".:rotation"), NodePath("Controller:move_blend")]:
		config.add_property(prop_path)
		config.property_set_spawn(prop_path, true)
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	# These properties change rarely (ON_CHANGE) but late joiners need them
	# (spawn=true). Same reasoning as equipped_slots — see equipment_component.gd.
	var on_change_paths := [
		NodePath("EquipmentComponent:equipped_slots"),
		NodePath("StatsComponent:hp"),
		NodePath("StatsComponent:max_hp"),
		NodePath("StatsComponent:mp"),
		NodePath("StatsComponent:max_mp"),
		NodePath("StatsComponent:intelligence"),
		NodePath("StatsComponent:gold"),
		NodePath("LevelComponent:level"),
		NodePath("LevelComponent:current_xp"),
		NodePath("SkillComponent:known_skill_ids"),
		NodePath("SpellbookComponent:known_spell_ids"),
		NodePath("InventoryComponent:items"),
	]
	for prop_path in on_change_paths:
		config.add_property(prop_path)
		config.property_set_spawn(prop_path, true)
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = config
