class_name HitFlash

## Brief white (or tinted) emissive overlay on every MeshInstance3D under
## `model_root` — the shared "I just got hit" feedback for enemies and players
## (extracted from enemy.gd in M15). Purely cosmetic, client-side only.


static func flash(model_root: Node3D, color := Color(1, 1, 1, 1)) -> void:
	if model_root == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, meshes)
	if meshes.is_empty():
		return
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = color
	flash_material.emission_enabled = true
	flash_material.emission = Color(color.r, color.g, color.b, 1)
	for mesh in meshes:
		mesh.material_overlay = flash_material

	# The tween dies with model_root if the entity is freed mid-flash (enemies
	# free 0.6s after death), but a captured mesh can ALSO be freed while the
	# tween itself survives — hence is_instance_valid inside the lambda, not
	# just the material-identity check.
	var clear_overlay := func() -> void:
		for mesh in meshes:
			if is_instance_valid(mesh) and mesh.material_overlay == flash_material:
				mesh.material_overlay = null

	var tween := model_root.create_tween()
	tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(clear_overlay)


static func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, result)
