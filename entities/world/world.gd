extends Node3D

## The one authoritative dungeon level. Both server and client load this same
## res:// scene locally — guaranteeing one shared world lineage by virtue of
## being identical shipped content — while the SERVER alone drives the
## dynamic state within it (spawning/despawning players on connect/disconnect).
## spawn_function runs identically on every peer so replicated spawns
## reconstruct the same node everywhere.

## Server-only feedback for the requesting peer's character-creation UI.
## The RPCs below exist purely to cross the network to *that one client*;
## their bodies just translate "I was called" into these local signals so
## the (client-only) UI can connect idiomatically without referencing RPCs
## as if they were callbacks.
signal character_creation_succeeded()
signal character_creation_failed(reason: String)

## Server -> the player who entered the activated ExitPortal. Bridges
## exit_portal.gd's on_floor_cleared RPC to a local signal the HUD connects
## to, mirroring the character_creation_* bridge pattern above.
signal floor_cleared(xp_reward: int, new_floor: int)

const _DungeonDebugOverlay := preload("res://entities/world/dungeon_debug_overlay.gd")

const PLAYER_SCENE := "res://entities/player/player.tscn"
const ENEMY_SCENE := "res://entities/enemy/enemy.tscn"
const DRAGON_SCENE := "res://entities/enemy/boss/dragon.tscn"
const LOOT_SCENE := "res://entities/items/loot_drop/loot_drop.tscn"
const MAX_CHARACTER_NAME_LENGTH := 24

# New characters always start in town (SpawnPoints[0..TOWN_SPAWN_COUNT-1] are
# TownSpawn1/TownSpawn2 — see the SpawnPoints reorder in world.tscn). Cycling
# spawn_index through just these two avoids spawning every new player on top
# of each other (the coincident-spawn collision issue from earlier
# milestones) without dropping anyone into the dungeon's old Spawn1-4 slots.
const TOWN_SPAWN_COUNT := 2
const SPAWN_HEIGHT := 0.0  # body origin sits at the character's feet — the capsule's
                           # CollisionShape3D/MeshInstance3D are offset up by half their
                           # height (0.9), so y=0 rests it exactly on the y=0 floor/navmesh

# 4-unit grid cell size matching the Kenney Modular Dungeon Kit pieces. Every
# room/corridor footprint in the layout is a union of these cells, and every
# cell shares its corner vertices (by exact position) with its neighbours, so
# the polygons built below connect into one navigable mesh with no gaps. The
# starting town (world.tscn's Town subtree) reuses this same grid: its Kenney
# town-kit pieces are natively 1x1 and scaled 4x (WALL_SCALE in world.tscn)
# so each scaled piece spans exactly one cell.
const CELL_SIZE := 4.0

@onready var _navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var _town_navigation_region: NavigationRegion3D = $TownNavigationRegion3D
@onready var _players_root: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _enemies_root: Node3D = $Enemies
@onready var _enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var _loot_spawner: MultiplayerSpawner = $LootSpawner
@onready var _loot_drops: Node3D = $LootDrops
@onready var _exit_portal: Area3D = $ExitPortal
@onready var _dungeon_state_spawner: MultiplayerSpawner = $DungeonStateSpawner
@onready var _dungeon_state_root: Node = $DungeonStateRoot

var _loot_counter: int = 0
var _current_floor: int = 1
var _dungeon_layout: Array = []
var _dungeon_rng := RandomNumberGenerator.new()

## Server-only RNG for area/cone damage rolls (CombatSystem.compute_hit) —
## mirrors enemy_controller.gd's _rng. Never used client-side; clients only
## see rolled results via broadcast damage events.
var _combat_rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	_combat_rng.randomize()


func _ready() -> void:
	_town_navigation_region.navigation_mesh = _build_town_navigation_mesh()
	_build_town_floor_colliders()
	_build_town_wall_colliders()
	_spawner.spawn_function = _spawn_player
	_enemy_spawner.spawn_function = _spawn_enemy
	_loot_spawner.spawn_function = _spawn_loot
	_dungeon_state_spawner.spawn_function = _spawn_dungeon_state

	if NetworkMode.is_server():
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		_dungeon_rng.randomize()
		_dungeon_state_spawner.spawn({"floor_number": 1, "dungeon_seed": _dungeon_rng.randi()})
	if NetworkMode.is_client():
		AudioManager.play_ambient(&"dungeon_ambience")
		AudioManager.play_music(&"dungeon_explore")


