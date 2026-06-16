extends Node3D

## Debug cell overlay for dungeon layout verification (DEBUG_CELLS=1).
## world._rebuild_dungeon() calls build(cell_roles) after each floor; the node
## is freed and recreated on the next call so the overlay always matches the
## current layout.

const CELL_SIZE := 4.0

const COLOR_ENTRY    := Color(0.2, 0.9, 0.2, 0.5)
const COLOR_SIDE     := Color(0.2, 0.4, 0.9, 0.5)
const COLOR_BOSS     := Color(0.9, 0.2, 0.2, 0.5)
const COLOR_CORRIDOR := Color(0.9, 0.9, 0.9, 0.35)

# Wall-bar colors encode the wall's world direction (N/S/E/W).
const COLOR_NORTH := Color(0.15, 0.4, 1.0, 0.85)   # blue
const COLOR_SOUTH := Color(1.0,  0.85, 0.1,  0.85)  # yellow
const COLOR_EAST  := Color(1.0,  0.2,  0.2,  0.85)  # red
const COLOR_WEST  := Color(0.1,  0.85, 0.3,  0.85)  # green


## `cell_roles`: keys = Vector2i world-cell coords,
##              values = StringName role (&"entry", &"side", &"boss", or &"").
func build(cell_roles: Dictionary) -> void:
	var cell_set := {}
	for c in cell_roles:
		cell_set[c] = true

	for cell: Vector2i in cell_roles:
		var cx := cell.x
		var cz := cell.y
		var wx := float(cx) * CELL_SIZE
		var wz := float(cz) * CELL_SIZE

		var color: Color
		match cell_roles[cell]:
			&"entry": color = COLOR_ENTRY
			&"side":  color = COLOR_SIDE
			&"boss":  color = COLOR_BOSS
			_:        color = COLOR_CORRIDOR

		_add_quad(Vector3(wx, 0.05, wz), CELL_SIZE - 0.1, CELL_SIZE - 0.1, color)

		var label := Label3D.new()
		label.text = "(%d,%d)" % [cx, cz]
		label.font_size = 28
		label.modulate = Color(1.0, 1.0, 1.0, 0.9)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(wx, 0.15, wz)
		add_child(label)

		# Wall bars: one colored strip per boundary edge (absent neighbour).
		var half := CELL_SIZE / 2.0
		const BAR_W := 3.6
		const BAR_T := 0.25
		if not cell_set.has(Vector2i(cx, cz - 1)):
			_add_quad(Vector3(wx, 0.07, wz - half), BAR_W, BAR_T, COLOR_NORTH)
		if not cell_set.has(Vector2i(cx, cz + 1)):
			_add_quad(Vector3(wx, 0.07, wz + half), BAR_W, BAR_T, COLOR_SOUTH)
		if not cell_set.has(Vector2i(cx + 1, cz)):
			_add_quad(Vector3(wx + half, 0.07, wz), BAR_T, BAR_W, COLOR_EAST)
		if not cell_set.has(Vector2i(cx - 1, cz)):
			_add_quad(Vector3(wx - half, 0.07, wz), BAR_T, BAR_W, COLOR_WEST)


func _add_quad(center: Vector3, size_x: float, size_z: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat
	mi.mesh = plane
	mi.position = center
	add_child(mi)
