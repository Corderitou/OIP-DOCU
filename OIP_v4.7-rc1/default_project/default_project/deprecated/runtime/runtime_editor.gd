extends Control

## Main controller for the runtime scene editor.
## Manages the toolbar, viewport, parts browser, inspector, and all tools.

var _scene_manager: SceneManager
var _selection_manager: SelectionManager
var _clipboard_manager: ClipboardManager
var _simulation_controller: SimulationController
var _transform_tool: TransformTool
var _grid_system: GridSystem
var _camera: ViewportCamera
var _input_manager: InputManager
var _file_dialogs: FileDialogs
var _scene_root_3d: Node3D

@onready var _toolbar: Toolbar = get_node("VBox/Toolbar")
@onready var _parts_browser: PartsBrowser = get_node("VBox/MainArea/LeftPanel/PartsBrowser")
@onready var _inspector: InspectorPanel = get_node("VBox/MainArea/RightPanel/InspectorPanel")
@onready var _status_bar: StatusBar = get_node("VBox/StatusBar")
@onready var _notification_bar: Control = get_node("VBox/NotificationBar")
@onready var _comms_panel: CommsPanel = get_node("COMMSPanel")
@onready var _viewport_3d: SubViewportContainer = get_node("VBox/MainArea/Viewport3D")
@onready var _viewport: SubViewport = get_node("VBox/MainArea/Viewport3D/SubViewport")
@onready var _selection_rect: ColorRect = get_node("VBox/MainArea/Viewport3D/SelectionRect")

var _ghost_node: Node3D = null
var _pending_place_type: String = ""
var _hovered_node: Node3D = null
var _hover_label: Label = null
var _ghost_y_mode: bool = false
var _ghost_y_offset: float = 0.0
var _debug_server: Node = null

var _rect_drag_start: Vector2 = Vector2.INF
var _rect_dragging: bool = false
var _rect_current: Vector2 = Vector2.ZERO
var _axis_indicator: AxisIndicator = null