## Client -> server: "I'd like to play this race/class under this name."
## Mirrors player_input.gd's request_move_to — declared on a node (World)
## that exists at an identical path on every peer, so Godot can route the
## call to the same place server-side, before any character exists yet.
@rpc("any_peer", "call_local", "reliable")
func request_create_character(race_id: StringName, class_id: StringName, character_name: String) -> void:
	if not NetworkMode.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var reason := _validate_character_request(sender_id, race_id, class_id, character_name)
	if reason != "":
		push_warning("world: rejected character creation from peer %d: %s" % [sender_id, reason])
		on_character_creation_failed.rpc_id(sender_id, reason)
		return
	_spawner.spawn({
		"peer_id": sender_id,
		"spawn_index": _players_root.get_child_count() % TOWN_SPAWN_COUNT,
		"race_id": race_id,
		"class_id": class_id,
		"character_name": character_name,
	})
	on_character_created.rpc_id(sender_id)


func _validate_character_request(sender_id: int, race_id: StringName, class_id: StringName, character_name: String) -> String:
	if not GameDatabase.races.has(race_id):
		return "Unknown race."
	if not GameDatabase.classes.has(class_id):
		return "Unknown class."
	var trimmed_name := character_name.strip_edges()
	if trimmed_name.is_empty():
		return "Name cannot be empty."
	if trimmed_name.length() > MAX_CHARACTER_NAME_LENGTH:
		return "Name is too long."
	if _players_root.get_node_or_null("Player_%d" % sender_id) != null:
		return "You already have a character."
	return ""


## Server -> the requesting peer only (rpc_id, never broadcast). Bodies just
## bridge "called over the network" to a local signal — see the comment on
## the signals above for why the UI connects to those, not to these RPCs.
@rpc("authority", "call_local", "reliable")
func on_character_created() -> void:
	character_creation_succeeded.emit()


@rpc("authority", "call_local", "reliable")
func on_character_creation_failed(reason: String) -> void:
	character_creation_failed.emit(reason)


func _on_peer_disconnected(peer_id: int) -> void:
	var existing := _players_root.get_node_or_null("Player_%d" % peer_id)
	if existing != null:
		existing.queue_free()


## Deterministic reconstruction from replicated data — must behave identically
## wherever it runs (server creates + replicates incl. to late joiners; every
## peer reconstructs the same node from the same `data` dict). `data` only
## ever contains primitives (StringName/String/int) — that's what survives
## MultiplayerSpawner's variant encoding; Resources/PackedScenes would not.
## Race/class are re-resolved from GameDatabase by id, never passed directly.
func _spawn_player(data: Dictionary) -> Node:
	var player: CharacterBody3D = load(PLAYER_SCENE).instantiate()
	var peer_id: int = int(data.peer_id)
	player.race_id = data.race_id
	player.class_id = data.class_id
	player.character_name = data.character_name
	player.name = "Player_%d" % peer_id
	player.position = get_spawn_position(int(data.spawn_index))

	# Initialize M6 components from the class definition. This is deterministic
	# (same class_def on every peer via GameDatabase), so the values set here
	# are byte-identical to what the MultiplayerSynchronizer spawn snapshot
	# carries — no conflict, just harmless redundancy for the initial frame.
	var class_def: CharacterClass = GameDatabase.classes.get(data.class_id)
	if class_def != null:
		player.get_node("StatsComponent").initialize(class_def)
		player.get_node("LevelComponent").initialize(class_def)
		player.get_node("SkillComponent").initialize(class_def)
		player.get_node("SpellbookComponent").initialize(class_def)

	return player


## World-space position (feet/floor level) of the SpawnPoints marker at
## `index`, wrapping if out of range. Used both for initial spawns
## (_spawn_player) and for player.gd's respawn-on-death.
func get_spawn_position(index: int) -> Vector3:
	var spawn_points := _spawn_points.get_children()
	var slot: Node3D = spawn_points[index % spawn_points.size()]
	return Vector3(slot.position.x, SPAWN_HEIGHT, slot.position.z)


