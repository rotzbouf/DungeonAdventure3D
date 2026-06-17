extends Node3D

## Client-local destination indicator: spawned at the click point by
## player_input.gd, never replicated. Pulses out from a small scale then
## shrinks to zero so the ring is visible for ~0.45s before self-freeing.
func _ready() -> void:
	scale = Vector3.ONE * 0.2
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.33).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
