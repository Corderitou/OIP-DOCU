@tool
extends EditorNode3DGizmoPlugin

## Gizmo del SixAxisRobot:
## - Cruz/punto celeste en el cabezal = subgizmo que arrastra el nodo
##   "IKTarget" (hijo transitorio del robot). Al soltar, el objetivo queda
##   seleccionado y se puede seguir moviendo con el gizmo nativo del editor
##   (flechitas / anillos). El brazo resuelve IK hacia ese nodo en todo momento
##   (ver robot_ik_target.gd).
## - Marco naranja del EOAT detras de la bandera show_eoat_gizmo.

const EE_COLOR = Color(0.2, 0.9, 0.9)
const EE_SUBGIZMO_ID = 0

const EOAT_COLOR = Color(0.95, 0.6, 0.15)
const EOAT_FRAME_Y = -0.075
const EOAT_HANDLE_SIZE_X = 10
const EOAT_HANDLE_SIZE_Z = 11

var _initial_eoat_size: float = 0.0


func _get_gizmo_name() -> String:
	return "RobotEEGizmo"


func _has_gizmo(node: Node3D) -> bool:
	if node.get_script() == null:
		return false
	var script_path = node.get_script().resource_path
	return script_path == "res://src/SixAxisRobot/six_axis_robot.gd"


func _init() -> void:
	create_handle_material("handles", false)

	create_material("ee_line", EE_COLOR)
	var ee_mat = get_material("ee_line", null)
	if ee_mat:
		ee_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ee_mat.no_depth_test = true
		ee_mat.render_priority = 10

	create_material("eoat_line", EOAT_COLOR)
	var eoat_mat = get_material("eoat_line", null)
	if eoat_mat:
		eoat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eoat_mat.no_depth_test = true
		eoat_mat.render_priority = 10


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var node = gizmo.get_node_3d()
	if node == null:
		return

	if not EditorInterface.get_selection().get_selected_nodes().has(node):
		return

	var handles = PackedVector3Array()
	var handle_ids = PackedInt32Array()

	if node.get("show_gizmos"):
		_draw_ee_point(gizmo, node)

	if node.get("show_eoat_gizmo"):
		_draw_eoat(gizmo, node, handles, handle_ids)

	if handles.size() > 0:
		gizmo.add_handles(handles, get_material("handles", gizmo), handle_ids)


func _draw_ee_point(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
	var tip_global: Vector3 = node.call("get_tool_tip_position")
	var tip_local: Vector3 = node.to_local(tip_global)

	var cross_size: float = 0.08 * (node.get("robot_scale") if node.get("robot_scale") else 1.0)
	var ee_lines = PackedVector3Array()
	ee_lines.append(tip_local + Vector3(-cross_size, 0, 0))
	ee_lines.append(tip_local + Vector3(cross_size, 0, 0))
	ee_lines.append(tip_local + Vector3(0, -cross_size, 0))
	ee_lines.append(tip_local + Vector3(0, cross_size, 0))
	ee_lines.append(tip_local + Vector3(0, 0, -cross_size))
	ee_lines.append(tip_local + Vector3(0, 0, cross_size))
	gizmo.add_lines(ee_lines, get_material("ee_line", gizmo), false)


func _draw_eoat(gizmo: EditorNode3DGizmo, node: Node3D, handles: PackedVector3Array, handle_ids: PackedInt32Array) -> void:
	var eoat: Node3D = node.call("get_attached_tool")
	if eoat == null or not ("tool_size_x" in eoat):
		return

	var half_x: float = eoat.get("tool_size_x") * 0.5
	var half_z: float = eoat.get("tool_size_z") * 0.5
	var to_node := node.global_transform.affine_inverse() * eoat.global_transform

	var corners = [
		Vector3(-half_x, EOAT_FRAME_Y, -half_z),
		Vector3(half_x, EOAT_FRAME_Y, -half_z),
		Vector3(half_x, EOAT_FRAME_Y, half_z),
		Vector3(-half_x, EOAT_FRAME_Y, half_z),
	]
	var lines = PackedVector3Array()
	for i in range(4):
		lines.append(to_node * corners[i])
		lines.append(to_node * corners[(i + 1) % 4])
	gizmo.add_lines(lines, get_material("eoat_line", gizmo), false)

	handles.append(to_node * Vector3(half_x, EOAT_FRAME_Y, 0))
	handle_ids.append(EOAT_HANDLE_SIZE_X)
	handles.append(to_node * Vector3(0, EOAT_FRAME_Y, half_z))
	handle_ids.append(EOAT_HANDLE_SIZE_Z)


func _eoat_size_prop(handle_id: int) -> String:
	return "tool_size_x" if handle_id == EOAT_HANDLE_SIZE_X else "tool_size_z"


func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, screen_pos: Vector2) -> int:
	var node = gizmo.get_node_3d()
	if node == null:
		return -1

	var tip_global: Vector3 = node.call("get_tool_tip_position")
	if camera.is_position_behind(tip_global):
		return -1

	var tip_screen: Vector2 = camera.unproject_position(tip_global)
	if tip_screen.distance_to(screen_pos) <= 20.0:
		return EE_SUBGIZMO_ID
	return -1