## Runs on every peer when the DungeonStateSpawner spawns or replicates a
## DungeonState node (including late-joiner replay). Rebuilds the entire
## dungeon deterministically from (floor_number, dungeon_seed) so all peers
## converge on the same layout without any extra RPCs.
func _spawn_dungeon_state(data: Dictionary) -> Node:
	var state := DungeonState.new()
	state.floor_number = int(data.floor_number)
	state.dungeon_seed = int(data.dungeon_seed)
	state.name = "DungeonState_%d" % state.floor_number
	_rebuild_dungeon(state.floor_number, state.dungeon_seed)
	return state


## Tears down the current dungeon and builds a fresh one for `floor_num` using
## the given seed. Runs on every peer (called from _spawn_dungeon_state).
## Server also respawns enemies; clients only rebuild geometry.
func _rebuild_dungeon(floor_num: int, dungeon_seed: int) -> void:
	var generated := DungeonGenerator.generate(floor_num, dungeon_seed)
	_dungeon_layout = generated.layout

	var dungeon_level: Node3D = _navigation_region.get_node("DungeonLevel")
	for child in dungeon_level.get_children():
		child.free()  # immediate — not spawner-tracked

	for cname: String in ["FloorColliders", "WallColliders"]:
		var existing := get_node_or_null(cname)
		if existing != null:
			existing.free()

	_instantiate_dungeon_pieces(dungeon_level)
	_navigation_region.navigation_mesh = _build_dungeon_navigation_mesh()
	_build_floor_colliders()
	_build_wall_colliders()

	var boss_center := Vector3.ZERO
	for entry: Dictionary in _dungeon_layout:
		if entry.get("role", &"") == &"boss":
			boss_center = Vector3(entry.center.x * CELL_SIZE, 0.0, entry.center.y * CELL_SIZE)
			break
	_exit_portal.global_position = boss_center
	_exit_portal.deactivate()

	var boss_area := get_node_or_null("BossChamberArea") as Area3D
	if boss_area != null:
		boss_area.global_position = Vector3(boss_center.x, 1.0, boss_center.z)

	if NetworkMode.is_server():
		for child in _enemies_root.get_children():
			child.queue_free()
		for child in _loot_drops.get_children():
			child.queue_free()
		_loot_counter = 0
		for i: int in generated.enemy_spawns.size():
			var sp: Dictionary = generated.enemy_spawns[i]
			_enemy_spawner.spawn({
				"definition_id": sp.definition_id,
				"spawn_index": i,
				"pos_x": sp.pos_x,
				"pos_z": sp.pos_z,
			})

	if OS.has_environment("DEBUG_LAYOUT"):
		_debug_dump_layout()

	if OS.has_environment("DEBUG_CELLS"):
		var old_overlay := get_node_or_null("DungeonDebugOverlay")
		if old_overlay != null:
			old_overlay.free()
		var cell_roles: Dictionary = {}
		for entry: Dictionary in _dungeon_layout:
			var role: StringName = entry.get("role", &"")
			var footprint: Dictionary = PIECE_FOOTPRINTS[entry["piece"]]
			var notches: Array = footprint.get("notches", [])
			for lc: Vector2i in footprint["cells"]:
				if lc in notches:
					continue
				var wc: Vector2i = _rotate_cell(lc, entry["rot"]) + entry["center"]
				cell_roles[wc] = role
		var overlay = _DungeonDebugOverlay.new()
		overlay.name = "DungeonDebugOverlay"
		add_child(overlay)
		overlay.build(cell_roles)


## Server-only: advance to the next floor. Frees the current DungeonState
## (which clears the old dungeon via the spawner's delete replication), spawns
## a new one with a fresh seed, and teleports all players to the entry room.
func _advance_floor() -> void:
	if not NetworkMode.is_server():
		return
	_current_floor += 1
	for child in _dungeon_state_root.get_children():
		child.queue_free()
	_dungeon_state_spawner.spawn({"floor_number": _current_floor, "dungeon_seed": _dungeon_rng.randi()})
	for child in _players_root.get_children():
		var player := child as CharacterBody3D
		if player != null:
			player.position = Vector3(0.0, SPAWN_HEIGHT, 0.0)


## Deterministic reconstruction from replicated data — see _spawn_player.
func _spawn_enemy(data: Dictionary) -> Node:
	var definition_id: StringName = data.definition_id
	var scene_path := DRAGON_SCENE if definition_id == &"dragon" else ENEMY_SCENE
	var enemy: CharacterBody3D = load(scene_path).instantiate()
	enemy.definition_id = definition_id
	enemy.name = "Enemy_%d" % int(data.spawn_index)
	enemy.position = Vector3(float(data.pos_x), SPAWN_HEIGHT, float(data.pos_z))
	return enemy


