extends Node3D

const SPACING := 24.0
const COLS := 5
const PIECES := [
	"room-small", "room-wide", "room-large", "room-corner", "corridor",
	"corridor-corner", "corridor-junction", "corridor-intersection", "corridor-end",
	"corridor-transition", "corridor-wide", "corridor-wide-corner", "corridor-wide-junction",
	"corridor-wide-intersection", "gate",
]


func _ready() -> void:
	for i in PIECES.size():
		var piece_name: String = PIECES[i]
		var scene: PackedScene = load("res://entities/dungeon/kenney/%s.glb" % piece_name)
		var inst := scene.instantiate()
		var col := i % COLS
		var row := i / COLS
		inst.position = Vector3(col * SPACING, 0.0, row * SPACING)
		add_child(inst)

		var label := Label3D.new()
		label.text = piece_name
		label.position = Vector3(col * SPACING, 6.0, row * SPACING - 2.0)
		label.font_size = 32
		label.modulate = Color.YELLOW
		label.no_depth_test = true
		add_child(label)

		# Mark local +Z axis (red) and +X axis (green) of each piece for orientation reference.
		var z_marker := CSGBox3D.new()
		z_marker.size = Vector3(0.5, 0.5, 1.5)
		z_marker.position = Vector3(col * SPACING, 0.5, row * SPACING + 2.5)
		z_marker.material = StandardMaterial3D.new()
		z_marker.material.albedo_color = Color.RED
		add_child(z_marker)

		var x_marker := CSGBox3D.new()
		x_marker.size = Vector3(1.5, 0.5, 0.5)
		x_marker.position = Vector3(col * SPACING + 2.5, 0.5, row * SPACING)
		x_marker.material = StandardMaterial3D.new()
		x_marker.material.albedo_color = Color.GREEN
		add_child(x_marker)
