extends Node

## Drives the AnimationPlayer (if any) found inside an enemy's instantiated
## visual scene. Visuals without an AnimationPlayer (e.g. the skeleton
## placeholder) make every method below a safe no-op.

const IDLE_ANIM := &"idle"
const WALK_ANIM := &"walk"
const ATTACK_ANIM := &"attack"
const DEATH_ANIM := &"death"
const MOVE_THRESHOLD := 0.001

var _body: Node3D
var _anim_player: AnimationPlayer
var _last_position: Vector3
var _one_shot: bool = false


func setup(visual_root: Node3D) -> void:
	_body = get_parent()
	_last_position = _body.global_position
	_anim_player = _find_animation_player(visual_root)
	if _anim_player != null:
		for clip in [IDLE_ANIM, WALK_ANIM]:
			if _anim_player.has_animation(clip):
				_anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim_player.animation_finished.connect(_on_animation_finished)
	# A dedicated server has no renderer; only clients (including a
	# listen-host's own view) need to drive playback.
	set_process(NetworkMode.is_client())


func _process(_delta: float) -> void:
	if _anim_player == null or _one_shot:
		return
	var moved := _body.global_position.distance_to(_last_position) > MOVE_THRESHOLD
	_last_position = _body.global_position
	var clip := WALK_ANIM if moved else IDLE_ANIM
	if _anim_player.has_animation(clip) and _anim_player.current_animation != clip:
		_anim_player.play(clip)


## One-shot melee/breath clip; _on_animation_finished returns to idle/walk.
func play_attack() -> void:
	if _anim_player == null or not _anim_player.has_animation(ATTACK_ANIM):
		return
	_one_shot = true
	_anim_player.play(ATTACK_ANIM)


## Returns whether a "death" clip exists and was started; callers fall back
## to a cosmetic tween (_play_death_visual) when this returns false.
func play_death() -> bool:
	if _anim_player == null or not _anim_player.has_animation(DEATH_ANIM):
		return false
	_one_shot = true
	_anim_player.play(DEATH_ANIM)
	return true


func _on_animation_finished(_anim_name: StringName) -> void:
	_one_shot = false


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
