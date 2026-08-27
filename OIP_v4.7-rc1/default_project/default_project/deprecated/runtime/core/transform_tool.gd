class_name TransformTool
extends Node3D

enum TransformMode { SELECT, MOVE, ROTATE }

signal axis_changed(axis: String)
signal rotation_dragging(angle_deg: float, axis: String)

var _mode: TransformMode = TransformMode.SELECT
var _dragging: bool = false
var _drag_start_pos: Vector3 = Vector3.ZERO
var _drag_prev_screen: Vector2 = Vector2.ZERO
var _drag_y_accum: float = 0.0
var _drag_x_accum: float = 0.0
var _drag_node_start_pos: Vector3 = Vector3.ZERO
var _drag_node_start_rot: Vector3 = Vector3.ZERO
var _move_axis_lock: String = ""
var _rotate_axis_lock: String = ""

var _grid_system: GridSystem = null
var _selection_manager: SelectionManager = null
var _viewport_camera: Camera3D = null
var _scene_manager: SceneManager = null

var _pending_click: Vector2 = Vector2.INF
var _pending_additive: bool = false
var _action_active: bool = false

var mode: TransformMode:
	get:
		return _mode

var move_y_axis: bool:
	get:
		return _move_axis_lock == "y"

var move_axis_lock: String:
	get:
		return _move_axis_lock

var rotate_axis_lock: String:
	get:
		return _rotate_axis_lock

var is_dragging: bool:
	get:
		return _dragging


func setup(grid: GridSystem, selection: SelectionManager, camera: Camera3D, scene_mgr: SceneManager) -> void:
	_grid_system = grid
	_selection_manager = selection
	_viewport_camera = camera
	_scene_manager = scene_mgr


func set_mode(new_mode: TransformMode) -> void:
	_mode = new_mode


func toggle_move_y() -> void:
	if _move_axis_lock == "y":
		_move_axis_lock = ""
	else:
		_move_axis_lock = "y"
	axis_changed.emit(_move_axis_lock)


func set_move_axis_lock(axis: String) -> void:
	_move_axis_lock = axis
	axis_changed.emit(axis)


func clear_move_axis_lock() -> void:
	_move_axis_lock = ""
	axis_changed.emit("")


func set_rotate_axis_lock(axis: String) -> void:
	_rotate_axis_lock = axis
	axis_changed.emit(axis)


func clear_rotate_axis_lock() -> void:
	_rotate_axis_lock = ""
	axis_changed.emit("")


func handle_click(viewport_pos: Vector2, additive: bool = false) -> void:
	_pending_additive = additive
	_pending_click = viewport_pos


func _physics_process(_delta: float) -> void:
	if _pending_click == Vector2.INF:
		return
	var click_pos := _pending_click
	var additive: bool = _pending_additive
	_pending_click = Vector2.INF
	_pending_additive = false

	if _mode == TransformMode.SELECT:
		_handle_select_click(click_pos, additive)
	elif _mode == TransformMode.MOVE or _mode == TransformMode.ROTATE:
		_handle_transform_click(click_pos)


func handle_drag(start: Vector2, current: Vector2, viewport_size: Vector2) -> void:
	if not _dragging:
		return

	var selected := _selection_manager.selected
	if selected.is_empty():
		return

	if _mode == TransformMode.MOVE:
		_handle_move_drag(current)
	elif _mode == TransformMode.ROTATE:
		_handle_rotate_drag(current)


func _handle_move_drag(current: Vector2) -> void:
	var selected := _selection_manager.selected
	var delta_pos: Vector3

	match _move_axis_lock:
		"x":
			var ray_origin := _viewport_camera.project_ray_origin(current)
			var ray_dir := _viewport_camera.project_ray_normal(current)
			var plane := Plane(Vector3.FORWARD, -_drag_node_start_pos.z)
			var intersection = plane.intersects_ray(ray_origin, ray_dir)
			if intersection:
				_drag_prev_screen = current
				delta_pos = Vector3(intersection.x - _drag_start_pos.x, 0, 0)
			else:
				return
		"y":
			var delta_screen := current - _drag_prev_screen
			_drag_prev_screen = current
			_drag_y_accum -= delta_screen.y * 0.01
			delta_pos = Vector3(0.0, _drag_y_accum, 0.0)
		"z":
			var ray_origin := _viewport_camera.project_ray_origin(current)
			var ray_dir := _viewport_camera.project_ray_normal(current)
			var plane := Plane(Vector3.RIGHT, _drag_node_start_pos.x)
			var intersection = plane.intersects_ray(ray_origin, ray_dir)
			if intersection:
				_drag_prev_screen = current
				delta_pos = Vector3(0, 0, intersection.z - _drag_start_pos.z)
			else:
				return
		_:
			var ray_origin := _viewport_camera.project_ray_origin(current)
			var ray_dir := _viewport_camera.project_ray_normal(current)
			var plane := Plane(Vector3.UP, _drag_node_start_pos.y)
			var intersection = plane.intersects_ray(ray_origin, ray_dir)
			if not intersection:
				return
			_drag_prev_screen = current
			delta_pos = intersection - _drag_start_pos

	for node in selected:
		var new_pos := _drag_node_start_pos + delta_pos
		if _grid_system:
			new_pos = _grid_system.snap_position(new_pos)
		node.position = new_pos


