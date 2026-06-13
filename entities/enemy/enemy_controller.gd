extends Node

## Server-authoritative AI for a single enemy. Mirrors player_controller.gd's
## "server walks the NavigationAgent3D path, replicated position/rotation does
## the rest" pattern, layered with a simple state machine:
##
##   IDLE   -> wait a random interval, watching for a player within aggro_radius
##   PATROL -> walk to a random nearby point, watching for a player
##   AGGRO  -> chase the nearest player within range; close to attack range
##   ATTACK -> stand and strike on a cooldown while the player stays in range
##
## Clients never run this (set_physics_process(false)); they only render the
## replicated position/rotation, exactly like player_controller.gd. Disabled
## entirely once the enemy dies (enemy.gd.on_died).

enum State { IDLE, PATROL, AGGRO, ATTACK }

const PATROL_RADIUS := 4.0
const IDLE_TIME_MIN := 2.0
const IDLE_TIME_MAX := 4.0
const ROTATION_SPEED := 10.0
const TARGET_UPDATE_DISTANCE := 0.5
const LEASH_MULTIPLIER := 1.5

var _body: CharacterBody3D
var _agent: NavigationAgent3D
var _stats: Node
var _status: Node
var _players_root: Node3D
var _rng := RandomNumberGenerator.new()

var _state: State = State.IDLE
var _state_timer: float = 0.0
var _home_position: Vector3
var _target_player: CharacterBody3D
var _attack_timer: float = 0.0


func _ready() -> void:
	_body = get_parent()
	_agent = _body.get_node("NavigationAgent3D")
	_stats = _body.get_node("StatsComponent")
	_status = _body.get_node_or_null("StatusEffectComponent")
	_home_position = _body.global_position
	_players_root = get_tree().root.find_child("Players", true, false)
	_rng.randomize()
	# Only the server runs AI; clients merely render the replicated result.
	set_physics_process(NetworkMode.is_server())


func _physics_process(delta: float) -> void:
	# Stunned: stand frozen (no movement, no attacks, no state transitions) —
	# the stun's expiry is ticked by the StatusEffectComponent itself.
	if _status != null and _status.is_stunned():
		_body.velocity = Vector3.ZERO
		_body.move_and_slide()
		return
	match _state:
		State.IDLE:
			_process_idle(delta)
		State.PATROL:
			_process_patrol(delta)
		State.AGGRO:
			_process_aggro(delta)
		State.ATTACK:
			_process_attack(delta)


func _process_idle(delta: float) -> void:
	_body.velocity = Vector3.ZERO
	_body.move_and_slide()
	var aggro_target := _find_nearest_player_within(_stats.aggro_radius)
	if aggro_target != null:
		_target_player = aggro_target
		_state = State.AGGRO
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf() * PATROL_RADIUS
		_agent.target_position = _home_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
		_state = State.PATROL


func _process_patrol(delta: float) -> void:
	var aggro_target := _find_nearest_player_within(_stats.aggro_radius)
	if aggro_target != null:
		_target_player = aggro_target
		_state = State.AGGRO
		return
	if _agent.is_navigation_finished():
		_body.velocity = Vector3.ZERO
		_body.move_and_slide()
		_state = State.IDLE
		_state_timer = _rng.randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
		return
	_move_towards(_agent.get_next_path_position(), delta)


func _process_aggro(delta: float) -> void:
	if not _is_player_valid(_target_player) \
			or _body.global_position.distance_to(_target_player.global_position) > _stats.aggro_radius * LEASH_MULTIPLIER:
		_target_player = null
		_state = State.IDLE
		_state_timer = 0.0
		return
	if _body.global_position.distance_to(_target_player.global_position) <= _stats.attack_range:
		_body.velocity = Vector3.ZERO
		_body.move_and_slide()
		_attack_timer = 0.0
		_state = State.ATTACK
		return
	if _agent.target_position.distance_to(_target_player.global_position) > TARGET_UPDATE_DISTANCE:
		_agent.target_position = _target_player.global_position
	_move_towards(_agent.get_next_path_position(), delta)


func _process_attack(delta: float) -> void:
	if not _is_player_valid(_target_player):
		_target_player = null
		_state = State.IDLE
		_state_timer = 0.0
		return
	if _body.global_position.distance_to(_target_player.global_position) > _stats.attack_range:
		_state = State.AGGRO
		return

	_face_towards(_target_player.global_position, delta)
	_body.velocity = Vector3.ZERO
	_body.move_and_slide()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = _stats.attack_interval
		_strike_target()
		_body.on_attack_performed.rpc()


## One landed melee hit on _target_player: full CombatSystem roll against the
## victim's gear armor, applied through stats_component.apply_damage (so the
## hit broadcasts to clients), plus this enemy's status proc if any.
func _strike_target() -> void:
	var target_stats: Node = _target_player.get_node_or_null("StatsComponent")
	if target_stats == null:
		return
	var target_equipment: Node = _target_player.get_node_or_null("EquipmentComponent")
	var armor: int = target_equipment.total_armor() if target_equipment != null else 0
	var hit := CombatSystem.compute_hit(_stats.attack_damage, 0, armor, _stats.crit_chance, _rng)
	target_stats.apply_damage(hit.amount, hit.is_crit)
	if _stats.inflict_status != &"" and _rng.randf() < _stats.inflict_status_chance:
		var target_status: Node = _target_player.get_node_or_null("StatusEffectComponent")
		if target_status != null:
			target_status.apply_effect(_stats.inflict_status, _stats.inflict_status_duration, _stats.inflict_status_magnitude)


func _move_towards(next_point: Vector3, delta: float) -> void:
	var direction := next_point - _body.global_position
	direction.y = 0.0
	if direction.length() > 0.05:
		direction = direction.normalized()
		var speed_mult: float = _status.speed_multiplier() if _status != null else 1.0
		_body.velocity = direction * _stats.move_speed * speed_mult
		_face_towards(_body.global_position + direction, delta)
	else:
		_body.velocity = Vector3.ZERO
	_body.move_and_slide()


func _face_towards(target_position: Vector3, delta: float) -> void:
	var direction := target_position - _body.global_position
	direction.y = 0.0
	if direction.length() <= 0.001:
		return
	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	_body.global_transform.basis = _body.global_transform.basis.slerp(target_basis, ROTATION_SPEED * delta)


func _find_nearest_player_within(radius: float) -> CharacterBody3D:
	var nearest: CharacterBody3D = null
	var nearest_dist := radius
	for child in _players_root.get_children():
		var player := child as CharacterBody3D
		if player == null:
			continue
		var stats: Node = player.get_node_or_null("StatsComponent")
		if stats != null and stats.hp <= 0:
			continue
		var dist := _body.global_position.distance_to(player.global_position)
		if dist <= nearest_dist:
			nearest = player
			nearest_dist = dist
	return nearest


## Untyped parameter: _target_player can be a reference to a freed node (e.g.
## a player who disconnected) by the time this runs, and passing a freed
## object to a CharacterBody3D-typed parameter raises a script error on the
## type check itself, before is_instance_valid() can even run.
func _is_player_valid(player) -> bool:
	if not is_instance_valid(player):
		return false
	var stats: Node = player.get_node_or_null("StatsComponent")
	return stats == null or stats.hp > 0
