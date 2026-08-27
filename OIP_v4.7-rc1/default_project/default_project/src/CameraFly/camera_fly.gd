extends Camera3D

const BASE_SPEED: float = 5.0
const BOOST_MULTIPLIER: float = 3.0
const MOUSE_SENS: float = 0.003
const ZOOM_STEP: float = 1.1
const ZOOM_MIN: float = 15.0
const ZOOM_MAX: float = 120.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _speed: float = BASE_SPEED
var _move_input: Vector3 = Vector3.ZERO
var _boost: bool = false
var _looking: bool = false


func _ready() -> void:
	var euler := global_transform.basis.get_euler()
	_yaw = euler.y
	_pitch = euler.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			if _looking:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				fov = clampf(fov / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				fov = clampf(fov * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _looking:
		return
	_yaw -= event.relative.x * MOUSE_SENS
	_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)


func _handle_key(event: InputEventKey) -> void:
	if event.is_echo():
		return
	match event.keycode:
		KEY_W:
			_move_input.z = 1.0 if event.pressed else 0.0
		KEY_S:
			_move_input.z = -1.0 if event.pressed else 0.0
		KEY_A:
			_move_input.x = -1.0 if event.pressed else 0.0
		KEY_D:
			_move_input.x = 1.0 if event.pressed else 0.0
		KEY_SPACE:
			_move_input.y = 1.0 if event.pressed else 0.0
		KEY_CTRL:
			_move_input.y = -1.0 if event.pressed else 0.0
		KEY_SHIFT:
			_boost = event.pressed
		KEY_ESCAPE:
			if _looking:
				_looking = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var forward := -basis.z
	var right := basis.x

	var speed := _speed * (BOOST_MULTIPLIER if _boost else 1.0)
	var move_vec := forward * _move_input.z + right * _move_input.x + Vector3.UP * _move_input.y

	if move_vec.length_squared() > 0.0:
		global_position += move_vec.normalized() * speed * delta

	global_transform = Transform3D(basis, global_position)