# Angle typing during rotation drag
var _angle_input_active: bool = false
var _angle_input_buffer: String = ""
var _angle_input_axis: String = ""
var _angle_input_frozen_rot: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Apply dark theme
	theme = EditorTheme.build()

	_scene_manager = SceneManager.new()
	_selection_manager = SelectionManager.new()
	_clipboard_manager = ClipboardManager.new()
	_simulation_controller = SimulationController.new()
	_transform_tool = TransformTool.new()
	_grid_system = GridSystem.new()
	_input_manager = InputManager.new()
	_file_dialogs = FileDialogs.new()

	_scene_root_3d = Node3D.new()
	_scene_root_3d.name = "SceneRoot"
	_viewport.add_child(_scene_root_3d)

	_viewport.add_child(_grid_system)

	_camera = ViewportCamera.new()
	_camera.far = 500.0
	_camera.mode_changed.connect(func(mode_name: String):
		_status_bar.set_mode(mode_name)
		_toolbar.set_camera_mode(mode_name)
	)
	_viewport.add_child(_camera)

	_viewport.add_child(_selection_manager)
	_viewport.add_child(_simulation_controller)
	_viewport.add_child(_transform_tool)
	add_child(_input_manager)
	add_child(_file_dialogs)

	_setup_debug_server()

	_axis_indicator = AxisIndicator.new()
	_axis_indicator.name = "AxisIndicator"
	_viewport.add_child(_axis_indicator)

	_transform_tool.setup(_grid_system, _selection_manager, _camera, _scene_manager)
	_scene_manager.scene_root = _scene_root_3d
	_simulation_controller.scene_root = _scene_root_3d
	_file_dialogs.setup(_scene_manager, _scene_manager, _scene_root_3d)
	_inspector.setup(_scene_manager)
	_comms_panel.set_scene_root(_scene_root_3d)
	_comms_panel.back_pressed.connect(_on_toggle_comms_panel)

	_connect_signals()
	_setup_toast_bridge()

	_hover_label = Label.new()
	_hover_label.visible = false
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.add_theme_font_size_override("font_size", 12)
	_hover_label.add_theme_color_override("font_color", Color("#e6edf3"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.12, 0.92)
	sb.border_color = Color("#30363d")
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.set_content_margin_all(6)
	_hover_label.add_theme_stylebox_override("normal", sb)
	add_child(_hover_label)

	_status_bar.set_status("Ready")


func _connect_signals() -> void:
	_toolbar.new_pressed.connect(_on_new)
	_toolbar.open_pressed.connect(_on_open)
	_toolbar.save_pressed.connect(_on_save)
	_toolbar.play_pressed.connect(_on_play)
	_toolbar.pause_pressed.connect(_on_pause)
	_toolbar.stop_pressed.connect(_on_stop)
	_toolbar.undo_pressed.connect(_on_undo)
	_toolbar.redo_pressed.connect(_on_redo)
	_toolbar.select_mode.connect(_on_select_mode)
	_toolbar.move_mode.connect(_on_move_mode)
	_toolbar.rotate_mode.connect(_on_rotate_mode)
	_toolbar.snap_toggled.connect(_on_snap_toggled)
	_toolbar.copy_pressed.connect(_on_copy)
	_toolbar.paste_pressed.connect(_on_paste)
	_toolbar.duplicate_pressed.connect(_on_duplicate)
	_toolbar.delete_pressed.connect(_on_delete)
	_toolbar.focus_pressed.connect(_on_focus)
	_toolbar.view_front.connect(func(): _camera._set_front_view())
	_toolbar.view_back.connect(func(): _camera._set_back_view())
	_toolbar.view_left.connect(func(): _camera._set_left_view())
	_toolbar.view_right.connect(func(): _camera._set_right_view())
	_toolbar.view_top.connect(func(): _camera._set_top_view())
	_toolbar.toggle_left_panel.connect(_on_toggle_left_panel)
	_toolbar.toggle_right_panel.connect(_on_toggle_right_panel)
	_toolbar.toggle_status_bar.connect(_on_toggle_status_bar)
	_toolbar.toggle_comms_panel.connect(_on_toggle_comms_panel)
	_toolbar.rotation_snap_changed.connect(_on_rotation_snap_changed)

	_input_manager.undo_requested.connect(_on_undo)
	_input_manager.redo_requested.connect(_on_redo)
	_input_manager.save_requested.connect(_on_save)
	_input_manager.open_requested.connect(_on_open)
	_input_manager.new_scene_requested.connect(_on_new)
	_input_manager.delete_requested.connect(_on_delete)
	_input_manager.copy_requested.connect(_on_copy)
	_input_manager.paste_requested.connect(_on_paste)
	_input_manager.duplicate_requested.connect(_on_duplicate)
	_input_manager.focus_requested.connect(_on_focus)
	_input_manager.toggle_grid_requested.connect(_on_snap_toggled)
	_input_manager.cancel_requested.connect(_on_cancel)
	_input_manager.simulation_toggle_requested.connect(_on_play)
	_input_manager.group_requested.connect(_on_group)
	_input_manager.ungroup_requested.connect(_on_ungroup)
	_input_manager.rotate_exact_requested.connect(_on_rotate_exact)

	_input_manager.tool_mode_changed.connect(func(mode):
		_toolbar.set_active_tool(int(mode))
		_toolbar.set_mode_label(_input_manager.get_mode_name(mode))
		_status_bar.set_mode(_input_manager.get_mode_name(mode))
		_transform_tool.set_mode(int(mode))
		_update_axis_indicator(_transform_tool.move_axis_lock)
	)

	_parts_browser.part_selected.connect(_on_part_selected)
	_scene_manager.scene_modified.connect(func(): _status_bar.set_status("Modified"))
	_scene_manager.scene_modified.connect(func(): _simulation_controller.refresh_initial_state())
	_selection_manager.selection_changed.connect(_on_selection_changed)

	_transform_tool.axis_changed.connect(_update_axis_indicator)
	_transform_tool.rotation_dragging.connect(_on_rotation_dragging)

	_file_dialogs.scene_loaded.connect(_on_scene_loaded)
	_file_dialogs.scene_saved.connect(_on_scene_saved)


func _setup_toast_bridge() -> void:
	RuntimeEditorToaster.set_editor_toaster(null)
	RuntimeEditorToaster.toast_pushed.connect(func(message: String, severity: int):
		if _notification_bar:
			_notification_bar.show_toast(message, severity)
	)
	RuntimeEditorToaster.push_toast("Runtime Editor ready", RuntimeEditorToaster.SEVERITY_INFO)


func _setup_debug_server() -> void:
	var script: Script = load("res://src/runtime/core/debug_server.gd")
	_debug_server = Node.new()
	_debug_server.set_script(script)
	_debug_server.name = "DebugServer"
	add_child(_debug_server)
	_debug_server.set_runtime_editor(self)


func _process(_delta: float) -> void:
	_update_hover()


func _update_hover() -> void:
	# No hover tooltip while placing a part or rect-selecting.
	if _pending_place_type or _rect_dragging:
		_hide_hover()
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var rect := _viewport_3d.get_global_rect()
	if not rect.has_point(mouse_pos):
		_hide_hover()
		return

	var vp_pos := (mouse_pos - rect.position) * _viewport_3d.stretch_shrink
	var ray_origin := _camera.project_ray_origin(vp_pos)
	var ray_dir := _camera.project_ray_normal(vp_pos)

	var world := _viewport.get_world_3d()
	if not world:
		_hide_hover()
		return
	var space_state := world.direct_space_state
	if not space_state:
		_hide_hover()
		return
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		_hide_hover()
		return

	var hit_node = result["collider"]
	if not hit_node:
		_hide_hover()
		return

	# Walk up to find a node owned by scene root (a placed part).
	# Use an untyped var: the walk can pass non-Node3D ancestors (e.g. SubViewport).
	var part: Node3D = null
	var check: Node = hit_node
	while check and check != _scene_root_3d:
		if check is Node3D and check.owner == _scene_root_3d:
			part = check
			break
		check = check.get_parent()

	if not part:
		_hide_hover()
		return

	_hovered_node = part
	var type := SceneRegistry.get_type_for_node(part)
	var pos := part.position
	var info := part.name
	if not type.is_empty():
		info += "  [%s]" % type
	info += "\nPos: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

	if _hover_label.text != info:
		_hover_label.text = info
		_hover_label.reset_size()
	_hover_label.visible = true
	_hover_label.position = mouse_pos + Vector2(16, 16)
	# Keep tooltip on screen
	var vp_size := get_viewport().get_visible_rect().size
	if _hover_label.position.x + _hover_label.size.x > vp_size.x:
		_hover_label.position.x = mouse_pos.x - _hover_label.size.x - 8
	if _hover_label.position.y + _hover_label.size.y > vp_size.y:
		_hover_label.position.y = mouse_pos.y - _hover_label.size.y - 8


func _hide_hover() -> void:
	_hovered_node = null
	if _hover_label:
		_hover_label.visible = false


func _input(event: InputEvent) -> void:
	if _comms_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_on_toggle_comms_panel()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _angle_input_active:
			return

	var rect: Rect2 = _viewport_3d.get_global_rect()
	var mouse_in_viewport: bool = rect.has_point(get_viewport().get_mouse_position())

	# Helper: convert global mouse pos to SubViewport coords.
	var to_viewport_pos := func() -> Vector2:
		var p: Vector2 = get_viewport().get_mouse_position() - rect.position
		return p * _viewport_3d.stretch_shrink

	# Tell camera to ignore right-click pan when we are placing a part (so right-click cancels).
	_camera.set_suppress_right_click(_pending_place_type != "")

	# --- Mouse button events ---
	if event is InputEventMouseButton:
		# Handle mouse button release even outside viewport if a drag was in progress.
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and (_transform_tool.is_dragging or _rect_dragging):
			if _rect_dragging:
				_finalize_rect_selection()
			_rect_dragging = false
			_rect_drag_start = Vector2.INF
			_selection_rect.visible = false
			# Clean up angle typing if active
			if _angle_input_active:
				_cancel_angle_input()
			_transform_tool.handle_drag_end()
			get_viewport().set_input_as_handled()
			return

		if not mouse_in_viewport:
			return

		# Right-click while placing => cancel placement FIRST (before camera pan).
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _pending_place_type:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return

		# Right-click: show context menu if we have a selection.
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _selection_manager.selected.size() > 0 and not _pending_place_type:
			_show_context_menu()
			get_viewport().set_input_as_handled()
			return

		# Let camera handle orbit/pan/look first.
		if _camera.handle_mouse_button(event):
			get_viewport().set_input_as_handled()
			return

		# Left click: place if pending, otherwise select/transform.
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var vp_pos: Vector2 = to_viewport_pos.call()
			if _pending_place_type:
				_place_part(vp_pos)
			else:
				_rect_drag_start = vp_pos
				_rect_current = vp_pos
				var additive := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
				_transform_tool.handle_click(vp_pos, additive)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _rect_dragging and not _pending_place_type:
				_finalize_rect_selection()
			_rect_dragging = false
			_rect_drag_start = Vector2.INF
			_selection_rect.visible = false
			if _angle_input_active:
				_cancel_angle_input()
			_transform_tool.handle_drag_end()
			get_viewport().set_input_as_handled()

	# --- Mouse motion events ---
	elif event is InputEventMouseMotion:
		# Track if mouse is over viewport for camera look handling.
		_camera.set_mouse_over_viewport(mouse_in_viewport)

		# Let camera handle orbit/pan/look first.
		if _camera.handle_mouse_motion(event):
			get_viewport().set_input_as_handled()

		# Update ghost position while placing (always, even when not dragging).
		if _ghost_node and _ghost_node.is_inside_tree() and mouse_in_viewport:
			_update_ghost_position(to_viewport_pos.call(), event.relative)

		# Rectangle selection drag — only when nothing is already selected
		if _rect_drag_start != Vector2.INF and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _pending_place_type and _selection_manager.selected.is_empty():
			var vp_pos: Vector2 = to_viewport_pos.call()
			var drag_dist := (vp_pos - _rect_drag_start).length()
			if drag_dist > 5.0:
				_rect_dragging = true
				_rect_current = vp_pos
				_update_rect_visual()

		# Drag-transform only in select/move/rotate mode (not while placing)
		# Skip mouse rotation when angle typing is active (frozen)
		if not _pending_place_type and not _rect_dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and mouse_in_viewport:
			if not _angle_input_active:
				var cur: Vector2 = to_viewport_pos.call()
				var start: Vector2 = cur - event.relative
				_transform_tool.handle_drag(start, cur, _viewport.size)

	# --- Key events ---
	elif event is InputEventKey:
		if _camera.handle_key(event):
			get_viewport().set_input_as_handled()
			return

		# --- Angle typing during rotation drag ---
		if _transform_tool.is_dragging and _transform_tool.mode == TransformTool.TransformMode.ROTATE:
			if not _angle_input_active and _is_angle_input_digit(event):
				_start_angle_input()
			if _angle_input_active and event.pressed and not event.is_echo():
				if _handle_angle_input_key(event):
					get_viewport().set_input_as_handled()
					return

		# V key: toggle Y-axis mode (works while placing the ghost or in Move mode).
		if event.keycode == KEY_V and event.pressed and not event.is_echo():
			if _pending_place_type and _ghost_node:
				_ghost_y_mode = not _ghost_y_mode
				_status_bar.set_status("Placement axis: " + ("Y" if _ghost_y_mode else "XZ"))
				get_viewport().set_input_as_handled()
			elif _transform_tool.mode == TransformTool.TransformMode.MOVE:
				_transform_tool.toggle_move_y()
				_update_axis_indicator(_transform_tool.move_axis_lock)
				get_viewport().set_input_as_handled()

		# X/Y/Z keys: axis lock for Move/Rotate (ignored if Ctrl/Cmd pressed for shortcuts)
		# Also ignored during angle typing to avoid axis changes mid-input
		if event.pressed and not event.is_echo() and not event.ctrl_pressed and not event.meta_pressed and not _angle_input_active:
			var axis_key := ""
			match event.keycode:
				KEY_X: axis_key = "x"
				KEY_Y: axis_key = "y"
				KEY_Z: axis_key = "z"
			if axis_key != "":
				if _transform_tool.mode == TransformTool.TransformMode.MOVE:
					if _transform_tool.move_axis_lock == axis_key:
						_transform_tool.clear_move_axis_lock()
					else:
						_transform_tool.set_move_axis_lock(axis_key)
					_update_axis_indicator(_transform_tool.move_axis_lock)
					get_viewport().set_input_as_handled()
				elif _transform_tool.mode == TransformTool.TransformMode.ROTATE:
					if _transform_tool.rotate_axis_lock == axis_key:
						_transform_tool.clear_rotate_axis_lock()
					else:
						_transform_tool.set_rotate_axis_lock(axis_key)
					_update_axis_indicator(_transform_tool.rotate_axis_lock)
					get_viewport().set_input_as_handled()

	# --- Pinch gesture (trackpad 2-finger zoom) ---
	elif event is InputEventMagnifyGesture:
		if _camera.handle_pinch(event):
			get_viewport().set_input_as_handled()


func _place_part(viewport_pos: Vector2) -> void:
	# The ghost already tracks the mouse (including Y offset with V),
	# so place exactly where the ghost is.
	var spawn_pos := Vector3(0.0, 1.0, 0.0)
	if _ghost_node and _ghost_node.is_inside_tree():
		spawn_pos = _ghost_node.position
	else:
		var ray_origin := _camera.project_ray_origin(viewport_pos)
		var ray_dir := _camera.project_ray_normal(viewport_pos)
		var plane := Plane(Vector3.UP, 0.0)
		var intersection = plane.intersects_ray(ray_origin, ray_dir)
		if intersection:
			spawn_pos = intersection
			spawn_pos.y = 1.0
			if _grid_system.enabled:
				spawn_pos = _grid_system.snap_position(spawn_pos)
				spawn_pos.y = maxf(spawn_pos.y, 1.0)

	var scene_path: String = SceneRegistry.get_scene_path(_pending_place_type)
	if scene_path.is_empty():
		return

	var scene: PackedScene = load(scene_path)
	if not scene:
		return

	var node: Node3D = scene.instantiate()
	node.name = _unique_name(_pending_place_type)
	node.position = spawn_pos

	# Create undo action for placement
	RuntimeUndoRedo.create_action("Place Part")
	RuntimeUndoRedo.add_do_reference(node)  # Add node on redo
	# Undo: remove the node
	RuntimeUndoRedo.add_undo_method(_scene_root_3d, "remove_child", node)
	RuntimeUndoRedo.add_undo_method(node, "queue_free")

	_scene_root_3d.add_child(node)
	node.owner = _scene_root_3d

	RuntimeUndoRedo.commit_action()

	_scene_manager.mark_modified()
	_selection_manager.deselect_all()
	_selection_manager.select(node)
	_status_bar.set_status("Placed: " + _pending_place_type)

	_remove_ghost()


func _update_ghost_position(vp_pos: Vector2, mouse_relative: Vector2 = Vector2.ZERO) -> void:
	if not _ghost_node or not _ghost_node.is_inside_tree():
		return

	if _ghost_y_mode:
		# Vertical mouse movement adjusts height; XZ stays fixed.
		_ghost_y_offset = maxf(_ghost_y_offset - mouse_relative.y * 0.01, 0.0)
		var pos := _ghost_node.position
		pos.y = _ghost_y_offset
		_ghost_node.position = pos
		return

	var ray_origin := _camera.project_ray_origin(vp_pos)
	var ray_dir := _camera.project_ray_normal(vp_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	if intersection:
		var pos: Vector3 = intersection
		pos.y = 1.0
		if _grid_system.enabled:
			pos = _grid_system.snap_position(pos)
			pos.y = maxf(pos.y, 1.0)
		pos.y += _ghost_y_offset
		_ghost_node.position = pos


func _cancel_placement() -> void:
	_remove_ghost()
	_status_bar.set_status("Placement cancelled")


func _remove_ghost() -> void:
	if _ghost_node and _ghost_node.is_inside_tree():
		_ghost_node.queue_free()
	_ghost_node = null
	_pending_place_type = ""
	_ghost_y_mode = false
	_ghost_y_offset = 0.0


func _unique_name(type_name: String) -> String:
	var count := 0
	for child in _scene_root_3d.get_children():
		if child.name.begins_with(type_name):
			count += 1
	if count == 0:
		return type_name
	return type_name + str(count + 1)


static func _apply_ghost_material(node: Node) -> void:
	# Recursively make every mesh semi-transparent green-ish to indicate "ghost".
	for child in node.get_children():
		_apply_ghost_material(child)
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		# Overlay material via material_override so we don't mutate the shared mesh resource.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 1.0, 0.5, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		mi.material_override = mat


func _on_new() -> void:
	_scene_manager.new_scene(_scene_root_3d)
	_selection_manager.deselect_all()
	_comms_panel.set_scene_root(_scene_root_3d)
	_status_bar.set_status("New scene")


func _on_selection_changed(selected: Array[Node3D]) -> void:
	_status_bar.set_parts_count(_scene_root_3d.get_child_count())
	_camera.set_suppress_motion(not selected.is_empty())
	_update_axis_indicator(_transform_tool.move_axis_lock)
	_comms_panel.set_selection(selected)


func _on_toggle_left_panel() -> void:
	var left := get_node_or_null("VBox/MainArea/LeftPanel")
	if left:
		left.visible = not left.visible


func _on_toggle_right_panel() -> void:
	var right := get_node_or_null("VBox/MainArea/RightPanel")
	if right:
		right.visible = not right.visible


func _on_toggle_comms_panel() -> void:
	var is_showing_comms := _comms_panel.visible
	_comms_panel.visible = not is_showing_comms
	$VBox.visible = is_showing_comms


func _on_toggle_status_bar() -> void:
	if _status_bar:
		_status_bar.visible = not _status_bar.visible


func _on_open() -> void:
	_file_dialogs.open_file_dialog()


func _on_save() -> void:
	_file_dialogs.save_scene_direct()


func _on_play() -> void:
	# Play button: start if stopped, resume if paused, pause if running
	if not RuntimeSimulationBus.is_simulation_running():
		_simulation_controller.start_simulation()
	elif RuntimeSimulationBus.is_simulation_paused():
		_simulation_controller.resume_simulation()
	else:
		_simulation_controller.pause_simulation()
	
	var running := RuntimeSimulationBus.is_simulation_running()
	var paused := RuntimeSimulationBus.is_simulation_paused()
	_toolbar.set_simulation_running(running)
	if paused:
		_toolbar.set_simulation_paused(true)
	_status_bar.set_status("Simulation Running" if running and not paused else "Simulation Paused" if paused else "Simulation Stopped")


func _on_pause() -> void:
	# Pause button: only works when running (not paused)
	if RuntimeSimulationBus.is_simulation_running() and not RuntimeSimulationBus.is_simulation_paused():
		_simulation_controller.pause_simulation()
		_toolbar.set_simulation_paused(true)
		_status_bar.set_status("Simulation Paused")


func _on_stop() -> void:
	# Stop button: always stops and restores initial state
	if RuntimeSimulationBus.is_simulation_running():
		_simulation_controller.stop_simulation()
		_toolbar.set_simulation_running(false)
		_status_bar.set_status("Simulation Stopped")


func _on_undo() -> void:
	RuntimeUndoRedo._undo_redo.undo()
	_simulation_controller.refresh_initial_state()
	_status_bar.set_status("Undo")


func _on_redo() -> void:
	RuntimeUndoRedo._undo_redo.redo()
	_simulation_controller.refresh_initial_state()
	_status_bar.set_status("Redo")


func _on_select_mode() -> void:
	_input_manager.set_mode(InputManager.ToolMode.SELECT)
	_transform_tool.set_mode(TransformTool.TransformMode.SELECT)


func _on_move_mode() -> void:
	_input_manager.set_mode(InputManager.ToolMode.MOVE)
	_transform_tool.set_mode(TransformTool.TransformMode.MOVE)


func _on_rotate_mode() -> void:
	_input_manager.set_mode(InputManager.ToolMode.ROTATE)
	_transform_tool.set_mode(TransformTool.TransformMode.ROTATE)
	_update_axis_indicator(_transform_tool.move_axis_lock)


func _on_rotate_exact(angle_deg: float) -> void:
	if _transform_tool.mode != TransformTool.TransformMode.ROTATE:
		return
	var selected := _selection_manager.selected
	if selected.is_empty():
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Rotación exacta (grados)"
	var spin := SpinBox.new()
	spin.min_value = -360.0
	spin.max_value = 360.0
	spin.step = 1.0
	spin.value = angle_deg if angle_deg != 0.0 else 90.0
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.add_child(spin)
	dialog.get_ok_button().text = "Aplicar"
	dialog.confirmed.connect(func():
		var angle := deg_to_rad(spin.value)
		_transform_tool.handle_rotate(angle)
		_update_axis_indicator(_transform_tool.move_axis_lock)
		_status_bar.set_status("Rotado %.0f°" % spin.value)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	spin.grab_focus()
	spin.select_all()


func _on_rotation_dragging(angle_deg: float, axis: String) -> void:
	_status_bar.set_status("Rotando %s: %.1f°" % [axis.to_upper(), angle_deg])
	_status_bar.set_rotation_angle(angle_deg)
	# Also update axis indicator label if it shows angle
	if _axis_indicator:
		_axis_indicator.set_rotation_angle(angle_deg)


func _update_axis_indicator(axis_lock: String) -> void:
	if not _axis_indicator:
		return
	_status_bar.set_axis(axis_lock if _transform_tool.mode != TransformTool.TransformMode.SELECT else "")
	if _selection_manager.selected.is_empty():
		_axis_indicator.hide_all()
		return
	# Position indicator at the selected node
	var primary := _selection_manager.primary_selection
	if primary:
		_axis_indicator.set_track_node(primary)
	match _transform_tool.mode:
		TransformTool.TransformMode.MOVE:
			if axis_lock != "":
				_axis_indicator.show_axis(axis_lock)
			else:
				_axis_indicator.hide_all()
		TransformTool.TransformMode.ROTATE:
			_axis_indicator.show_rotate(axis_lock)
		_:
			_axis_indicator.hide_all()


func _on_snap_toggled() -> void:
	_grid_system.toggle()
	_status_bar.set_status("Grid: " + ("ON" if _grid_system.enabled else "OFF"))


func _on_rotation_snap_changed(angle_deg: int) -> void:
	_grid_system.rotation_snap_deg = float(angle_deg)
	if angle_deg == 0:
		_status_bar.set_status("Rotación: Snap OFF")
	else:
		_status_bar.set_status("Rotación: Snap %d°" % angle_deg)


func _on_delete() -> void:
	var selected := _selection_manager.selected
	for node in selected:
		_clipboard_manager.delete(node)
	_selection_manager.deselect_all()
	_scene_manager.mark_modified()
	_status_bar.set_status("Deleted")


func _on_copy() -> void:
	var primary := _selection_manager.primary_selection
	if primary:
		_clipboard_manager.copy(primary)


func _on_paste() -> void:
	var pasted := _clipboard_manager.paste(_scene_root_3d)
	if pasted:
		_selection_manager.deselect_all()
		_selection_manager.select(pasted)
		_scene_manager.mark_modified()


func _on_duplicate() -> void:
	var primary := _selection_manager.primary_selection
	if primary:
		var dup := _clipboard_manager.duplicate(primary)
		if dup:
			_selection_manager.deselect_all()
			_selection_manager.select(dup)
			_scene_manager.mark_modified()


func _on_focus() -> void:
	_camera.focus_selected()


func _on_cancel() -> void:
	if _pending_place_type:
		_cancel_placement()
	else:
		_selection_manager.deselect_all()


func _on_part_selected(type_name: String) -> void:
	# If a placement is already in progress, finalize it first.
	if _pending_place_type:
		_remove_ghost()

	# Entering placement mode means we also want the camera to stay still
	# (and definitely not be locked from a previous selection).
	_selection_manager.deselect_all()

	_pending_place_type = type_name
	_status_bar.set_status("Move mouse over viewport, click to place: " + type_name + " (Right-click to cancel)")

	var scene_path: String = SceneRegistry.get_scene_path(type_name)
	if scene_path.is_empty():
		return
	var scene: PackedScene = load(scene_path)
	if scene:
		_ghost_node = scene.instantiate()
		_apply_ghost_material(_ghost_node)
		# Spawn slightly above the ground so the part doesn't sink into the floor.
		_ghost_node.position = Vector3(0.0, 1.0, 0.0)
		_scene_root_3d.add_child(_ghost_node)
		# Try to position under the cursor right now if mouse is over the viewport.
		var rect: Rect2 = _viewport_3d.get_global_rect()
		if rect.has_point(get_viewport().get_mouse_position()):
			var vp_pos: Vector2 = get_viewport().get_mouse_position() - rect.position
			vp_pos *= _viewport_3d.stretch_shrink
			_update_ghost_position(vp_pos)



func _update_rect_visual() -> void:
	if _rect_drag_start == Vector2.INF or not _selection_rect:
		return
	var rect := Rect2(_rect_drag_start, _rect_current - _rect_drag_start)
	rect = rect.abs()
	_selection_rect.global_position = _viewport_3d.global_position + rect.position
	_selection_rect.size = rect.size
	_selection_rect.visible = rect.size.length() > 5.0
	var mat: CanvasItemMaterial = _selection_rect.material as CanvasItemMaterial
	if mat == null:
		mat = CanvasItemMaterial.new()
		_selection_rect.material = mat
	mat.particles_animation = 0


func _finalize_rect_selection() -> void:
	if _rect_drag_start == Vector2.INF:
		return
	var rect := Rect2(_rect_drag_start, _rect_current - _rect_drag_start).abs()
	if rect.size.length() < 5.0:
		return
	var additive := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	_select_nodes_in_rect(rect, additive)


func _select_nodes_in_rect(screen_rect: Rect2, additive: bool) -> void:
	var to_exclude := _selection_manager.selected.duplicate()
	var to_select: Array[Node3D] = []
	var _vp_size: Vector2 = _viewport.size
	for child in _scene_root_3d.get_children():
		if child is Node3D and not to_exclude.has(child):
			var pos_2d := _camera.unproject_position(child.global_position)
			if screen_rect.has_point(pos_2d):
				to_select.append(child)
	if not additive:
		_selection_manager.deselect_all()
	for node in to_select:
		_selection_manager.select(node, true)
	if to_select.size() > 0:
		var label := "Selected %d part" % to_select.size()
		if to_select.size() > 1:
			label += "s"
		_status_bar.set_status(label)


func _show_context_menu() -> void:
	var menu := PopupMenu.new()
	menu.add_item("Delete", 1)
	menu.add_item("Copy", 2)
	menu.add_item("Paste", 3)
	menu.add_item("Duplicate", 4)
	menu.add_separator()
	menu.add_item("Group", 5)
	menu.add_item("Ungroup", 6)
	menu.id_pressed.connect(_on_context_menu_id)
	add_child(menu)
	var mouse_global := get_viewport().get_mouse_position()
	menu.set_position(mouse_global)
	menu.size = Vector2(180, 200)
	menu.visible = true
	menu.tree_exiting.connect(func(): menu.queue_free())


func _on_context_menu_id(id: int) -> void:
	match id:
		1: _on_delete()
		2: _on_copy()
		3: _on_paste()
		4: _on_duplicate()
		5: _on_group()
		6: _on_ungroup()


func _on_group() -> void:
	var selected := _selection_manager.selected
	if selected.size() < 2:
		_status_bar.set_status("Select 2+ parts to group")
		return
	var group := Node3D.new()
	group.name = "Group"
	_scene_root_3d.add_child(group)
	group.owner = _scene_root_3d
	for node in selected:
		var old_parent := node.get_parent()
		old_parent.remove_child(node)
		group.add_child(node)
		node.owner = _scene_root_3d
	_selection_manager.deselect_all()
	_selection_manager.select(group)
	_scene_manager.mark_modified()
	_status_bar.set_status("Grouped %d parts" % selected.size())


func _on_ungroup() -> void:
	var selected := _selection_manager.selected.duplicate()
	if selected.is_empty():
		return
	var ungrouped := 0
	for node in selected:
		if node.get_child_count() == 0:
			continue
		var group_parent: Node3D = node.get_parent() as Node3D
		var children: Array[Node] = node.get_children()
		for child in children:
			node.remove_child(child)
			group_parent.add_child(child)
			child.owner = _scene_root_3d
			ungrouped += 1
		group_parent.remove_child(node)
		group_parent.queue_free()
		_selection_manager.deselect(node)
	if ungrouped > 0:
		_scene_manager.mark_modified()
		_status_bar.set_status("Ungrouped %d parts" % ungrouped)


func _on_scene_loaded(path: String) -> void:
	_status_bar.set_status("Loaded: " + path.get_file())
	_selection_manager.deselect_all()
	_comms_panel.set_scene_root(_scene_root_3d)


func _on_scene_saved(path: String) -> void:
	_status_bar.set_status("Saved: " + path.get_file())


# --- Angle typing during rotation drag ---

func _start_angle_input() -> void:
	if _angle_input_active:
		return
	_angle_input_active = true
	_angle_input_buffer = ""
	_angle_input_axis = _transform_tool.rotate_axis_lock if _transform_tool.rotate_axis_lock != "" else "y"
	_angle_input_frozen_rot = Vector3.ZERO
	var selected := _selection_manager.selected
	if not selected.is_empty():
		_angle_input_frozen_rot = selected[0].rotation


func _cancel_angle_input() -> void:
	if not _angle_input_active:
		return
	# Restore frozen rotation
	var selected := _selection_manager.selected
	for node in selected:
		node.rotation = _angle_input_frozen_rot
	_angle_input_active = false
	_angle_input_buffer = ""
	_status_bar.set_angle_input("")


func _confirm_angle_input() -> void:
	if not _angle_input_active:
		return
	var angle_val := _angle_input_buffer.to_float()
	_angle_input_active = false
	_angle_input_buffer = ""
	_status_bar.set_angle_input("")
	# Apply the typed angle
	var angle_rad := deg_to_rad(angle_val)
	_transform_tool.handle_rotate(angle_rad)
	_status_bar.set_status("Rotado %.1f°" % angle_val)


func _handle_angle_input_key(event: InputEventKey) -> bool:
	var code := event.keycode

	# Enter: confirm
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		if _angle_input_buffer.is_empty() or _angle_input_buffer == "-":
			_cancel_angle_input()
		else:
			_confirm_angle_input()
		return true

	# Escape: cancel
	if code == KEY_ESCAPE:
		_cancel_angle_input()
		return true

	# Backspace: delete last char
	if code == KEY_BACKSPACE:
		if _angle_input_buffer.length() > 0:
			_angle_input_buffer = _angle_input_buffer.left(-1)
		if _angle_input_buffer.is_empty() or _angle_input_buffer == "-":
			# Restore frozen rotation
			var selected := _selection_manager.selected
			for node in selected:
				node.rotation = _angle_input_frozen_rot
			_status_bar.set_angle_input("")
		else:
			# Live preview with the typed value
			_apply_angle_preview()
			_status_bar.set_angle_input(_angle_input_buffer + "°")
		return true

	# Digit keys (top row and numpad)
	var digit := -1
	match code:
		KEY_0, KEY_KP_0: digit = 0
		KEY_1, KEY_KP_1: digit = 1
		KEY_2, KEY_KP_2: digit = 2
		KEY_3, KEY_KP_3: digit = 3
		KEY_4, KEY_KP_4: digit = 4
		KEY_5, KEY_KP_5: digit = 5
		KEY_6, KEY_KP_6: digit = 6
		KEY_7, KEY_KP_7: digit = 7
		KEY_8, KEY_KP_8: digit = 8
		KEY_9, KEY_KP_9: digit = 9
		KEY_MINUS, KEY_KP_SUBTRACT:
			if _angle_input_buffer.is_empty():
				_angle_input_buffer = "-"
				_status_bar.set_angle_input("-°")
			return true
		KEY_PERIOD, KEY_KP_PERIOD:
			if not _angle_input_buffer.contains("."):
				if _angle_input_buffer.is_empty():
					_angle_input_buffer = "0."
				else:
					_angle_input_buffer += "."
				_status_bar.set_angle_input(_angle_input_buffer + "°")
			return true

	if digit >= 0:
		_angle_input_buffer += str(digit)
		_apply_angle_preview()
		_status_bar.set_angle_input(_angle_input_buffer + "°")
		return true

	return false


func _apply_angle_preview() -> void:
	if _angle_input_buffer.is_empty() or _angle_input_buffer == "-":
		return
	var angle_val := _angle_input_buffer.to_float()
	var selected := _selection_manager.selected
	for node in selected:
		var rot := _angle_input_frozen_rot
		match _angle_input_axis:
			"x": rot.x = deg_to_rad(angle_val)
			"y": rot.y = deg_to_rad(angle_val)
			"z": rot.z = deg_to_rad(angle_val)
		node.rotation = rot


func _is_angle_input_digit(event: InputEventKey) -> bool:
	if not event.pressed or event.is_echo():
		return false
	match event.keycode:
		KEY_0, KEY_KP_0, KEY_1, KEY_KP_1, KEY_2, KEY_KP_2, KEY_3, KEY_KP_3:
			return true
		KEY_4, KEY_KP_4, KEY_5, KEY_KP_5, KEY_6, KEY_KP_6, KEY_7, KEY_KP_7:
			return true
		KEY_8, KEY_KP_8, KEY_9, KEY_KP_9:
			return true
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_PERIOD, KEY_KP_PERIOD:
			return true
	return false
