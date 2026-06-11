extends Node3D

## Purely cosmetic, client-side bone/smoke particle burst spawned by
## enemy.gd.on_died on non-server peers. Self-removes once the one-shot
## particle burst finishes.

const LIFETIME := 1.5

@onready var _particles: GPUParticles3D = $GPUParticles3D


func _ready() -> void:
	_particles.emitting = true
	_particles.finished.connect(_cleanup, CONNECT_ONE_SHOT)
	get_tree().create_timer(LIFETIME).timeout.connect(_cleanup)


func _cleanup() -> void:
	if not is_queued_for_deletion():
		queue_free()
