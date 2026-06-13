extends OmniLight3D

## CLIENT-ONLY torch/brazier/candle flicker (M15): modulates light_energy
## around its authored value with two incommensurate sine frequencies plus a
## random per-instance phase. Deliberately unsynced across peers — flicker
## phase is ambience, not gameplay state, so it is never replicated.

const FLICKER_FREQ_A := 7.3
const FLICKER_FREQ_B := 11.7
const FLICKER_DEPTH_A := 0.15
const FLICKER_DEPTH_B := 0.08

var _base_energy: float
var _phase: float


func _ready() -> void:
	_base_energy = light_energy
	_phase = randf() * TAU
	set_process(not NetworkMode.is_dedicated_server())


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	light_energy = _base_energy * (1.0 \
			+ FLICKER_DEPTH_A * sin(t * FLICKER_FREQ_A) \
			+ FLICKER_DEPTH_B * sin(t * FLICKER_FREQ_B))
