extends Node3D

## Purely cosmetic, client-side cone fire-breath burst spawned by
## dragon.gd.on_dragon_breath. Self-removes once the one-shot particle burst
## finishes. The server has already applied apply_cone_hit damage before this
## node exists.

const LIFETIME := 1.5

@onready var _particles: GPUParticles3D = $GPUParticles3D


func _ready() -> void:
	_particles.emitting = true
	_particles.finished.connect(_cleanup, CONNECT_ONE_SHOT)
	get_tree().create_timer(LIFETIME).timeout.connect(_cleanup)


func _cleanup() -> void:
	if not is_queued_for_deletion():
		queue_free()
