class_name PanelResizer
extends Control

enum Side { LEFT, RIGHT }

@export var side: int = 0
@export var target_path: NodePath
@export var min_width: float = 160.0
@export var max_width: float = 600.0

var _target: Control = null
var _dragging: bool = false
var _drag_start_x: float = 0.0
var _initial_size: float = 0.0


func _ready() -> void:
	custom_minimum_size.x = 6.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE

	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.17, 0.2, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var hover_bg := ColorRect.new()
	hover_bg.name = "HoverBG"
	hover_bg.color = Color(0.3, 0.5, 0.8, 0.6)
	hover_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hover_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_bg.visible = false
	add_child(hover_bg)


func _enter_tree() -> void:
	if target_path:
		_target = get_node_or_null(target_path)
	if not _target:
		_target = get_parent()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start_x = event.global_position.x
				_initial_size = _target.custom_minimum_size.x
			else:
				_end_drag()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _dragging:
		# Failsafe: if the release happened outside and another control
		# consumed it, let go as soon as the button is no longer pressed.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_end_drag()
			return
		var delta: float = event.global_position.x - _drag_start_x
		if side == Side.RIGHT:
			delta = -delta
		var new_size: float = clampf(_initial_size + delta, min_width, max_width)
		_target.custom_minimum_size.x = new_size
		_target.size.x = new_size


func _input(event: InputEvent) -> void:
	# The release can be consumed by other nodes (e.g. the 3D viewport marks
	# left-button releases as handled), so listen globally while dragging to
	# never get stuck in drag mode.
	if _dragging and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()


func _end_drag() -> void:
	_dragging = false
	# Clear the hover highlight if the cursor is no longer over the resizer
	# (MOUSE_EXIT was suppressed while dragging).
	if not get_global_rect().has_point(get_global_mouse_position()):
		var hb := get_node_or_null("HoverBG")
		if hb:
			hb.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		var hb := get_node_or_null("HoverBG")
		if hb:
			hb.visible = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		if not _dragging:
			var hb := get_node_or_null("HoverBG")
			if hb:
				hb.visible = false
