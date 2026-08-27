class_name InputManager
extends Node

enum ToolMode { SELECT, MOVE, ROTATE }

signal tool_mode_changed(mode: ToolMode)
signal undo_requested
signal redo_requested
signal save_requested
signal open_requested
signal new_scene_requested
signal delete_requested
signal copy_requested
signal paste_requested
signal duplicate_requested
signal focus_requested
signal toggle_grid_requested
signal conveyor_snap_requested
signal simulation_toggle_requested
signal cancel_requested
signal group_requested
signal ungroup_requested
signal rotate_exact_requested(angle_deg: float)

var _current_mode: ToolMode = ToolMode.SELECT

var current_mode: ToolMode:
	get:
		return _current_mode


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.is_echo():
		return

	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	var shift: bool = event.shift_pressed

	match event.keycode:
		KEY_Q:
			_set_mode(ToolMode.SELECT)
		KEY_W:
			_set_mode(ToolMode.MOVE)
		KEY_R:
			_set_mode(ToolMode.ROTATE)
		KEY_R when shift:
			rotate_exact_requested.emit(0.0)  # 0 = trigger dialog
		KEY_G:
			toggle_grid_requested.emit()
		KEY_DELETE:
			delete_requested.emit()
		KEY_ESCAPE:
			cancel_requested.emit()
		KEY_F5:
			simulation_toggle_requested.emit()
		KEY_Z when ctrl and not shift:
			undo_requested.emit()
		KEY_Y when ctrl:
			redo_requested.emit()
		KEY_S when ctrl and not shift:
			save_requested.emit()
		KEY_S when ctrl and shift:
			conveyor_snap_requested.emit()
		KEY_O when ctrl:
			open_requested.emit()
		KEY_N when ctrl:
			new_scene_requested.emit()
		KEY_C when ctrl:
			copy_requested.emit()
		KEY_V when ctrl:
			paste_requested.emit()
		KEY_D when ctrl:
			duplicate_requested.emit()
		KEY_G when ctrl and not shift:
			group_requested.emit()
		KEY_G when ctrl and shift:
			ungroup_requested.emit()


func _set_mode(mode: ToolMode) -> void:
	if _current_mode != mode:
		_current_mode = mode
		tool_mode_changed.emit(mode)


func get_mode_name(mode: ToolMode) -> String:
	match mode:
		ToolMode.SELECT:
			return "Select"
		ToolMode.MOVE:
			return "Move"
		ToolMode.ROTATE:
			return "Rotate"
	return ""


func set_mode(mode: ToolMode) -> void:
	_set_mode(mode)
