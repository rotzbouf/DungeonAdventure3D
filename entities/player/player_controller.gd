extends Node

## SERVER-AUTHORITATIVE movement. Owns the character's NavigationAgent3D and
## walks the computed path every physics frame. Receives destination requests
## from player_input.gd (already verified to come from the owning peer) and is
## the thing whose resulting position/rotation gets replicated to every client
## via MultiplayerSynchronizer. This node's multiplayer authority is always the
## server (1) — set by player.gd._ready().

const SPEED := 4.0
const ROTATION_SPEED := 10.0
const STUCK_VELOCITY_MIN := 0.5   # m/s — below this we're already stopping
const STUCK_MOVE_MIN    := 0.01   # m   — less than this counts as no progress
const STUCK_TIME_MAX    := 0.4    # s   — cancel nav after being stuck this long

## Normalized locomotion state in [0, 1] (0 = idle, 1 = walking at full SPEED).
## Computed here (server-authoritative) and replicated by player.gd alongside
## position/rotation; model_view.gd feeds it straight into the AnimationTree's
## blend parameter on every peer. Replicating this small derived value rather
## than raw animation frames or velocity keeps locomotion blending smooth and
## jitter-resilient over the network.
var move_blend: float = 0.0

var _body: CharacterBody3D
var _agent: NavigationAgent3D
var _stats: Node
var _status: Node
var _equipment: Node
var _rng := RandomNumberGenerator.new()

## Basic-attack state (M15): the enemy body this character is pursuing, or
## null. Untyped on purpose — enemies queue_free 0.6s after death, and a
## CharacterBody3D-typed var holding a freed node errors on the type check
## itself before is_instance_valid can run (same idiom as
## enemy_controller._is_player_valid).
var _attack_target = null
var _attack_timer: float = 0.0
var _stuck_timer: float = 0.0


func _ready() -> void:
	_body = get_parent()
	_agent = _body.get_node("NavigationAgent3D")
	_stats = _body.get_node("StatsComponent")
	_status = _body.get_node_or_null("StatusEffectComponent")
	_equipment = _body.get_node("EquipmentComponent")
	_rng.randomize()
	# Only the server walks paths; clients merely render the replicated result.
	set_physics_process(NetworkMode.is_server())


func _physics_process(delta: float) -> void:
	if _stats.hp <= 0 or (_status != null and _status.is_stunned()):
		_body.velocity = Vector3.ZERO
		_body.move_and_slide()
		move_blend = 0.0
		return

	if _attack_target != null:
		if not _is_target_attackable(_attack_target):
			_attack_target = null
		else:
			_process_attack_target(delta)
			return

	if _agent.is_navigation_finished():
		_body.velocity = Vector3.ZERO
		_body.move_and_slide()
		move_blend = 0.0
		return

	_walk_path(delta)


## Walks one physics frame toward the agent's next path point (shared by
## free movement and attack-target pursuit).
func _walk_path(delta: float) -> void:
	var next_point := _agent.get_next_path_position()
	var direction := next_point - _body.global_position
	direction.y = 0.0
	if direction.length() > 0.05:
		direction = direction.normalized()
		var speed_mult: float = _status.speed_multiplier() if _status != null else 1.0
		_body.velocity = direction * SPEED * speed_mult
		var target_basis := Basis.looking_at(direction, Vector3.UP)
		_body.global_transform.basis = _body.global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)
	else:
		_body.velocity = Vector3.ZERO
	var pre_speed := _body.velocity.length()
	var before_pos := _body.global_position
	_body.move_and_slide()
	move_blend = clampf(_body.velocity.length() / SPEED, 0.0, 1.0)
	# Stuck detection: velocity was set but the slide produced no movement.
	if pre_speed > STUCK_VELOCITY_MIN \
			and before_pos.distance_to(_body.global_position) < STUCK_MOVE_MIN:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME_MAX:
			_agent.target_position = _body.global_position
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0


## Miniature of enemy_controller's AGGRO->ATTACK: outside weapon range chase
## the target, inside it stand, face it, and swing on the weapon's interval.
func _process_attack_target(delta: float) -> void:
	var target: CharacterBody3D = _attack_target
	var weapon_range: float = _equipment.weapon_attack_range()
	if _body.global_position.distance_to(target.global_position) > weapon_range:
		if _agent.target_position.distance_to(target.global_position) > 0.5:
			_agent.target_position = target.global_position
		if _agent.is_navigation_finished():
			_body.velocity = Vector3.ZERO
			_body.move_and_slide()
			move_blend = 0.0
			return
		_walk_path(delta)
		return

	_face_towards(target.global_position, delta)
	_body.velocity = Vector3.ZERO
	_body.move_and_slide()
	move_blend = 0.0

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = _equipment.weapon_attack_interval()
		var health: Node = target.get_node_or_null("HealthComponent")
		var enemy_stats: Node = target.get_node_or_null("StatsComponent")
		if health != null:
			var armor: int = enemy_stats.armor if enemy_stats != null else 0
			var hit := CombatSystem.compute_hit(_equipment.weapon_attack_damage(), 0,
					armor, _equipment.total_crit_chance(), _rng)
			health.apply_damage(hit.amount, _body.owning_peer_id(), hit.is_crit)
		_body.on_attack_performed.rpc()


func _face_towards(target_position: Vector3, delta: float) -> void:
	var direction := target_position - _body.global_position
	direction.y = 0.0
	if direction.length() <= 0.001:
		return
	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	_body.global_transform.basis = _body.global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)


## Untyped for the same freed-node reason as _attack_target above.
func _is_target_attackable(target) -> bool:
	if not is_instance_valid(target):
		return false
	var health: Node = target.get_node_or_null("HealthComponent")
	return health != null and health.hp > 0


## Entry point for validated attack requests (player_input.gd's
## request_attack_target RPC handler). Swing immediately on arrival.
func attack_target(enemy: CharacterBody3D) -> void:
	if _stats.hp <= 0:
		return
	_attack_target = enemy
	_attack_timer = 0.0


## Entry point for validated move requests (called by player_input.gd's RPC
## handler after it confirms the sender owns this character). Clicking the
## ground disengages any attack target.
func move_to(destination: Vector3) -> void:
	if _stats.hp <= 0:
		return
	_attack_target = null
	var map := _agent.get_navigation_map()
	var snapped := NavigationServer3D.map_get_closest_point(map, destination)
	_agent.target_position = snapped
	if OS.has_environment("DEBUG_CLICK"):
		print("[MOVE] dest_raw=%s dest_snapped=%s delta=%.3f" % [
			str(destination), str(snapped), destination.distance_to(snapped)])


## Called by player.gd on respawn: teleports the body to `position` and
## clears any in-flight pathfinding so the character stands idle there
## instead of immediately walking back toward its pre-death destination.
func reset_to(position: Vector3) -> void:
	_body.global_position = position
	_body.velocity = Vector3.ZERO
	_agent.target_position = position
	_attack_target = null
