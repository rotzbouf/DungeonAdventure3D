extends Node

## SERVER-AUTHORITATIVE movement. Owns the character's NavigationAgent3D and
## walks the computed path every physics frame. Receives destination requests
## from player_input.gd (already verified to come from the owning peer) and is
## the thing whose resulting position/rotation gets replicated to every client
## via MultiplayerSynchronizer. This node's multiplayer authority is always the
## server (1) — set by player.gd._ready().

const SPEED := 4.0
const ROTATION_SPEED := 10.0

## Normalized locomotion state in [0, 1] (0 = idle, 1 = walking at full SPEED).
## Computed here (server-authoritative) and replicated by player.gd alongside
## position/rotation; model_view.gd feeds it straight into the AnimationTree's
## blend parameter on every peer. Replicating this small derived value rather
## than raw animation frames or velocity keeps locomotion blending smooth and
## jitter-resilient over the network.
var move_blend: float = 0.0

var _body: CharacterBody3D
var _agent: NavigationAgent3D


func _ready() -> void:
	_body = get_parent()
	_agent = _body.get_node("NavigationAgent3D")
	# Only the server walks paths; clients merely render the replicated result.
	set_physics_process(NetworkMode.is_server())


func _physics_process(delta: float) -> void:
	if _agent.is_navigation_finished():
		_body.velocity = Vector3.ZERO
		_body.move_and_slide()
		move_blend = 0.0
		return

	var next_point := _agent.get_next_path_position()
	var direction := next_point - _body.global_position
	direction.y = 0.0
	if direction.length() > 0.05:
		direction = direction.normalized()
		_body.velocity = direction * SPEED
		var target_basis := Basis.looking_at(direction, Vector3.UP)
		_body.global_transform.basis = _body.global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)
	else:
		_body.velocity = Vector3.ZERO
	_body.move_and_slide()
	move_blend = clampf(_body.velocity.length() / SPEED, 0.0, 1.0)


## Entry point for validated move requests (called by player_input.gd's RPC
## handler after it confirms the sender owns this character).
func move_to(destination: Vector3) -> void:
	_agent.target_position = destination
