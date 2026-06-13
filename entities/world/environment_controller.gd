extends WorldEnvironment

## CLIENT-ONLY dungeon/town atmosphere (M15). Smoothly lerps the shared
## Environment resource (and the sibling DirectionalLight3D) between a dark,
## foggy dungeon preset and a warmer, brighter town preset based on where the
## LOCAL player stands — each peer sees the mood of its own area, nothing is
## replicated. The two areas are disconnected walkable islands (town centered
## at x=-40, dungeon at x>=-10, see world.gd), so a single x threshold is a
## robust area test.
##
## Headless-safe: a WorldEnvironment without _process is inert on a dedicated
## server; we additionally skip processing there.

const TOWN_X_THRESHOLD := -20.0
const LERP_SPEED := 2.0

## ambient/fog drive the Environment resource; light_* the DirectionalLight.
## Dungeon: cool, dim — torch OmniLights (Prop_Torch etc.) carry the scene.
const DUNGEON_PRESET := {
	"ambient_color": Color(0.35, 0.38, 0.5),
	"ambient_energy": 0.4,
	"fog_color": Color(0.1, 0.11, 0.16),
	"fog_density": 0.02,
	"light_energy": 0.3,
	"light_color": Color(0.85, 0.9, 1.0),
}
const TOWN_PRESET := {
	"ambient_color": Color(0.78, 0.73, 0.65),
	"ambient_energy": 0.9,
	"fog_color": Color(0.5, 0.52, 0.58),
	"fog_density": 0.005,
	"light_energy": 0.8,
	"light_color": Color(1.0, 0.95, 0.85),
}

@onready var _light: DirectionalLight3D = get_node("../DirectionalLight3D")

## Snap (rather than lerp) to the first preset once the local player exists,
## so joining in town doesn't start with a 1s dungeon-to-town crossfade.
var _snapped := false


func _ready() -> void:
	set_process(NetworkMode.is_client())


func _process(delta: float) -> void:
	var player := _find_local_player()
	if player == null:
		return
	var preset: Dictionary = TOWN_PRESET if player.global_position.x < TOWN_X_THRESHOLD else DUNGEON_PRESET
	var weight := 1.0 if not _snapped else 1.0 - exp(-LERP_SPEED * delta)
	_snapped = true
	environment.ambient_light_color = environment.ambient_light_color.lerp(preset.ambient_color, weight)
	environment.ambient_light_energy = lerpf(environment.ambient_light_energy, preset.ambient_energy, weight)
	environment.fog_light_color = environment.fog_light_color.lerp(preset.fog_color, weight)
	environment.fog_density = lerpf(environment.fog_density, preset.fog_density, weight)
	_light.light_energy = lerpf(_light.light_energy, preset.light_energy, weight)
	_light.light_color = _light.light_color.lerp(preset.light_color, weight)


func _find_local_player() -> Node3D:
	# Same Players/Player_<peer_id> convention as hud.gd.
	return get_node_or_null("../Players/Player_%d" % multiplayer.get_unique_id())
