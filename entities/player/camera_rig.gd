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

# Camera shake (M15): decaying random offset applied to the Camera3D child's
# local position — NOT this rig's global position, so it can never fight the
# follow-lerp/teleport-snap logic above.
var _shake_strength: float = 0.0
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0


func _ready() -> void:
	_target = get_parent()
	# The rig is a child of the player body, which yaws toward its movement
	# direction (player_controller's slerp) — without top_level the rig
	# inherits that yaw and the "fixed-angle" camera silently turns with the
	# character (M15 fix; all positioning below is global, so nothing else
	# changes).
	top_level = true
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
	_apply_shake(delta)


## LOCAL-ONLY game feel: never replicated, never called on inactive rigs
## (the callers check the rig belongs to the local player first). Safe to
## call while inactive — _physics_process is off then, so it just no-ops.
func shake(strength := 0.15, duration := 0.2) -> void:
	_shake_strength = strength
	_shake_duration = duration
	_shake_time_left = duration


func _apply_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		if _camera.position != Vector3.ZERO:
			_camera.position = Vector3.ZERO
		return
	_shake_time_left = maxf(0.0, _shake_time_left - delta)
	var falloff := _shake_time_left / _shake_duration
	var amplitude := _shake_strength * falloff
	_camera.position = Vector3(
		randf_range(-amplitude, amplitude),
		randf_range(-amplitude, amplitude),
		0.0,
	)


func _snap_to_target() -> void:
	if _target == null:
		return
	global_position = _target.global_position + BOOM_OFFSET
	look_at(_target.global_position, Vector3.UP)
	_last_target_position = _target.global_position