func _subgizmos_intersect_frustum(gizmo: EditorNode3DGizmo, camera: Camera3D, frustum_planes: Array[Plane]) -> PackedInt32Array:
	return PackedInt32Array()


func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, subgizmo_id: int) -> Transform3D:
	var node = gizmo.get_node_3d()
	if node == null or subgizmo_id != EE_SUBGIZMO_ID:
		return Transform3D.IDENTITY

	var ik_target: Node3D = node.call("get_ik_target")
	if ik_target == null or not is_instance_valid(ik_target):
		return Transform3D.IDENTITY
	return ik_target.transform


func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, subgizmo_id: int, transform: Transform3D) -> void:
	var node = gizmo.get_node_3d()
	if node == null or subgizmo_id != EE_SUBGIZMO_ID:
		return

	var ik_target: Node3D = node.call("get_ik_target")
	if ik_target == null or not is_instance_valid(ik_target):
		return

	ik_target.transform = transform


func _commit_subgizmos(gizmo: EditorNode3DGizmo, ids: PackedInt32Array, restore: Array[Transform3D], cancel: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	var ik_target: Node3D = node.call("get_ik_target")
	if ik_target == null or not is_instance_valid(ik_target):
		return

	if not ids.has(EE_SUBGIZMO_ID):
		return

	var undo_redo := EditorInterface.get_editor_undo_redo()
	if cancel:
		if restore.size() > 0:
			ik_target.transform = restore[0]
	else:
		undo_redo.create_action("Move Robot End Effector")
		undo_redo.add_do_property(ik_target, "transform", ik_target.transform)
		if restore.size() > 0:
			undo_redo.add_undo_property(ik_target, "transform", restore[0])
		undo_redo.commit_action()

		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(ik_target)

	node.update_gizmos()


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	if handle_id == EOAT_HANDLE_SIZE_X:
		return "EOAT Size X"
	if handle_id == EOAT_HANDLE_SIZE_Z:
		return "EOAT Size Z"
	return ""


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var node = gizmo.get_node_3d()
	if node == null:
		return 0.0
	return node.get(_eoat_size_prop(handle_id))


func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return
	if handle_id == EOAT_HANDLE_SIZE_X or handle_id == EOAT_HANDLE_SIZE_Z:
		_initial_eoat_size = node.get(_eoat_size_prop(handle_id))


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return
	if handle_id == EOAT_HANDLE_SIZE_X or handle_id == EOAT_HANDLE_SIZE_Z:
		_set_eoat_handle(node, handle_id, camera, screen_pos)


func _set_eoat_handle(node: Node3D, handle_id: int, camera: Camera3D, screen_pos: Vector2) -> void:
	var eoat: Node3D = node.call("get_attached_tool")
	if eoat == null:
		return

	var axis_local := Vector3.RIGHT if handle_id == EOAT_HANDLE_SIZE_X else Vector3.BACK
	var origin := eoat.global_transform * Vector3(0, EOAT_FRAME_Y, 0)
	var axis_vec := eoat.global_transform.basis * axis_local
	var axis_scale := axis_vec.length()
	if axis_scale < 0.0001:
		return
	var axis_dir := axis_vec / axis_scale

	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var points := Geometry3D.get_closest_points_between_segments(
		origin - axis_dir * 100.0, origin + axis_dir * 100.0,
		ray_from, ray_from + ray_dir * 1000.0)

	var dist := (points[0] - origin).dot(axis_dir)
	node.set(_eoat_size_prop(handle_id), absf(dist) * 2.0 / axis_scale)
	node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var node = gizmo.get_node_3d()
	if node == null:
		return

	if handle_id == EOAT_HANDLE_SIZE_X or handle_id == EOAT_HANDLE_SIZE_Z:
		var prop := _eoat_size_prop(handle_id)
		if cancel:
			node.set(prop, _initial_eoat_size)
		else:
			var eoat_undo_redo := EditorInterface.get_editor_undo_redo()
			eoat_undo_redo.create_action("Resize Robot EOAT")
			eoat_undo_redo.add_do_property(node, prop, node.get(prop))
			eoat_undo_redo.add_undo_property(node, prop, _initial_eoat_size)
			eoat_undo_redo.commit_action()

	node.update_gizmos()
