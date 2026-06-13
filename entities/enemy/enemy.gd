extends CharacterBody3D

## Orchestrator for a networked enemy. Mirrors player.gd's split: the body and
## its Controller (AI) are server-authoritative (authority = 1); clients only
## render the replicated position/rotation/hp. Spawned (and named
## "Enemy_<spawn_index>") by the world's enemy MultiplayerSpawner.

## Set by world.gd._spawn_enemy on the freshly instantiated node, BEFORE it
## enters the tree — same deterministic-reconstruction pattern as
## player.gd.race_id/class_id (re-resolved from GameDatabase by id, never
## passed directly through spawn data).
var definition_id: StringName

const DeathBurstScene := preload("res://entities/vfx/death_burst.tscn")

@onready var _controller: Node = $Controller
@onready var _health: Node = $HealthComponent
@onready var _stats: Node = $StatsComponent
@onready var _model: Node3D = $Model
@onready var _animator: Node = $Animator


func _enter_tree() -> void:
	set_multiplayer_authority(1)
	# Must happen before MultiplayerSynchronizer's own _enter_tree/_ready —
	# see lesson 2 in lessons_multiplayer_replication.md.
	_setup_replication(get_node("MultiplayerSynchronizer"))


func _ready() -> void:
	_controller.set_multiplayer_authority(1)

	var def: EnemyDefinition = GameDatabase.enemies.get(definition_id)
	if def == null:
		return
	_health.initialize(def)
	_stats.initialize(def)
	_health.died.connect(_on_health_depleted)
	_health.hit.connect(_on_health_hit)

	if def.visual_scene != null:
		var visual := def.visual_scene.instantiate() as Node3D
		_model.add_child(visual)
		_animator.setup(visual)


func _on_health_depleted() -> void:
	if NetworkMode.is_server():
		on_died.rpc()


func _on_health_hit(amount: int, is_crit: bool, damage_type: StringName, attacker_peer_id: int) -> void:
	if NetworkMode.is_server():
		on_enemy_hit.rpc(amount, is_crit, damage_type, attacker_peer_id)


## Broadcast (call_local) so every peer plays a hit flash and floating damage
## number; purely cosmetic, the server has already applied (and rolled) the
## damage. attacker_peer_id lets the one peer who dealt a crit shake its own
## camera — everyone else ignores it.
@rpc("authority", "call_local", "reliable")
func on_enemy_hit(amount: int, is_crit: bool, damage_type: StringName, attacker_peer_id: int) -> void:
	if NetworkMode.is_dedicated_server():
		return
	HitFlash.flash(_model)
	var world := get_tree().root.find_child("World", true, false)
	DamageNumber.spawn(world, global_position, amount, is_crit, damage_type)
	if is_crit and attacker_peer_id == multiplayer.get_unique_id():
		var players_root := get_tree().root.find_child("Players", true, false)
		var attacker := players_root.get_node_or_null("Player_%d" % attacker_peer_id) if players_root != null else null
		if attacker != null:
			attacker.get_node("CameraRig").shake(0.1, 0.15)


## Broadcast (call_local) so every peer plays the attack/breath animation;
## purely cosmetic, the server has already applied any resulting damage.
@rpc("authority", "call_local", "reliable")
func on_attack_performed() -> void:
	_animator.play_attack()


## Broadcast (call_local) so every peer plays the death animation/visual; the
## server additionally awards XP, drops loot, and removes the node shortly
## after — which MultiplayerSpawner replicates as a despawn to every client.
@rpc("authority", "call_local", "reliable")
func on_died() -> void:
	_controller.set_physics_process(false)
	var def: EnemyDefinition = GameDatabase.enemies.get(definition_id)
	if not _animator.play_death():
		_play_death_visual()
	if NetworkMode.is_client():
		AudioManager.play_sfx(&"enemy_death")
		_spawn_death_burst()
	if def != null and def.is_boss:
		var world := get_tree().root.find_child("World", true, false)
		world.activate_exit_portal()
	if NetworkMode.is_server():
		if def != null:
			_award_kill_xp(def.xp_reward)
			if def.loot_item_id != &"":
				var world := get_tree().root.find_child("World", true, false)
				world.spawn_loot_drop(global_position, def.loot_item_id)
		get_tree().create_timer(0.6).timeout.connect(queue_free)


func _award_kill_xp(xp_reward: int) -> void:
	var attacker_peer_id: int = _health.last_attacker_peer_id
	if attacker_peer_id < 0:
		return
	var players_root := get_tree().root.find_child("Players", true, false)
	var player := players_root.get_node_or_null("Player_%d" % attacker_peer_id)
	if player == null:
		return
	var level_comp: Node = player.get_node_or_null("LevelComponent")
	if level_comp != null:
		level_comp.gain_xp(xp_reward)


func _play_death_visual() -> void:
	if _model.get_child_count() == 0:
		return
	var visual: Node3D = _model.get_child(0)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ZERO, 0.6)
	tween.parallel().tween_property(visual, "position:y", -1.0, 0.6)


func _spawn_death_burst() -> void:
	var world := get_tree().root.find_child("World", true, false)
	if world == null:
		return
	var burst := DeathBurstScene.instantiate()
	world.add_child(burst)
	burst.global_position = global_position


func _setup_replication(synchronizer: MultiplayerSynchronizer) -> void:
	var config := SceneReplicationConfig.new()
	for prop_path in [NodePath(".:position"), NodePath(".:rotation")]:
		config.add_property(prop_path)
		config.property_set_spawn(prop_path, true)
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	var on_change_paths := [
		NodePath("HealthComponent:hp"),
		NodePath("HealthComponent:max_hp"),
		NodePath("StatusEffectComponent:active_effects"),
	]
	for prop_path in on_change_paths:
		config.add_property(prop_path)
		config.property_set_spawn(prop_path, true)
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	synchronizer.replication_config = config
