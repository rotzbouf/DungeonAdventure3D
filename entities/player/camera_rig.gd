extends Node3D

## LOCAL-ONLY (owning client): a fixed-angle diagonal top-down boom camera
## (ARPG/Diablo-style) that smoothly follows this character. Never activated on
## the server (headless-safe) or for other players' characters — see
## player.gd._ready(), which calls set_active() only for the owning client.

const BOOM_OFFSET := Vector3(0.0, 12.0, 9.0)
const FOLLOW_LERP_SPEED := 6.0

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D
var _active: bool = false


func _ready() -> void:
	_target = get_parent()
	_camera.current = false
	_snap_to_target()


func set_active(value: bool) -> void:
	_active = value
	_camera.current = value
	set_physics_process(value)
	if value:
		_snap_to_target()


func _physics_process(delta: float) -> void:
	var desired := _target.global_position + BOOM_OFFSET
	global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_LERP_SPEED * delta))
	look_at(_target.global_position, Vector3.UP)


func _snap_to_target() -> void:
	if _target == null:
		return
	global_position = _target.global_position + BOOM_OFFSET
	look_at(_target.global_position, Vector3.UP)
