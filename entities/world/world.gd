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

const PLAYER_SCENE := "res://entities/player/player.tscn"
const ENEMY_SCENE := "res://entities/enemy/enemy.tscn"
const LOOT_SCENE := "res://entities/items/loot_drop/loot_drop.tscn"
const MAX_CHARACTER_NAME_LENGTH := 24
const SPAWN_HEIGHT := 0.0  # body origin sits at the character's feet — the capsule's
                           # CollisionShape3D/MeshInstance3D are offset up by half their
                           # height (0.9), so y=0 rests it exactly on the y=0 floor/navmesh

# 4-unit grid cell size matching the Kenney Modular Dungeon Kit pieces. Every
# room/corridor footprint in the layout is a union of these cells, and every
# cell shares its corner vertices (by exact position) with its neighbours, so
# the polygons built below connect into one navigable mesh with no gaps.
const CELL_SIZE := 4.0

@onready var _navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var _players_root: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _enemies_root: Node3D = $Enemies
@onready var _enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var _enemy_spawn_points: Node3D = $EnemySpawnPoints
@onready var _loot_spawner: MultiplayerSpawner = $LootSpawner

var _loot_counter: int = 0


func _ready() -> void:
	_navigation_region.navigation_mesh = _build_dungeon_navigation_mesh()
	_spawner.spawn_function = _spawn_player
	_enemy_spawner.spawn_function = _spawn_enemy
	_loot_spawner.spawn_function = _spawn_loot

	if NetworkMode.is_server():
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		# Late joiners: MultiplayerSpawner replicates already-tracked spawns
		# (including the `data` dict each was spawned with) to newly connected
		# peers automatically — no roster code needed. Spawning itself is now
		# client-initiated via request_create_character, not connect-triggered.
		_spawn_initial_enemies()
	else:
		AudioManager.play_ambient(&"dungeon_ambience")
		AudioManager.play_music(&"dungeon_explore")


## Client -> server: "I'd like to play this race/class under this name."
## Mirrors player_input.gd's request_move_to — declared on a node (World)
## that exists at an identical path on every peer, so Godot can route the
## call to the same place server-side, before any character exists yet.
@rpc("any_peer", "call_remote", "reliable")
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
		"spawn_index": _players_root.get_child_count(),
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
@rpc("authority", "call_remote", "reliable")
func on_character_created() -> void:
	character_creation_succeeded.emit()


@rpc("authority", "call_remote", "reliable")
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
	var spawn_points := _spawn_points.get_children()
	var slot: Node3D = spawn_points[int(data.spawn_index) % spawn_points.size()]
	player.position = Vector3(slot.position.x, SPAWN_HEIGHT, slot.position.z)

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


## Server-only: place one enemy at each EnemySpawnPoints marker. Each spawn's
## `data` only carries the definition id + a sequential index — the same
## "primitives only, re-resolve from GameDatabase" shape as _spawn_player.
func _spawn_initial_enemies() -> void:
	var spawn_points := _enemy_spawn_points.get_children()
	for i in spawn_points.size():
		_enemy_spawner.spawn({"definition_id": &"skeleton_warrior", "spawn_index": i})


## Deterministic reconstruction from replicated data — see _spawn_player.
func _spawn_enemy(data: Dictionary) -> Node:
	var enemy: CharacterBody3D = load(ENEMY_SCENE).instantiate()
	var spawn_index: int = int(data.spawn_index)
	enemy.definition_id = data.definition_id
	enemy.name = "Enemy_%d" % spawn_index
	var slot: Node3D = _enemy_spawn_points.get_children()[spawn_index]
	enemy.position = Vector3(slot.position.x, SPAWN_HEIGHT, slot.position.z)
	return enemy


## Deterministic reconstruction from replicated data — see _spawn_player.
## Position is split into primitive floats for the same reason `data` never
## carries Resources/PackedScenes/Vector3 directly elsewhere in this file.
func _spawn_loot(data: Dictionary) -> Node:
	var loot: StaticBody3D = load(LOOT_SCENE).instantiate()
	loot.item_id = data.item_id
	loot.name = "Loot_%d" % int(data.loot_index)
	loot.position = Vector3(data.pos_x, data.pos_y, data.pos_z)
	return loot


## Server-side area damage applied after a skill/spell cast
## (skill_component.gd / spellbook_component.gd) — every enemy within `range`
## of `origin` takes `damage`, attributed to `attacker_peer_id` for the XP
## award on death (see enemy.gd._award_kill_xp).
func apply_area_hit(origin: Vector3, range: float, damage: int, attacker_peer_id: int) -> void:
	if not NetworkMode.is_server():
		return
	for child in _enemies_root.get_children():
		var enemy := child as CharacterBody3D
		if enemy == null:
			continue
		if enemy.global_position.distance_to(origin) <= range:
			var health: Node = enemy.get_node_or_null("HealthComponent")
			if health != null:
				health.apply_damage(damage, attacker_peer_id)


## Server-only: drop a pickup at `drop_position`, replicated to every peer via
## the loot MultiplayerSpawner. Called by enemy.gd.on_died.
func spawn_loot_drop(drop_position: Vector3, item_id: StringName) -> void:
	if not NetworkMode.is_server():
		return
	_loot_spawner.spawn({
		"loot_index": _loot_counter,
		"item_id": item_id,
		"pos_x": drop_position.x,
		"pos_y": drop_position.y,
		"pos_z": drop_position.z,
	})
	_loot_counter += 1


## Returns the (cell_x, cell_z) grid coordinates of every walkable cell in the
## dungeon, where cell (cx, cz) covers world space x in [cx*CELL_SIZE -
## CELL_SIZE/2, cx*CELL_SIZE + CELL_SIZE/2] and likewise for z. This is the
## single source of truth for the dungeon's walkable footprint, mirroring the
## room/corridor placements in world.tscn.
static func _dungeon_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Entry Room (room-corner, 12x12) at grid origin.
	for cx in range(-1, 2):
		for cz in range(-1, 2):
			cells.append(Vector2i(cx, cz))
	# Corridor E1 -> Side Room A (room-small, 12x12).
	cells.append(Vector2i(2, 0))
	for cx in range(3, 6):
		for cz in range(-1, 2):
			cells.append(Vector2i(cx, cz))
	# Corridor S1 -> Hub -> Corridor E2 -> Side Room B (room-small, 12x12).
	cells.append(Vector2i(0, 2))
	cells.append(Vector2i(0, 3))
	cells.append(Vector2i(1, 3))
	for cx in range(2, 5):
		for cz in range(2, 5):
			cells.append(Vector2i(cx, cz))
	# Corridor S2 -> Boss Chamber (room-wide, 12x20).
	cells.append(Vector2i(0, 4))
	for cx in range(-1, 2):
		for cz in range(4, 9):
			cells.append(Vector2i(cx, cz))
	return cells


## Builds the navmesh as a union of 4x4 unit cells (see _dungeon_cells).
## Adjacent cells are deduplicated down to shared corner vertices, so every
## internal edge is a literal shared-index edge between two polygons and the
## NavigationServer connects them into one walkable mesh with no baking step
## (deterministic and headless-safe).
func _build_dungeon_navigation_mesh() -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var vertex_index := {}
	var half := CELL_SIZE / 2.0
	var polygons: Array[PackedInt32Array] = []

	for cell in _dungeon_cells():
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
