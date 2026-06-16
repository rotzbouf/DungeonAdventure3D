extends Area3D

## Floor-completion portal in the Boss Chamber. Hidden and inert until the
## dragon dies (world.gd.activate_exit_portal, called on every peer from
## enemy.gd.on_died for is_boss enemies). Once activated, the first player
## to walk in triggers floor_cleared for that player and advances the floor.


@onready var _particles: GPUParticles3D = $GPUParticles3D

var _triggered := false


func _ready() -> void:
	monitoring = false
	visible = false


func activate() -> void:
	visible = true
	_particles.emitting = true
	if NetworkMode.is_server():
		monitoring = true
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)


## Called by world._rebuild_dungeon on every floor (including floor 1) to
## reset portal state before the new dragon has spawned.
func deactivate() -> void:
	_triggered = false
	visible = false
	_particles.emitting = false
	if NetworkMode.is_server():
		monitoring = false
		if body_entered.is_connected(_on_body_entered):
			body_entered.disconnect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if not body.name.begins_with("Player_"):
		return
	_triggered = true
	monitoring = false
	var peer_id := int(body.name.trim_prefix("Player_"))
	var dragon_def: EnemyDefinition = GameDatabase.enemies.get(&"dragon")
	var world := get_tree().root.find_child("World", true, false)
	world.on_floor_cleared.rpc_id(peer_id, dragon_def.xp_reward, world._current_floor + 1)
	world._advance_floor()
