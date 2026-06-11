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
	var interactable := _find_interactable(result.collider)
	if interactable != null:
		interactable.interact(get_parent())
		return
	request_move_to.rpc_id(1, result.position)


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


@rpc("any_peer", "call_remote", "reliable")
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
