class_name ViewportCamera
extends Camera3D

## FPS-style camera with two modes (Factory I/O style):
##  - WALK (default): WASD + right-click look, Space up, Ctrl down, Shift boost
##  - FLY: same as WALK but Y is free (no gravity lock)
## Keys: B=toggle walk/fly, F=focus, 1-5=preset views

enum Mode { WALK, FLY }

signal mode_changed(mode_name: String)

const FLY_SPEED: float = 8.0
const FLY_BOOST: float = 4.0
const WALK_HEIGHT: float = 1.7
const MOUSE_LOOK_SENS: float = 0.0025
const DEFAULT_FOV: float = 90.0
const ZOOM_MIN_FOV: float = 15.0
const ZOOM_MAX_FOV: float = 120.0
const ZOOM_STEP: float = 1.15

var _mode: Mode = Mode.WALK
var _yaw: float = 0.0
var _pitch: float = 0.0
var _speed: float = FLY_SPEED
var _move_input: Vector3 = Vector3.ZERO
var _boost: bool = false
var _is_looking: bool = false
var _suppress_right_click: bool = false
var _suppress_motion: bool = false  # When true, no orbit/pan/WASD — selection mode active.


func _ready() -> void:
	# Start at a good position looking at the origin.
	global_position = Vector3(0.0, WALK_HEIGHT, 20.0)
	_yaw = PI  # look toward -Z (toward origin)
	_pitch = -0.1
	fov = DEFAULT_FOV
	_apply_transform()

# Track if mouse is over viewport
var _mouse_over_viewport: bool = false


func set_mouse_over_viewport(over: bool) -> void:
	_mouse_over_viewport = over
	if not over:
		_is_looking = false
		_move_input = Vector3.ZERO


func set_mode(m: Mode) -> void:
	if _mode == m:
		return
	_is_looking = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mode = m
	_move_input = Vector3.ZERO
	mode_changed.emit(get_mode_name())


func get_mode_name() -> String:
	match _mode:
		Mode.WALK: return "Walk"
		Mode.FLY: return "Fly"
	return ""


func set_suppress_right_click(value: bool) -> void:
	_suppress_right_click = value


## When a part is selected, the editor calls this with `true` so the camera
## stops responding to right-drag/look and WASD until the user deselects.
func set_suppress_motion(value: bool) -> void:
	_suppress_motion = value
	if value:
		_is_looking = false
		_move_input = Vector3.ZERO
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func handle_mouse_button(event: InputEventMouseButton) -> bool:
	# Wheel: zoom (FOV) when camera is free; still works when motion is
	# suppressed (selection mode). Shift+Wheel tunes fly speed instead.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		if event.shift_pressed:
			_speed = clampf(_speed * 1.25, 1.0, 200.0)
		else:
			fov = clampf(fov / ZOOM_STEP, ZOOM_MIN_FOV, ZOOM_MAX_FOV)
		return true
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		if event.shift_pressed:
			_speed = clampf(_speed / 1.25, 1.0, 200.0)
		else:
			fov = clampf(fov * ZOOM_STEP, ZOOM_MIN_FOV, ZOOM_MAX_FOV)
		return true

	# All non-wheel camera controls are blocked while motion is suppressed.
	if _suppress_motion:
		return false

	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			if _suppress_right_click:
				return false
			_is_looking = event.pressed
			if _is_looking:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return true
	return false


func handle_pinch(event: InputEventMagnifyGesture) -> bool:
	# Pinch-to-zoom on trackpad (2-finger pinch). Works even when motion is suppressed.
	if _suppress_motion:
		# In selection mode, only zoom is allowed
		fov = clampf(fov * event.factor, ZOOM_MIN_FOV, ZOOM_MAX_FOV)
		return true
	return false


func handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	if _suppress_motion:
		return false
	if not _mouse_over_viewport:
		return false
	if _is_looking:
		_yaw -= event.relative.x * MOUSE_LOOK_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_LOOK_SENS, -1.5, 1.5)
		return true
	return false