## Deterministic reconstruction from replicated data — see _spawn_player.
## Position is split into primitive floats for the same reason `data` never
## carries Resources/PackedScenes/Vector3 directly elsewhere in this file.
func _spawn_loot(data: Dictionary) -> Node:
	var loot: StaticBody3D = load(LOOT_SCENE).instantiate()
	loot.item_instance = data.item_instance
	loot.name = "Loot_%d" % int(data.loot_index)
	loot.position = Vector3(data.pos_x, data.pos_y, data.pos_z)
	return loot


## Server-side area damage applied after a skill/spell cast
## (skill_component.gd / spellbook_component.gd) — every enemy within `range`
## of `origin` takes a CombatSystem.compute_hit roll (rolled PER TARGET, since
## armor differs per enemy), attributed to `attacker_peer_id` for the XP
## award on death (see enemy.gd._award_kill_xp).
func apply_area_hit(origin: Vector3, range: float, base_damage: int, attack_bonus: int,
		crit_chance: float, attacker_peer_id: int, status_id := &"",
		status_duration := 0.0, status_magnitude := 0.0) -> void:
	if not NetworkMode.is_server():
		return
	for child in _enemies_root.get_children():
		var enemy := child as CharacterBody3D
		if enemy == null:
			continue
		if enemy.global_position.distance_to(origin) <= range:
			var health: Node = enemy.get_node_or_null("HealthComponent")
			var stats: Node = enemy.get_node_or_null("StatsComponent")
			if health != null:
				var armor: int = stats.armor if stats != null else 0
				var hit := CombatSystem.compute_hit(base_damage, attack_bonus, armor, crit_chance, _combat_rng)
				health.apply_damage(hit.amount, attacker_peer_id, hit.is_crit)
				if status_id != &"":
					var status: Node = enemy.get_node_or_null("StatusEffectComponent")
					if status != null:
						status.apply_effect(status_id, status_duration, status_magnitude, attacker_peer_id)


## Server-side cone damage applied by dragon_controller.gd's fire-breath
## attack — every player within `range` of `origin` and within
## `cone_degrees / 2` of `forward` takes a CombatSystem.compute_hit roll
## (rolled per target: armor differs per player), shown as &"burn" damage,
## plus an optional burn DoT (status_effect_component.gd) when
## `burn_duration` > 0.
func apply_cone_hit(origin: Vector3, forward: Vector3, range: float, cone_degrees: float,
		base_damage: int, burn_duration := 0.0, burn_magnitude := 0.0) -> void:
	if not NetworkMode.is_server():
		return
	var half_angle := deg_to_rad(cone_degrees / 2.0)
	for child in _players_root.get_children():
		var player := child as CharacterBody3D
		if player == null:
			continue
		var to_player := player.global_position - origin
		if to_player.length() > range:
			continue
		if forward.angle_to(to_player.normalized()) > half_angle:
			continue
		var stats: Node = player.get_node_or_null("StatsComponent")
		if stats != null:
			var equipment: Node = player.get_node_or_null("EquipmentComponent")
			var armor: int = equipment.total_armor() if equipment != null else 0
			var hit := CombatSystem.compute_hit(base_damage, 0, armor, 0.0, _combat_rng)
			stats.apply_damage(hit.amount, hit.is_crit, &"burn")
			if burn_duration > 0.0:
				var status: Node = player.get_node_or_null("StatusEffectComponent")
				if status != null:
					status.apply_effect(&"burn", burn_duration, burn_magnitude)


## Server-only: drop a pickup at `drop_position`, replicated to every peer via
## the loot MultiplayerSpawner. Called by enemy.gd.on_died.
func spawn_loot_drop(drop_position: Vector3, instance: Dictionary) -> void:
	if not NetworkMode.is_server():
		return
	_loot_spawner.spawn({
		"loot_index": _loot_counter,
		"item_instance": instance,
		"pos_x": drop_position.x,
		"pos_y": drop_position.y,
		"pos_z": drop_position.z,
	})
	_loot_counter += 1


## Server-only: rolls `loot_table` against the shared combat RNG. Called by
## enemy.gd.on_died — _combat_rng stays private to this file.
func roll_loot(loot_table: LootTable) -> Array[Dictionary]:
	return LootRollSystem.roll(loot_table, _combat_rng)


