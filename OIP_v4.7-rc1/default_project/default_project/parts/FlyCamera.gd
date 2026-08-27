extends Camera3D

@export var move_speed: float = 5.0
@export var look_sensitivity: float = 0.003
@export var fast_multiplier: float = 3.0

var _rot_x: float = 0.0
var _rot_y: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_process_unhandled_input(false)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var euler := global_transform.basis.get_euler()
	_rot_x = euler.y
	_rot_y = euler.x


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion:
		_rot_x -= event.relative.x * look_sensitivity
		_rot_y -= event.relative.y * look_sensitivity
		_rot_y = clampf(_rot_y, -PI * 0.49, PI * 0.49)
		global_transform.basis = Basis.from_euler(Vector3(_rot_y, _rot_x, 0))
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP

	if dir.length_squared() > 0:
		global_position += dir.normalized() * speed * delta
