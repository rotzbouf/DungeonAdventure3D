extends Node3D

## Client-only rarity indicator for loot_drop.gd: a pulsing colored light plus
## a small column of sparkles, both tinted by Rarity.COLORS. Hidden by default
## (the common case); set_rarity() reveals it for uncommon/rare drops. Reuses
## flicker_light.gd's sine-pulse pattern for the light.

const PULSE_FREQ := 2.0
const PULSE_DEPTH := 0.35

@onready var _light: OmniLight3D = $OmniLight3D
@onready var _particles: GPUParticles3D = $GPUParticles3D

var _base_energy: float = 0.0


func _ready() -> void:
	_base_energy = _light.light_energy
	visible = false
	set_process(not NetworkMode.is_dedicated_server())


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_light.light_energy = _base_energy * (1.0 + PULSE_DEPTH * sin(t * PULSE_FREQ))


## Reveals the glow for uncommon/rare drops, tinted by Rarity.COLORS. Stays
## hidden for &"common" (and the empty-string default for non-rarity items).
func set_rarity(rarity: StringName) -> void:
	if rarity == &"common" or rarity == &"":
		return
	visible = true
	var color: Color = Rarity.COLORS.get(rarity, Rarity.COLORS[&"common"])
	_light.light_color = color
	var draw_material: StandardMaterial3D = _particles.material_override
	draw_material.albedo_color = color
	draw_material.emission = color