## Called on every peer (from enemy.gd.on_died, broadcast) when the dragon
## boss dies — reveals the Boss Chamber's exit portal and (server-only)
## starts listening for a player walking into it.
func activate_exit_portal() -> void:
	_exit_portal.activate()


## Server -> the one player who walked into the activated ExitPortal
## (exit_portal.gd._on_body_entered). Bridges to the floor_cleared signal the
## HUD's floor-cleared overlay connects to.
@rpc("authority", "call_local", "reliable")
func on_floor_cleared(xp_reward: int, new_floor: int) -> void:
	floor_cleared.emit(xp_reward, new_floor)


# --- Dungeon geometry helpers ------------------------------------------------
#
# _dungeon_layout (populated by DungeonGenerator each floor) is the runtime
# source of truth for the dungeon's room/corridor pieces. _cells_from_layout()
# (walkable-footprint grid → nav mesh and floor/wall colliders) and
# _instantiate_dungeon_pieces() (actual GLB placements) both derive from it,
# so a piece's position/rotation can never drift between "what's walkable" and
# "what's rendered".
#
# ROTATION_BASES[r] is the Transform3D.basis for a rotation of r * 90 degrees
# about Y. The same (x, z) mapping rotates integer cell offsets via
# _rotate_cell(), since cell centers are just (cx, cz) * CELL_SIZE and the
# mapping is linear — so a piece's mesh and its footprint cells always rotate
# together.
const ROTATION_BASES: Array[Basis] = [
	Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)),    # r=0: (x,z) -> (x,z)
	Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)),   # r=1: (x,z) -> (-z,x)
	Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)),  # r=2: (x,z) -> (-x,-z)
	Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)),   # r=3: (x,z) -> (z,-x)
]

# Local cell footprints (centered on each piece's own origin, before
# rotation/translation), derived from each GLB's mesh AABB. room_corner is
# the only piece with a "notch" - the namesake cut-away corner with no floor
# geometry, listed separately so rotation carries it along with the piece.
const PIECE_FOOTPRINTS := {
	"corridor": {"cells": [Vector2i(0, 0)]},
	"intersection": {"cells": [Vector2i(0, 0)]},  # kept for any static layouts
	"room_small": {"cells": [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]},
	"room_wide": {"cells": [
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	]},
	"room_corner": {
		"cells": [
			Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		],
		"notches": [Vector2i(-1, -1)],
	},
}

## Rotates a cell offset by `rot` * 90 degrees, matching ROTATION_BASES[rot]'s
## (x, z) mapping - so a piece's footprint cells rotate the same way as its
## mesh.
static func _rotate_cell(cell: Vector2i, rot: int) -> Vector2i:
	match rot:
		1: return Vector2i(-cell.y, cell.x)
		2: return Vector2i(-cell.x, -cell.y)
		3: return Vector2i(cell.y, -cell.x)
		_: return cell


## Returns the (cell_x, cell_z) grid coordinates of every walkable cell in the
## dungeon. Derived from `layout` (the same shape as the old DUNGEON_LAYOUT
## constant, now generated by DungeonGenerator): each piece's local footprint,
## minus notches, is rotated and translated to its world-space position.
static func _cells_from_layout(layout: Array) -> Array[Vector2i]:
	var seen := {}
	var cells: Array[Vector2i] = []
	for entry: Dictionary in layout:
		var footprint: Dictionary = PIECE_FOOTPRINTS[entry["piece"]]
		var notches: Array = footprint.get("notches", [])
		for local_cell: Vector2i in footprint["cells"]:
			if local_cell in notches:
				continue
			var cell: Vector2i = _rotate_cell(local_cell, entry["rot"]) + entry["center"]
			if not seen.has(cell):
				seen[cell] = true
				cells.append(cell)
	return cells


## Instantiates every piece in `_dungeon_layout` as a child of `parent`
## (NavigationRegion3D/DungeonLevel), using the same center/rot convention.
func _instantiate_dungeon_pieces(parent: Node3D) -> void:
	for entry: Dictionary in _dungeon_layout:
		var piece: Node3D = (entry["scene"] as PackedScene).instantiate()
		piece.name = entry["name"]
		var center: Vector2i = entry["center"]
		piece.transform = Transform3D(ROTATION_BASES[entry["rot"]], Vector3(center.x, 0.0, center.y) * CELL_SIZE)
		parent.add_child(piece)