func _handle_rotate_drag(current: Vector2) -> void:
	var selected := _selection_manager.selected
	var delta_screen := current - _drag_prev_screen
	_drag_prev_screen = current

	# Determine rotation axis
	var axis := _rotate_axis_lock if _rotate_axis_lock != "" else "y"
	
	# Horizontal mouse movement = rotation around selected axis
	var angle_delta: float = delta_screen.x * 0.005
	
	var applied_angle_deg: float = 0.0
	for node in selected:
		var new_rot := node.rotation
		match axis:
			"x":
				new_rot.x += angle_delta
				applied_angle_deg = rad_to_deg(new_rot.x)
			"y":
				new_rot.y += angle_delta
				applied_angle_deg = rad_to_deg(new_rot.y)
			"z":
				new_rot.z += angle_delta
				applied_angle_deg = rad_to_deg(new_rot.z)
		if _grid_system:
			# Snap rotation on the active axis
			match axis:
				"x": new_rot.x = _grid_system.snap_rotation_y(new_rot.x)
				"y": new_rot.y = _grid_system.snap_rotation_y(new_rot.y)
				"z": new_rot.z = _grid_system.snap_rotation_y(new_rot.z)
		node.rotation = new_rot
	
	rotation_dragging.emit(applied_angle_deg, axis)


func handle_drag_end() -> void:
	if not _dragging:
		if _action_active:
			RuntimeUndoRedo.commit_action(false)
			_action_active = false
		return

	_dragging = false

	var selected := _selection_manager.selected
	if selected.is_empty():
		if _action_active:
			RuntimeUndoRedo.commit_action(false)
			_action_active = false
		return

	for n in selected:
		RuntimeUndoRedo.add_do_property(n, "position", n.position)
		RuntimeUndoRedo.add_do_property(n, "rotation", n.rotation)
	RuntimeUndoRedo.commit_action()
	_action_active = false

	if _mode == TransformMode.MOVE:
		RuntimeEditorStub.transform_commited.emit()
	if _scene_manager:
		_scene_manager.mark_modified()


func _handle_select_click(viewport_pos: Vector2, additive: bool = false) -> void:
	var node := _selection_manager.select_by_point(viewport_pos, _viewport_camera, Vector2.ZERO)
	if node:
		if additive:
			if _selection_manager.is_selected(node):
				_selection_manager.deselect(node)
			else:
				_selection_manager.select(node, true)
		else:
			_selection_manager.deselect_all()
			_selection_manager.select(node)
	else:
		if not additive:
			_selection_manager.deselect_all()


func _handle_transform_click(viewport_pos: Vector2) -> void:
	var node := _selection_manager.select_by_point(viewport_pos, _viewport_camera, Vector2.ZERO)
	if not node:
		_selection_manager.deselect_all()
		return

	if not _selection_manager.is_selected(node):
		_selection_manager.deselect_all()
		_selection_manager.select(node)

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	# Create undo action now that we know we're starting a drag
	_action_active = true
	if _mode == TransformMode.MOVE:
		RuntimeUndoRedo.create_action("Move Part")
	else:
		RuntimeUndoRedo.create_action("Rotate Part")
	for n in _selection_manager.selected:
		RuntimeUndoRedo.add_undo_property(n, "position", n.position)
		RuntimeUndoRedo.add_undo_property(n, "rotation", n.rotation)

	_dragging = true
	_drag_prev_screen = viewport_pos
	_drag_y_accum = 0.0
	_drag_x_accum = 0.0
	_drag_node_start_pos = node.position
	_drag_node_start_rot = node.rotation

	var ray_origin := _viewport_camera.project_ray_origin(viewport_pos)
	var ray_dir := _viewport_camera.project_ray_normal(viewport_pos)
	var plane := Plane(Vector3.UP, node.global_position.y)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)

	if intersection:
		_drag_start_pos = intersection
	else:
		_drag_start_pos = node.global_position


func handle_rotate(angle_delta: float) -> void:
	var selected := _selection_manager.selected
	if selected.is_empty():
		return

	RuntimeUndoRedo.create_action("Rotate Part")
	for node in selected:
		RuntimeUndoRedo.add_undo_property(node, "rotation", node.rotation)

	# Determine rotation axis
	var axis := _rotate_axis_lock if _rotate_axis_lock != "" else "y"

	for node in selected:
		var new_rot := node.rotation
		match axis:
			"x":
				new_rot.x += angle_delta
				if _grid_system:
					new_rot.x = _grid_system.snap_rotation_y(new_rot.x)
			"y":
				new_rot.y += angle_delta
				if _grid_system:
					new_rot.y = _grid_system.snap_rotation_y(new_rot.y)
			"z":
				new_rot.z += angle_delta
				if _grid_system:
					new_rot.z = _grid_system.snap_rotation_y(new_rot.z)
		node.rotation = new_rot

	for node in selected:
		RuntimeUndoRedo.add_do_property(node, "rotation", node.rotation)
	RuntimeUndoRedo.commit_action()

	if _scene_manager:
		_scene_manager.mark_modified()
