class_name SelectionManager
extends Node3D

const HIGHLIGHT_COLOR := Color(0.2, 0.9, 1.0, 1.0)
const OUTLINE_SCALE := 1.03
const OUTLINE_WIDTH := 4.0

signal selection_changed(selected: Array[Node3D])
signal node_selected(node: Node3D)
signal node_deselected(node: Node3D)

var _selected: Array[Node3D] = []
var _primary: Node3D = null
var _node_original_materials: Dictionary = {}  # Node3D → Array[MeshInstance3D → Material]

var selected: Array[Node3D]:
	get:
		return _selected

var primary_selection: Node3D:
	get:
		return _primary


func select(node: Node3D, additive: bool = false) -> void:
	if not node or not node is Node3D:
		return

	if not additive:
		deselect_all()

	if not _selected.has(node):
		_selected.append(node)
		_highlight_node(node)
		node_selected.emit(node)

	_primary = node
	RuntimeSelection.select_node(node)
	selection_changed.emit(_selected)


func deselect(node: Node3D) -> void:
	_selected.erase(node)
	_unhighlight_node(node)
	if _primary == node:
		_primary = _selected[0] if not _selected.is_empty() else null
	node_deselected.emit(node)
	RuntimeSelection.deselect_all()
	selection_changed.emit(_selected)


func deselect_all() -> void:
	for node in _selected:
		_unhighlight_node(node)
	_selected.clear()
	_primary = null
	RuntimeSelection.deselect_all()
	selection_changed.emit(_selected)


func is_selected(node: Node3D) -> bool:
	return _selected.has(node)


func select_by_raycast(from: Vector3, direction: Vector3, camera: Camera3D, viewport_size: Vector2) -> Node3D:
	var space_state := get_world_3d().direct_space_state
	var ray_length := 1000.0
	var to := from + direction * ray_length

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF  # Check all physics layers (Static=1, Dynamic=2, Belt=3, Box=4, etc.)
	query.collide_with_areas = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider := result["collider"] as Node3D
	return _find_part_root(collider)


## Walk up from the collider to the node that is a direct child of SceneRoot.
## Raycasts hit StaticBody3D/RigidBody3D children, but we want to select and
## move the whole part. The floor (StaticBody3D named "Floor") and SceneRoot
## itself are not selectable.
func _find_part_root(node: Node3D) -> Node3D:
	if not is_instance_valid(node):
		return null
	# Reject the floor by name BEFORE walking up.
	if node.name == "Floor" or node.name == "SceneRoot":
		return null
	var current: Node = node
	while current:
		var parent := current.get_parent()
		if parent and parent.name == "SceneRoot":
			var as_3d := current as Node3D
			if as_3d and as_3d.name == "Floor":
				return null
			return as_3d
		current = parent
	return node


func select_by_point(point: Vector2, camera: Camera3D, viewport_size: Vector2) -> Node3D:
	var ray_origin := camera.project_ray_origin(point)
	var ray_dir := camera.project_ray_normal(point)
	return select_by_raycast(ray_origin, ray_dir, camera, viewport_size)


func _highlight_node(node: Node3D) -> void:
	var meshes := _collect_meshes(node)
	_node_original_materials[node] = meshes
	for mi: MeshInstance3D in meshes:
		var outline := MeshInstance3D.new()
		outline.name = "_outline_" + mi.name
		outline.mesh = mi.mesh
		outline.layers = mi.layers
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

		outline.transform = mi.transform
		outline.scale = mi.scale * OUTLINE_SCALE

		var mat := StandardMaterial3D.new()
		mat.albedo_color = HIGHLIGHT_COLOR
		mat.emission_enabled = true
		mat.emission = HIGHLIGHT_COLOR
		mat.emission_energy_multiplier = 1.2
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		outline.material_override = mat

		mi.get_parent().add_child(outline)
		outline.owner = node.owner if node.owner else mi.get_parent()


func _unhighlight_node(node: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = _node_original_materials.get(node, [])
	for mi: MeshInstance3D in meshes:
		if is_instance_valid(mi) and mi.get_parent():
			var parent := mi.get_parent()
			for sibling in parent.get_children():
				if sibling is MeshInstance3D and sibling.name.begins_with("_outline_"):
					sibling.queue_free()
	_node_original_materials.erase(node)


func _collect_meshes(node: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var seen: Dictionary = {}  # Use mesh instance ID as key to deduplicate
	_collect_meshes_unique(node, result, seen)
	return result


func _collect_meshes_unique(node: Node3D, result: Array[MeshInstance3D], seen: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var id := child.get_instance_id()
			if not seen.has(id):
				seen[id] = true
				result.append(child)
		elif child is Node3D:
			_collect_meshes_unique(child, result, seen)
