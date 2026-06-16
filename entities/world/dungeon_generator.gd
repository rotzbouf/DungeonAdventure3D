class_name DungeonGenerator

## Pure static dungeon generator — no scene tree access, no network awareness.
## DungeonGenerator.generate(floor_num, dungeon_seed) → {layout: Array, enemy_spawns: Array}
##
## Layout entries share the same shape as world.gd's DUNGEON_LAYOUT so that
## _instantiate_dungeon_pieces / _cells_from_layout / _build_*_colliders need
## no changes beyond swapping the constant for the instance variable.
##
## RNG is local and seeded from (dungeon_seed, floor_num) so every peer with
## the same two values produces an identical layout — pure determinism.

const CELL_SIZE := 4.0

const ROOM_CORNER_SCENE  := preload("res://entities/dungeon/kenney/room-corner.glb")
const CORRIDOR_SCENE     := preload("res://entities/dungeon/kenney/corridor.glb")
const ROOM_SMALL_SCENE   := preload("res://entities/dungeon/kenney/room-small.glb")
const ROOM_WIDE_SCENE    := preload("res://entities/dungeon/kenney/room-wide.glb")

# Local cell footprints before rotation — matches world.gd's PIECE_FOOTPRINTS.
const PIECE_FOOTPRINTS := {
	"corridor": {"cells": [Vector2i(0, 0)]},
	"room_small": {"cells": [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0), Vector2i(0,  0), Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
	]},
	"room_wide": {"cells": [
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1),
		Vector2i(-2,  0), Vector2i(-1,  0), Vector2i(0,  0), Vector2i(1,  0), Vector2i(2,  0),
		Vector2i(-2,  1), Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1), Vector2i(2,  1),
	]},
	"room_corner": {
		"cells": [
			Vector2i( 0, -1), Vector2i(1, -1),
			Vector2i(-1,  0), Vector2i(0,  0), Vector2i(1, 0),
			Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1, 1),
		],
		"notches": [Vector2i(-1, -1)],
	},
}


static func _rotate_cell(cell: Vector2i, rot: int) -> Vector2i:
	match rot:
		1: return Vector2i(-cell.y,  cell.x)
		2: return Vector2i(-cell.x, -cell.y)
		3: return Vector2i( cell.y, -cell.x)
		_: return cell


