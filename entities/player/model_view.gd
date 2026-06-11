extends Node3D

## Visual-only: instances the race's character model and blends its locomotion
## animation from the replicated Controller.move_blend value (a small float,
## not raw animation frames — jitter-resilient over the network, see
## player_controller.gd). Never runs on a dedicated server: it's headless and
## is a spectator of no one. A listen-host process IS also a client (it
## renders itself and every other player), so this still runs there.
##
## Race is whatever the player chose at character creation (player.gd.race_id,
## set deterministically by world.gd._spawn_player on every peer) — looked up
## in GameDatabase.races so "new race = new .tres", not new code.

## Both currently-converted rigs (Elf, Dark Elf) share the same source scale
## and clip names (idle / "Walk-sexy - fixed"); a per-race RaceModel.model_scale
## field would be speculative until a race actually needs a different value.
## The source rig is authored at roughly 8x the size we use for gameplay
## (placeholder capsule height = 1.8m); this scale brings the model's feet-to
## -head height to match it so collision/camera/movement tuning lines up.
const MODEL_SCALE := 0.227

const IDLE_ANIMATION := &"idle"
const WALK_ANIMATION := &"Walk-sexy - fixed"
const BLEND_PARAM := "parameters/locomotion/blend_amount"
const MOVE_BLEND_THRESHOLD := 0.1
const FOOTSTEP_INTERVAL := 0.4

@onready var _controller: Node = get_parent().get_node("Controller")
@onready var _race_id: StringName = get_parent().race_id

var _animation_tree: AnimationTree
var _footstep_timer := 0.0


func _ready() -> void:
	if NetworkMode.is_dedicated_server():
		return
	var race: RaceModel = GameDatabase.races.get(_race_id)
	var visual_scene: PackedScene = race.visual_scene if race != null else null
	if visual_scene == null:
		push_error("model_view: no RaceModel found for race_id %s" % _race_id)
		return
	scale = Vector3.ONE * MODEL_SCALE
	var visual := visual_scene.instantiate()
	add_child(visual)
	# The source rig's rest pose faces +Z, but player_controller.gd's
	# Basis.looking_at(direction, UP) points the body's -Z at the movement
	# direction (the convention apply_cone_hit/dragon.gd's "forward" also
	# use) — without this flip the model walks/faces backwards.
	visual.rotation.y = PI

	_animation_tree = AnimationTree.new()
	_animation_tree.name = "AnimationTree"
	add_child(_animation_tree)
	_animation_tree.anim_player = _animation_tree.get_path_to(visual.get_node("AnimationPlayer"))
	_animation_tree.tree_root = _build_locomotion_tree()
	_animation_tree.active = true


func _process(delta: float) -> void:
	if _animation_tree != null:
		_animation_tree[BLEND_PARAM] = _controller.move_blend

	if _controller.move_blend > MOVE_BLEND_THRESHOLD:
		_footstep_timer += delta
		if _footstep_timer >= FOOTSTEP_INTERVAL:
			_footstep_timer -= FOOTSTEP_INTERVAL
			AudioManager.play_sfx(&"footstep_stone")
	else:
		_footstep_timer = 0.0


func _build_locomotion_tree() -> AnimationNodeBlendTree:
	var idle := AnimationNodeAnimation.new()
	idle.animation = IDLE_ANIMATION
	var walk := AnimationNodeAnimation.new()
	walk.animation = WALK_ANIMATION
	var locomotion := AnimationNodeBlend2.new()

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node(&"idle", idle)
	tree_root.add_node(&"walk", walk)
	tree_root.add_node(&"locomotion", locomotion)
	tree_root.connect_node(&"locomotion", 0, &"idle")
	tree_root.connect_node(&"locomotion", 1, &"walk")
	tree_root.connect_node(&"output", 0, &"locomotion")
	return tree_root
