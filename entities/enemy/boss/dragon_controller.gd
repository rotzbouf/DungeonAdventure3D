extends "res://entities/enemy/enemy_controller.gd"

## Dragon boss AI: reuses the IDLE/PATROL/AGGRO/ATTACK state machine from
## enemy_controller.gd, adding a second phase (<= phase2_hp_ratio of max HP)
## in which the dragon also has a cone fire-breath attack usable from
## fire_breath_range, on its own cooldown.

var _health: Node
var _world: Node
var _breath_timer: float = 0.0


func _ready() -> void:
	super()
	_health = _body.get_node("HealthComponent")
	_world = get_tree().root.find_child("World", true, false)


func _is_phase2() -> bool:
	return _health.hp <= _health.max_hp * _stats.phase2_hp_ratio


func _engage_range() -> float:
	return maxf(_stats.attack_range, _stats.fire_breath_range if _is_phase2() else 0.0)


func _process_aggro(delta: float) -> void:
	if not _is_player_valid(_target_player) \
			or _body.global_position.distance_to(_target_player.global_position) > _stats.aggro_radius * LEASH_MULTIPLIER:
		_target_player = null
		_state = State.IDLE
		_state_timer = 0.0
		return
	if _body.global_position.distance_to(_target_player.global_position) <= _engage_range():
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
	if _body.global_position.distance_to(_target_player.global_position) > _engage_range():
		_state = State.AGGRO
		return

	_face_towards(_target_player.global_position, delta)
	_body.velocity = Vector3.ZERO
	_body.move_and_slide()

	_attack_timer -= delta
	_breath_timer -= delta
	var dist := _body.global_position.distance_to(_target_player.global_position)

	if dist <= _stats.attack_range:
		if _attack_timer <= 0.0:
			_attack_timer = ATTACK_COOLDOWN
			var target_stats: Node = _target_player.get_node_or_null("StatsComponent")
			if target_stats != null:
				var damage := CombatSystem.compute_damage(_stats.attack_damage)
				target_stats.hp = maxi(0, target_stats.hp - damage)
			_body.on_attack_performed.rpc()
	elif _is_phase2() and dist <= _stats.fire_breath_range and _breath_timer <= 0.0:
		_breath_timer = _stats.fire_breath_cooldown
		var forward := -_body.global_transform.basis.z
		_world.apply_cone_hit(_body.global_position, forward, _stats.fire_breath_range, _stats.fire_breath_cone_degrees, _stats.fire_breath_damage)
		_body.on_dragon_breath.rpc()