func handle_key(event: InputEventKey) -> bool:
	if event.is_echo():
		return false

	# Track movement keys only when camera is free to move.
	if not _suppress_motion:
		_update_move_input(event, event.pressed)
	elif event.pressed:
		# While suppressed, clear any held movement so it doesn't ramp up.
		_move_input = Vector3.ZERO

	if not event.pressed:
		return false

	# View presets and focus also disabled while selection-driven motion is off.
	if _suppress_motion:
		return false

	match event.keycode:
		KEY_F:
			focus_selected()
			return true
		KEY_1:
			_set_front_view()
			return true
		KEY_2:
			_set_back_view()
			return true
		KEY_3:
			_set_left_view()
			return true
		KEY_4:
			_set_right_view()
			return true
		KEY_5:
			_set_top_view()
			return true
		KEY_B:
			set_mode(Mode.FLY if _mode == Mode.WALK else Mode.WALK)
			return true
		KEY_ESCAPE:
			if _is_looking:
				_is_looking = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				return true
	return false


func _update_move_input(event: InputEventKey, pressed: bool) -> void:
	match event.keycode:
		KEY_W, KEY_UP:
			_move_input.z = 1.0 if pressed else 0.0
		KEY_S, KEY_DOWN:
			_move_input.z = -1.0 if pressed else 0.0
		KEY_A, KEY_LEFT:
			_move_input.x = -1.0 if pressed else 0.0
		KEY_D, KEY_RIGHT:
			_move_input.x = 1.0 if pressed else 0.0
		KEY_SPACE:
			_move_input.y = 1.0 if pressed else 0.0
		KEY_CTRL, KEY_Z:
			_move_input.y = -1.0 if pressed else 0.0
		KEY_SHIFT:
			_boost = pressed


func _process(delta: float) -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var forward := -basis.z
	var right := basis.x

	var speed := _speed * (FLY_BOOST if _boost else 1.0)
	var move_vec := forward * _move_input.z + right * _move_input.x

	if _mode == Mode.FLY:
		move_vec += Vector3.UP * _move_input.y

	if move_vec.length_squared() > 0.0:
		global_position += move_vec.normalized() * speed * delta

	if _mode == Mode.WALK:
		global_position.y = WALK_HEIGHT

	global_transform = Transform3D(basis, global_position)


func _apply_transform() -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_transform = Transform3D(basis, global_position)


func focus_selected() -> void:
	var selected := RuntimeSelection.get_selected_nodes()
	if selected.is_empty():
		return
	var center := Vector3.ZERO
	var count := 0
	for node in selected:
		if node is Node3D:
			center += (node as Node3D).global_position
			count += 1
	if count > 0:
		center /= count
	# Position camera in front of the target, looking at it.
	var dir := (center - global_position).normalized()
	global_position = center - dir * 5.0
	_yaw = atan2(-dir.x, -dir.z)
	_pitch = -asin(clampf(dir.y, -1.0, 1.0))
	_apply_transform()


func _set_front_view() -> void:
	global_position = Vector3(0.0, WALK_HEIGHT, 20.0)
	_yaw = PI
	_pitch = -0.1
	_apply_transform()


func _set_back_view() -> void:
	global_position = Vector3(0.0, WALK_HEIGHT, -20.0)
	_yaw = 0.0
	_pitch = -0.1
	_apply_transform()


func _set_left_view() -> void:
	global_position = Vector3(-20.0, WALK_HEIGHT, 0.0)
	_yaw = PI / 2.0
	_pitch = -0.1
	_apply_transform()


func _set_right_view() -> void:
	global_position = Vector3(20.0, WALK_HEIGHT, 0.0)
	_yaw = -PI / 2.0
	_pitch = -0.1
	_apply_transform()


func _set_top_view() -> void:
	global_position = Vector3(0.0, 25.0, 0.01)
	_yaw = 0.0
	_pitch = PI / 2.0 - 0.01
	_apply_transform()


func focus_point(point: Vector3, distance: float = 15.0) -> void:
	global_position = point + Vector3(0.0, distance * 0.5, distance)
	_yaw = atan2(-(point.x - global_position.x), -(point.z - global_position.z))
	_pitch = -0.3
	_apply_transform()