## Returns the world-space walkable area(s) of the starting town, as
## axis-aligned rectangles in the XZ plane (position/size in world units).
## This is the town's equivalent of _dungeon_cells() -- the single source of
## truth for its footprint -- but expressed as rectangles since the plaza is
## one large open area rather than a maze of individually-placed pieces.
## _town_cells() expands these onto the same CELL_SIZE grid as
## _dungeon_cells() so the nav/floor/wall builders below can be shared
## between dungeon and town.
static func _town_floor_areas() -> Array[Rect2]:
	return [
		Rect2(Vector2(-50, -10), Vector2(20, 20)),  # main plaza
	]


## Expands _town_floor_areas()'s rectangles onto the CELL_SIZE grid (see
## _dungeon_cells()'s cell-coordinate convention), deduplicated. Rectangle
## bounds are expected to align to the grid (offset by CELL_SIZE/2, since
## cell (cx, cz) is centered on (cx*CELL_SIZE, cz*CELL_SIZE)).
static func _town_cells() -> Array[Vector2i]:
	var seen := {}
	var cells: Array[Vector2i] = []
	var half := CELL_SIZE / 2.0
	for rect in _town_floor_areas():
		var cx0 := int(round((rect.position.x + half) / CELL_SIZE))
		var cx1 := int(round((rect.position.x + rect.size.x + half) / CELL_SIZE))
		var cz0 := int(round((rect.position.y + half) / CELL_SIZE))
		var cz1 := int(round((rect.position.y + rect.size.y + half) / CELL_SIZE))
		for cx in range(cx0, cx1):
			for cz in range(cz0, cz1):
				var cell := Vector2i(cx, cz)
				if not seen.has(cell):
					seen[cell] = true
					cells.append(cell)
	return cells


## Builds a navmesh as a union of CELL_SIZE unit cells. Adjacent cells are
## deduplicated down to shared corner vertices, so every internal edge is a
## literal shared-index edge between two polygons and the NavigationServer
## connects them into one walkable mesh with no baking step (deterministic
## and headless-safe). Shared by _build_dungeon_navigation_mesh and
## _build_town_navigation_mesh.
func _build_navigation_mesh_for_cells(cells: Array[Vector2i]) -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var vertex_index := {}
	var half := CELL_SIZE / 2.0
	var polygons: Array[PackedInt32Array] = []

	for cell in cells:
		var x0 := cell.x * CELL_SIZE - half
		var x1 := cell.x * CELL_SIZE + half
		var z0 := cell.y * CELL_SIZE - half
		var z1 := cell.y * CELL_SIZE + half
		var corners := [
			Vector3(x0, 0.0, z0),
			Vector3(x1, 0.0, z0),
			Vector3(x1, 0.0, z1),
			Vector3(x0, 0.0, z1),
		]
		var polygon := PackedInt32Array()
		for corner in corners:
			if not vertex_index.has(corner):
				vertex_index[corner] = vertices.size()
				vertices.append(corner)
			polygon.append(vertex_index[corner])
		polygons.append(polygon)

	nav_mesh.vertices = vertices
	for polygon in polygons:
		nav_mesh.add_polygon(polygon)

	return nav_mesh


func _build_dungeon_navigation_mesh() -> NavigationMesh:
	return _build_navigation_mesh_for_cells(_cells_from_layout(_dungeon_layout))


## Builds the starting town's navmesh from _town_cells(). Assigned to a
## separate NavigationRegion3D from the dungeon's, since the two areas are
## disconnected walkable islands -- only reachable from each other via
## area_portal.gd's teleports, not a walkable corridor.
func _build_town_navigation_mesh() -> NavigationMesh:
	return _build_navigation_mesh_for_cells(_town_cells())


## Builds invisible floor colliders matching `cells` (one thin StaticBody3D
## box per cell, top face at y=0), parented under a new child node named
## `parent_name`. The imported Kenney meshes carry no collision shapes of
## their own, so without this, player_input.gd's click-to-move raycast has
## nothing to hit and every click silently no-ops. Shared by
## _build_floor_colliders and _build_town_floor_colliders.
func _build_floor_colliders_for_cells(cells: Array[Vector2i], parent_name: String) -> void:
	var floor_colliders := Node3D.new()
	floor_colliders.name = parent_name
	add_child(floor_colliders)
	const BOX_HEIGHT := 0.2
	for cell in cells:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(CELL_SIZE, BOX_HEIGHT, CELL_SIZE)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(cell.x * CELL_SIZE, -BOX_HEIGHT / 2.0, cell.y * CELL_SIZE)
		floor_colliders.add_child(body)


