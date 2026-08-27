extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in ["res://assets/glb/StringerFrame.glb", "res://assets/glb/StringerHead.glb"]:
		print("=== ", path, " ===")
		var packed := load(path) as PackedScene
		if not packed:
			print("  FAILED to load")
			continue
		var inst := packed.instantiate()
		if not inst:
			print("  FAILED to instantiate")
			continue
		_print_tree(inst, 1)
		var aabb := _calc_aabb(inst)
		print("  AABB position: ", aabb.position, " size: ", aabb.size)
		inst.queue_free()
	quit(0)

func _print_tree(node: Node, depth: int) -> void:
	var indent := ""
	for i in depth:
		indent += "  "
	var info := node.name + " (" + node.get_class() + ")"
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			info += " mesh=" + mi.mesh.get_class()
			if mi.mesh is ArrayMesh:
				var am := mi.mesh as ArrayMesh
				info += " surfaces=" + str(am.get_surface_count())
				for s in am.get_surface_count():
					var mat := am.surface_get_material(s)
					if mat:
						info += " mat=" + mat.get_class()
	var t3d := node as Node3D
	if t3d:
		info += " pos=" + str(t3d.position) + " scale=" + str(t3d.scale) + " rot=" + str(t3d.rotation)
	print(indent + info)
	for c in node.get_children():
		_print_tree(c, depth + 1)

func _calc_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var found := false
	_gather_aabb(node, aabb, found)
	if not found:
		return AABB()
	return aabb

func _gather_aabb(node: Node3D, aabb: AABB, found: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var local := mi.get_aabb()
			var global := node.global_transform * local
			if not found:
				aabb.position = global.position
				aabb.size = global.size
				found = true
			else:
				aabb = aabb.merge(global)
	for c in node.get_children():
		if c is Node3D:
			_gather_aabb(c as Node3D, aabb, found)