## Returns all world-space cells occupied by `entry` (for overlap detection).
static func _occupied_cells(entry: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var footprint: Dictionary = PIECE_FOOTPRINTS[entry["piece"]]
	var notches: Array = footprint.get("notches", [])
	for local_cell: Vector2i in footprint["cells"]:
		if local_cell in notches:
			continue
		result.append(_rotate_cell(local_cell, entry["rot"]) + entry["center"])
	return result


static func _can_place(entry: Dictionary, occupied: Dictionary) -> bool:
	for cell in _occupied_cells(entry):
		if occupied.has(cell):
			return false
	return true


static func _mark(entry: Dictionary, occupied: Dictionary) -> void:
	for cell in _occupied_cells(entry):
		occupied[cell] = true


## Fisher-Yates shuffle using `rng`.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp


static func generate(floor_num: int, dungeon_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dungeon_seed ^ floor_num * 1_000_003)

	var layout: Array = []
	var occupied: Dictionary = {}

	# ── Phase 1: Entry room (always fixed at origin) ─────────────────────────
	var entry_room := {
		"name": "EntryRoom",
		"scene": ROOM_CORNER_SCENE,
		"piece": "room_corner",
		"center": Vector2i(0, 0),
		"rot": 2,
		"role": &"entry",
	}
	layout.append(entry_room)
	_mark(entry_room, occupied)

	# ── Phase 2: Side rooms ───────────────────────────────────────────────────
	# Number of side rooms scales with floor (floor 1 → 2, max 5 at floor 4+).
	var side_room_target := 2 + clampi(floor_num - 1, 0, 3)
	var frontier: Array[Vector2i] = [Vector2i(0, 0)]
	var side_room_centers: Array[Vector2i] = []
	var corridor_index := 0
	var attempts := 0

	# Directions: (1,0)=east, (0,1)=south, (-1,0)=west, (0,-1)=north.
	# Bias south first so the dungeon tends to grow downward where the boss
	# chamber can always be placed without running into the entry room.
	var directions: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

	while side_room_centers.size() < side_room_target and attempts < 80:
		attempts += 1
		var base: Vector2i = frontier[rng.randi() % frontier.size()]
		_shuffle(directions, rng)
		# Ensure south is tried first half the time for the downward bias.
		if rng.randi() % 2 == 0:
			directions.erase(Vector2i(0, 1))
			directions.push_front(Vector2i(0, 1))

		for dir: Vector2i in directions:
			# Rooms have radius 1; corridor sits 2 cells out, room 4 cells out.
			var corr_center := base + dir * 2
			var room_center := base + dir * 4
			var corr_rot    := 0 if dir.x != 0 else 3
			var room_rot    := rng.randi() % 4

			var corr_entry := {
				"name": "Corridor_%d" % corridor_index,
				"scene": CORRIDOR_SCENE,
				"piece": "corridor",
				"center": corr_center,
				"rot": corr_rot,
			}
			var room_entry := {
				"name": "SideRoom_%d" % side_room_centers.size(),
				"scene": ROOM_SMALL_SCENE,
				"piece": "room_small",
				"center": room_center,
				"rot": room_rot,
				"role": &"side",
			}

			if not _can_place(corr_entry, occupied) or not _can_place(room_entry, occupied):
				continue

			layout.append(corr_entry)
			layout.append(room_entry)
			_mark(corr_entry, occupied)
			_mark(room_entry, occupied)
			frontier.append(room_center)
			side_room_centers.append(room_center)
			corridor_index += 1
			break  # placed one room this iteration; try again from frontier

	# ── Phase 3: Boss chamber south of deepest side room ─────────────────────
	# "Deepest" = largest Z (south); tiebreak by largest X (easternmost).
	var boss_origin := Vector2i(0, 0)  # fallback to entry room origin
	for sc: Vector2i in side_room_centers:
		if sc.y > boss_origin.y or (sc.y == boss_origin.y and sc.x > boss_origin.x):
			boss_origin = sc

	# Try south first; if blocked keep shifting south 1 cell until clear.
	# In practice the gap from the side room's south edge means this nearly
	# never needs more than one attempt.
	var boss_corr_center := boss_origin + Vector2i(0, 2)
	var boss_room_center := boss_origin + Vector2i(0, 5)

	for _i in 8:
		var boss_corr := {
			"name": "BossCorridor",
			"scene": CORRIDOR_SCENE,
			"piece": "corridor",
			"center": boss_corr_center,
			"rot": 3,
		}
		var boss_room := {
			"name": "BossChamber",
			"scene": ROOM_WIDE_SCENE,
			"piece": "room_wide",
			"center": boss_room_center,
			"rot": 3,
			"role": &"boss",
		}
		if _can_place(boss_corr, occupied) and _can_place(boss_room, occupied):
			layout.append(boss_corr)
			layout.append(boss_room)
			_mark(boss_corr, occupied)
			_mark(boss_room, occupied)
			break
		boss_corr_center += Vector2i(0, 1)
		boss_room_center += Vector2i(0, 1)

	# ── Enemy spawns ──────────────────────────────────────────────────────────
	var enemy_spawns: Array = []

	# Entry room guard.
	enemy_spawns.append({"definition_id": &"skeleton_warrior", "pos_x": 2.0, "pos_z": 2.0})

	# Side room occupants: random from the three non-boss enemies.
	var roster: Array[StringName] = [&"goblin", &"zombie", &"skeleton_warrior"]
	for i: int in side_room_centers.size():
		var sc := side_room_centers[i]
		var def_id: StringName = roster[rng.randi() % roster.size()]
		enemy_spawns.append({
			"definition_id": def_id,
			"pos_x": float(sc.x) * CELL_SIZE,
			"pos_z": float(sc.y) * CELL_SIZE,
		})
		if floor_num >= 3:
			enemy_spawns.append({
				"definition_id": def_id,
				"pos_x": float(sc.x) * CELL_SIZE + 1.5,
				"pos_z": float(sc.y) * CELL_SIZE + 1.5,
			})

	# Dragon in the boss chamber.
	enemy_spawns.append({
		"definition_id": &"dragon",
		"pos_x": float(boss_room_center.x) * CELL_SIZE,
		"pos_z": float(boss_room_center.y) * CELL_SIZE,
	})

	return {"layout": layout, "enemy_spawns": enemy_spawns}