func _build_floor_colliders() -> void:
	_build_floor_colliders_for_cells(_cells_from_layout(_dungeon_layout), "FloorColliders")


func _build_town_floor_colliders() -> void:
	_build_floor_colliders_for_cells(_town_cells(), "TownFloorColliders")


## Builds invisible wall colliders along every edge of `cells` that doesn't
## border another cell in the same set (i.e. the perimeter of the walkable
## footprint, including door-sized gaps like the dungeon's room-corner notch).
## The imported Kenney meshes carry no collision shapes, so without this,
## CharacterBody3D.move_and_slide() has nothing to stop it sliding into the
## void beyond the navmesh/floor colliders - this keeps movement confined to
## exactly the area those colliders cover. For the town (which has no visible
## wall meshes at all) this is the sole boundary keeping players on the plaza.
## Shared by _build_wall_colliders and _build_town_wall_colliders.
func _build_wall_colliders_for_cells(cells: Array[Vector2i], parent_name: String) -> void:
	var wall_colliders := Node3D.new()
	wall_colliders.name = parent_name
	add_child(wall_colliders)
	const WALL_HEIGHT := 4.5
	const WALL_THICKNESS := 0.2
	var half := CELL_SIZE / 2.0
	var cell_set := {}
	for cell in cells:
		cell_set[cell] = true
	for cell in cell_set:
		var center := Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)
		if not cell_set.has(Vector2i(cell.x, cell.y - 1)):
			_add_wall_collider(wall_colliders, center + Vector3(0.0, 0.0, -half), Vector3(CELL_SIZE, WALL_HEIGHT, WALL_THICKNESS))
		if not cell_set.has(Vector2i(cell.x, cell.y + 1)):
			_add_wall_collider(wall_colliders, center + Vector3(0.0, 0.0, half), Vector3(CELL_SIZE, WALL_HEIGHT, WALL_THICKNESS))
		if not cell_set.has(Vector2i(cell.x - 1, cell.y)):
			_add_wall_collider(wall_colliders, center + Vector3(-half, 0.0, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL_SIZE))
		if not cell_set.has(Vector2i(cell.x + 1, cell.y)):
			_add_wall_collider(wall_colliders, center + Vector3(half, 0.0, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL_SIZE))


func _build_wall_colliders() -> void:
	_build_wall_colliders_for_cells(_cells_from_layout(_dungeon_layout), "WallColliders")


func _build_town_wall_colliders() -> void:
	_build_wall_colliders_for_cells(_town_cells(), "TownWallColliders")


func _add_wall_collider(parent: Node3D, edge_center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = edge_center + Vector3(0.0, size.y / 2.0, 0.0)
	parent.add_child(body)


func _debug_dump_layout() -> void:
	for entry: Dictionary in _dungeon_layout:
		var cx: int = entry.center.x
		var cz: int = entry.center.y
		print("[LAYOUT] %-15s piece=%-12s center=(%d,%d) rot=%d world=(%g,0,%g)" % [
			entry.name, entry.piece, cx, cz, entry.rot,
			float(cx) * CELL_SIZE, float(cz) * CELL_SIZE,
		])
	var cells := _cells_from_layout(_dungeon_layout)
	print("[LAYOUT] cell count = %d" % cells.size())
	_debug_assert_entry_room_cells(cells)


static func _debug_assert_entry_room_cells(cells: Array[Vector2i]) -> void:
	var cell_set := {}
	for c in cells:
		cell_set[c] = true
	var expected: Array[Vector2i] = [
		Vector2i( 1, -1), Vector2i( 0, -1), Vector2i(-1, -1),
		Vector2i( 1,  0), Vector2i( 0,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i(-1,  1),
	]
	var excluded := Vector2i(1, 1)
	var ok := true
	for c: Vector2i in expected:
		if not cell_set.has(c):
			print("[CELL TEST] FAIL — expected cell %s missing" % str(c))
			ok = false
	if cell_set.has(excluded):
		print("[CELL TEST] FAIL — notch cell %s should be excluded" % str(excluded))
		ok = false
	if ok:
		print("[CELL TEST] PASS")
