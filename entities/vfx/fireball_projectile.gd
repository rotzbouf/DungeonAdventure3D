extends Node3D

## Purely cosmetic, client-side VFX spawned by spellbook_component.gd when a
## player casts a spell whose `Spell.projectile_vfx` is set (currently only
## Fireball). Travels in a straight line toward `target_position`, then plays
## an impact particle burst and frees itself. Never server-authoritative —
## the server already resolved the damage via apply_area_hit before this
## node exists.

const SPEED := 12.0
const ARRIVAL_DISTANCE := 0.4
const IMPACT_LIFETIME := 1.0

var target_position: Vector3 = Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $OmniLight3D
@onready var _trail: GPUParticles3D = $Trail
@onready var _impact: GPUParticles3D = $Impact

var _exploded := false


func _process(delta: float) -> void:
	if _exploded:
		return
	var to_target := target_position - global_position
	var dist := to_target.length()
	if dist <= ARRIVAL_DISTANCE:
		_explode()
		return
	global_position += to_target.normalized() * minf(SPEED * delta, dist)


func _explode() -> void:
	_exploded = true
	_mesh.visible = false
	_light.visible = false
	_trail.emitting = false
	_impact.emitting = true
	_impact.finished.connect(_cleanup, CONNECT_ONE_SHOT)
	get_tree().create_timer(IMPACT_LIFETIME).timeout.connect(_cleanup)


func _cleanup() -> void:
	if not is_queued_for_deletion():
		queue_free()
