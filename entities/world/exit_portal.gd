extends Area3D

## Floor-completion portal in the Boss Chamber. Hidden and inert until the
## dragon dies (world.gd.activate_exit_portal, called from every peer's
## enemy.gd.on_died for is_boss enemies). Once activated, a player walking
## into this area triggers the "Floor Cleared!" overlay for that player only.


@onready var _particles: GPUParticles3D = $GPUParticles3D


func _ready() -> void:
	monitoring = false
	visible = false


func activate() -> void:
	visible = true
	_particles.emitting = true
	if NetworkMode.is_server():
		monitoring = true
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.name.begins_with("Player_"):
		return
	var peer_id := int(body.name.trim_prefix("Player_"))
	var dragon_def: EnemyDefinition = GameDatabase.enemies.get(&"dragon")
	var world := get_tree().root.find_child("World", true, false)
	world.on_floor_cleared.rpc_id(peer_id, dragon_def.xp_reward)
