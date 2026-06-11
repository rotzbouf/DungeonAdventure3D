extends "res://entities/enemy/enemy.gd"

## Dragon boss body. Adds the fire-breath broadcast RPC on top of enemy.gd's
## hit/death/attack handling; everything else (health, stats, animator,
## death/loot/XP, exit-portal activation via on_died) is inherited unchanged.

const FireBreathScene := preload("res://entities/vfx/fire_breath.tscn")


## Broadcast (call_local) when dragon_controller fires its cone fire-breath
## attack — the server has already applied the damage via apply_cone_hit.
@rpc("authority", "call_local", "reliable")
func on_dragon_breath() -> void:
	_animator.play_attack()
	if NetworkMode.is_client():
		AudioManager.play_sfx(&"dragon_roar")
		_spawn_fire_breath_vfx()


func _spawn_fire_breath_vfx() -> void:
	var world := get_tree().root.find_child("World", true, false)
	if world == null:
		return
	var breath := FireBreathScene.instantiate() as Node3D
	world.add_child(breath)
	var forward := -global_transform.basis.z
	breath.global_position = global_position + Vector3(0, 1.5, 0) + forward * 1.5
	breath.look_at(breath.global_position + forward, Vector3.UP)
