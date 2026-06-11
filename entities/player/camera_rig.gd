extends Node3D

## LOCAL-ONLY (owning client): a fixed-angle diagonal top-down boom camera
## (ARPG/Diablo-style) that smoothly follows this character. Never activated on
## the server (headless-safe) or for other players' characters — see
## player.gd._ready(), which calls set_active() only for the owning client.

const BOOM_OFFSET := Vector3(0.0, 12.0, 9.0)
const FOLLOW_LERP_SPEED := 6.0

# Per-physics-tick target movement above this is a teleport (death respawn,
# portal use), not normal locomotion (SPEED = 4.0 units/sec) — snap instantly
# instead of lerping, so the character doesn't sit out of frame for a beat.
const TELEPORT_DISTANCE := 1.0

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D
var _active: bool = false
var _last_target_position: Vector3


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
	# Translation only — rotation is fixed (set once in _snap_to_target), so
	# the camera never re-aims/turns while following the target.
	var target_position := _target.global_position
	if target_position.distance_to(_last_target_position) > TELEPORT_DISTANCE:
		_snap_to_target()
		return
	var desired := target_position + BOOM_OFFSET
	global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_LERP_SPEED * delta))
	_last_target_position = target_position


func _snap_to_target() -> void:
	if _target == null:
		return
	global_position = _target.global_position + BOOM_OFFSET
	look_at(_target.global_position, Vector3.UP)
	_last_target_position = _target.global_position
