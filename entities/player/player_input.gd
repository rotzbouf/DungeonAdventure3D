extends Node

## LOCAL-ONLY: active only on the owning client (never on the server, never for
## other players' characters — see player.gd._ready()). Raycasts mouse clicks
## against the level's static geometry and ships the resulting destination
## point to the server: a small, infrequent, discrete intent message — exactly
## what reliable RPC is good at, unlike a continuous per-frame direction vector.
##
## request_move_to is declared on THIS node so Godot can route the call to the
## same node path on the server. There, the very same function acts as the
## server-side entry point of the universal pattern: verify sender owns this
## character, then delegate to the authoritative controller.

const RAY_LENGTH := 1000.0

var _active: bool = false


func set_active(value: bool) -> void:
	_active = value
	set_process_unhandled_input(value)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)


func _handle_click(screen_position: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RAY_LENGTH)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	if OS.has_environment("DEBUG_CLICK"):
		print("[CLICK] screen=%s world=%s collider=%s" % [str(screen_position), str(result.position), result.collider.name])
	var interactable := _find_interactable(result.collider)
	if interactable != null:
		interactable.interact(get_parent())
		return
	var enemy := _find_enemy(result.collider)
	if enemy != null:
		# Cross-peer currency is the node NAME (Enemy_<n>), never a node
		# reference — same convention as Player_<peer_id> everywhere else.
		request_attack_target.rpc_id(1, enemy.name)
		return
	# Wall clicks project onto the y=0 floor plane so the server-side navmesh
	# snap in move_to() gets a reasonable destination instead of a y>0 wall face.
	var destination: Vector3
	if _is_wall_collider(result.collider):
		destination = _ray_y0_intersection(from, direction)
	else:
		destination = result.position
	request_move_to.rpc_id(1, destination)


func _is_wall_collider(collider: Node) -> bool:
	var p := collider.get_parent()
	return p != null and (p.name == "WallColliders" or p.name == "TownWallColliders")


## Intersects the camera ray with the y=0 ground plane.
func _ray_y0_intersection(from: Vector3, direction: Vector3) -> Vector3:
	if abs(direction.y) < 0.001:
		return from  # near-horizontal ray — use ray origin as fallback
	return from + direction * (-from.y / direction.y)


## Returns the clicked enemy body (the CharacterBody3D living under the
## world's Enemies root) at or above `node`, or null. Walks up because the
## ray may hit the enemy's CollisionShape3D-owning body directly or a child.
func _find_enemy(node: Node) -> Node:
	var current := node
	while current != null:
		if current is CharacterBody3D and current.get_parent() != null \
				and current.get_parent().name == "Enemies":
			return current
		current = current.get_parent()
	return null


## Returns the interactable node at or above `node` (self or parent), or null.
func _find_interactable(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("interact"):
		return node
	var parent := node.get_parent()
	if parent != null and parent.has_method("interact"):
		return parent
	return null


@rpc("any_peer", "call_local", "reliable")
func request_move_to(destination: Vector3) -> void:
	if not NetworkMode.is_server():
		return
	# 1. verify sender owns this character
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		push_warning("player_input: rejected move request from non-owning peer %d" % multiplayer.get_remote_sender_id())
		return
	# 2-3. validation here is trivial (any point is walkable on this test arena);
	#      a real level would re-check the destination against nav-mesh bounds.
	#      4. replication is implicit: the controller mutates authoritative
	#      position, MultiplayerSynchronizer carries the result to every peer.
	get_parent().get_node("Controller").move_to(destination)


## Client -> server: "attack this enemy" (M15 basic attack). Same routing and
## sender-verification shape as request_move_to above; the controller then
## owns the pursue-and-swing loop server-side.
@rpc("any_peer", "call_local", "reliable")
func request_attack_target(enemy_name: StringName) -> void:
	if not NetworkMode.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		push_warning("player_input: rejected attack request from non-owning peer %d" % multiplayer.get_remote_sender_id())
		return
	var enemies_root := get_tree().root.find_child("Enemies", true, false)
	if enemies_root == null:
		return
	var enemy := enemies_root.get_node_or_null(String(enemy_name))
	if enemy == null:
		return
	get_parent().get_node("Controller").attack_target(enemy)
