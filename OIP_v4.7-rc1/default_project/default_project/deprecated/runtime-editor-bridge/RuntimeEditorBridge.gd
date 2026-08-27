@tool
extends EditorPlugin

## Bridges real EditorInterface simulation/selection/undo/toaster signals
## to the runtime stub autoloads so that part scripts using the stubs
## work identically in editor and exported builds.
##
## All EditorInterface hooks are connected dynamically by name so this
## script compiles on editor builds that lack the custom OIP signals.

var _editor_interface: Object = null


func _enter_tree() -> void:
	_editor_interface = Engine.get_singleton("EditorInterface")
	if _editor_interface == null:
		return

	# --- Simulation ---
	_safe_connect("simulation_started", _on_simulation_started)
	_safe_connect("simulation_stopped", _on_simulation_stopped)
	_safe_connect("simulation_pause_toggled", _on_simulation_pause_toggled)

	# --- Undo / Redo ---
	if _editor_interface.has_method("get_editor_undo_redo"):
		RuntimeUndoRedo.use_editor_undo_redo(_editor_interface.call("get_editor_undo_redo"))

	# --- Toaster ---
	if _editor_interface.has_method("get_editor_toaster"):
		RuntimeEditorToaster.set_editor_toaster(_editor_interface.call("get_editor_toaster"))

	# --- Selection ---
	var sel: Object = _get_selection()
	if sel:
		sel.selection_changed.connect(_on_selection_changed)
		_sync_selection()

	# --- Transform gizmo signals ---
	_safe_connect("transform_requested", _on_transform_requested)
	_safe_connect("transform_commited", _on_transform_commited)


func _exit_tree() -> void:
	if _editor_interface == null:
		return
	_safe_disconnect("simulation_started", _on_simulation_started)
	_safe_disconnect("simulation_stopped", _on_simulation_stopped)
	_safe_disconnect("simulation_pause_toggled", _on_simulation_pause_toggled)
	_safe_disconnect("transform_requested", _on_transform_requested)
	_safe_disconnect("transform_commited", _on_transform_commited)

	var sel: Object = _get_selection()
	if sel and sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)
	_editor_interface = null


func _safe_connect(signal_name: String, callable: Callable) -> void:
	if _editor_interface.has_signal(signal_name) and not _editor_interface.is_connected(signal_name, callable):
		_editor_interface.connect(signal_name, callable)


func _safe_disconnect(signal_name: String, callable: Callable) -> void:
	if _editor_interface.has_signal(signal_name) and _editor_interface.is_connected(signal_name, callable):
		_editor_interface.disconnect(signal_name, callable)


func _get_selection() -> Object:
	if _editor_interface != null and _editor_interface.has_method("get_selection"):
		return _editor_interface.call("get_selection")
	return null


func _on_transform_requested(args: Variant = null) -> void:
	if RuntimeEditorStub.has_signal("transform_requested"):
		if args == null:
			RuntimeEditorStub.transform_requested.emit()
		else:
			RuntimeEditorStub.transform_requested.emit(args)


func _on_transform_commited(args: Variant = null) -> void:
	if RuntimeEditorStub.has_signal("transform_commited"):
		if args == null:
			RuntimeEditorStub.transform_commited.emit()
		else:
			RuntimeEditorStub.transform_commited.emit(args)


func _on_simulation_started() -> void:
	if not RuntimeSimulationBus.is_simulation_running():
		RuntimeSimulationBus.start_simulation()


func _on_simulation_stopped() -> void:
	if RuntimeSimulationBus.is_simulation_running():
		RuntimeSimulationBus.stop_simulation()


func _on_simulation_pause_toggled(paused: bool) -> void:
	RuntimeSimulationBus.set_paused(paused)


func _on_selection_changed() -> void:
	_sync_selection()


func _sync_selection() -> void:
	var sel: Object = _get_selection()
	if not sel:
		return
	var nodes: Array = sel.call("get_selected_nodes")
	RuntimeSelection.select_nodes(nodes)
	var active_3d: Node3D = null
	for node in nodes:
		if node is Node3D:
			active_3d = node as Node3D
			break
	RuntimeSelection.set_active_node_3d(active_3d)
