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
signal floor_cleared(xp_reward: int)

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

## One entry per EnemySpawnPoints marker (matched by index): the starting
## roster for this floor — 4 skeleton warriors guarding the entry/hub, 3
## goblins in Side Room A, 2 zombies in the Hub, and the dragon boss in the
## Boss Chamber.
const INITIAL_ENEMY_SPAWNS: Array[StringName] = [
	&"skeleton_warrior", &"skeleton_warrior", &"skeleton_warrior", &"skeleton_warrior",
	&"goblin", &"goblin", &"goblin",
	&"zombie", &"zombie",
	&"dragon",
]

@onready var _navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var _town_navigation_region: NavigationRegion3D = $TownNavigationRegion3D
@onready var _players_root: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _enemies_root: Node3D = $Enemies
@onready var _enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var _enemy_spawn_points: Node3D = $EnemySpawnPoints
@onready var _loot_spawner: MultiplayerSpawner = $LootSpawner
@onready var _exit_portal: Area3D = $ExitPortal

var _loot_counter: int = 0


func _ready() -> void:
	_navigation_region.navigation_mesh = _build_dungeon_navigation_mesh()
	_town_navigation_region.navigation_mesh = _build_town_navigation_mesh()
	_build_floor_colliders()
	_build_wall_colliders()
	_build_town_floor_colliders()
	_build_town_wall_colliders()
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


## Server-only: place one enemy at each EnemySpawnPoints marker, per
## INITIAL_ENEMY_SPAWNS. Each spawn's `data` only carries the definition id +
## a sequential index — the same "primitives only, re-resolve from
## GameDatabase" shape as _spawn_player.
func _spawn_initial_enemies() -> void:
	var spawn_points := _enemy_spawn_points.get_children()
	for i in spawn_points.size():
		_enemy_spawner.spawn({"definition_id": INITIAL_ENEMY_SPAWNS[i], "spawn_index": i})


## Deterministic reconstruction from replicated data — see _spawn_player.
func _spawn_enemy(data: Dictionary) -> Node:
	var definition_id: StringName = data.definition_id
	var scene_path := DRAGON_SCENE if definition_id == &"dragon" else ENEMY_SCENE
	var enemy: CharacterBody3D = load(scene_path).instantiate()
	var spawn_index: int = int(data.spawn_index)
	enemy.definition_id = definition_id
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


## Server-side cone damage applied by dragon_controller.gd's fire-breath
## attack — every player within `range` of `origin` and within
## `cone_degrees / 2` of `forward` takes `damage` directly. Mirrors
## apply_area_hit's single-target damage application; player-death handling
## is out of scope here, matching that existing code.
func apply_cone_hit(origin: Vector3, forward: Vector3, range: float, cone_degrees: float, damage: int) -> void:
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
			stats.hp = maxi(0, stats.hp - damage)


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


## Called on every peer (from enemy.gd.on_died, broadcast) when the dragon
## boss dies — reveals the Boss Chamber's exit portal and (server-only)
## starts listening for a player walking into it.
func activate_exit_portal() -> void:
	_exit_portal.activate()


## Server -> the one player who walked into the activated ExitPortal
## (exit_portal.gd._on_body_entered). Bridges to the floor_cleared signal the
## HUD's floor-cleared overlay connects to.
@rpc("authority", "call_local", "reliable")
func on_floor_cleared(xp_reward: int) -> void:
	floor_cleared.emit(xp_reward)


## Returns the (cell_x, cell_z) grid coordinates of every walkable cell in the
## dungeon, where cell (cx, cz) covers world space x in [cx*CELL_SIZE -
## CELL_SIZE/2, cx*CELL_SIZE + CELL_SIZE/2] and likewise for z. This is the
## single source of truth for the dungeon's walkable footprint, mirroring the
## room/corridor placements in world.tscn.
static func _dungeon_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Entry Room (room-corner, 12x12) at grid origin. The room-corner mesh's
	# southwest corner cell (-1,-1) is a cut-away notch with no floor geometry
	# (the piece's namesake "corner" opening), so it's excluded here.
	for cx in range(-1, 2):
		for cz in range(-1, 2):
			if cx == -1 and cz == -1:
				continue
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
	# Corridor S2 (room-wide, 12x20) -> Boss Chamber. The room-wide piece is
	# rotated 90 degrees at z=28, so its 20-unit span covers world z in
	# [18, 38], i.e. cz in [5, 9] - one row further out than the corridor's
	# cz=4, not overlapping it (an off-by-one here previously duplicated cell
	# (0,4) and left both a phantom floor/navmesh strip beside the corridor at
	# cz=4 and a missing strip at the chamber's far wall, cz=9).
	cells.append(Vector2i(0, 4))
	for cx in range(-1, 2):
		for cz in range(5, 10):
			cells.append(Vector2i(cx, cz))
	return cells


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
		Rect2(Vector2(-42, 10), Vector2(4, 4)),     # Dungeon Gate alcove
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
	return _build_navigation_mesh_for_cells(_dungeon_cells())


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
	_build_floor_colliders_for_cells(_dungeon_cells(), "FloorColliders")


func _build_town_floor_colliders() -> void:
	_build_floor_colliders_for_cells(_town_cells(), "TownFloorColliders")


## Builds invisible wall colliders along every edge of `cells` that doesn't
## border another cell in the same set (i.e. the perimeter of the walkable
## footprint, including door-sized gaps like the dungeon's room-corner notch
## or the town's Dungeon Gate alcove opening). The imported Kenney meshes
## carry no collision shapes, so without this, CharacterBody3D.move_and_slide()
## has nothing to stop it sliding past a wall's visual mesh into the void on
## the other side - this keeps movement confined to exactly the area the
## navmesh/floor colliders cover, regardless of any visual mismatch with the
## hand-placed pieces. Shared by _build_wall_colliders and
## _build_town_wall_colliders.
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
	_build_wall_colliders_for_cells(_dungeon_cells(), "WallColliders")


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
