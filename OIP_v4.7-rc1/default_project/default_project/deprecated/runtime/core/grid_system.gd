class_name GridSystem
extends Node3D

const GRID_SIZE_DEFAULT: float = 1.0
const GRID_SIZE_MIN: float = 0.25
const GRID_SIZE_MAX: float = 5.0
const GRID_EXTENT: float = 50.0
const ROTATION_SNAP_DEG_DEFAULT: float = 15.0

var _enabled: bool = true
var _grid_size: float = GRID_SIZE_DEFAULT
var _rotation_snap_deg: float = ROTATION_SNAP_DEG_DEFAULT
var _grid_mesh: ImmediateMesh
var _grid_instance: RID
var _grid_material: StandardMaterial3D

var enabled: bool:
	get:
		return _enabled
	set(value):
		_enabled = value
		_update_grid_visibility()

var grid_size: float:
	get:
		return _grid_size
	set(value):
		_grid_size = clamp(value, GRID_SIZE_MIN, GRID_SIZE_MAX)
		_rebuild_grid()

var rotation_snap_deg: float:
	get:
		return _rotation_snap_deg
	set(value):
		_rotation_snap_deg = clamp(value, 0.0, 180.0)


func _ready() -> void:
	_grid_mesh = ImmediateMesh.new()
	_grid_material = StandardMaterial3D.new()
	_grid_material.albedo_color = Color(0.4, 0.4, 0.4, 0.3)
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_material.no_depth_test = true
	_grid_material.render_priority = -10

	_grid_instance = RenderingServer.instance_create()
	RenderingServer.instance_set_scenario(_grid_instance, get_world_3d().scenario)
	RenderingServer.instance_set_base(_grid_instance, _grid_mesh)

	_rebuild_grid()


func _exit_tree() -> void:
	RenderingServer.free_rid(_grid_instance)


func toggle() -> void:
	enabled = not enabled


func snap_position(pos: Vector3) -> Vector3:
	if not _enabled:
		return pos
	return Vector3(
		snappedf(pos.x, _grid_size),
		pos.y,
		snappedf(pos.z, _grid_size),
	)


func snap_rotation_y(angle: float) -> float:
	if not _enabled:
		return angle
	return snappedf(angle, deg_to_rad(_rotation_snap_deg))


func snap_position_grid(pos: Vector3, size: float) -> Vector3:
	if not _enabled:
		return pos
	return Vector3(
		snappedf(pos.x, size),
		pos.y,
		snappedf(pos.z, size),
	)


func _rebuild_grid() -> void:
	_grid_mesh.clear_surfaces()

	var half := GRID_EXTENT
	var step := _grid_size
	var major_step := step * 5.0

	_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _grid_material)

	var x := -half
	while x <= half + 0.001:
		var alpha := 0.15 if fmod(abs(x), major_step) > 0.001 else 0.4
		_grid_mesh.surface_set_color(Color(0.5, 0.5, 0.5, alpha))
		_grid_mesh.surface_add_vertex(Vector3(x, 0, -half))
		_grid_mesh.surface_set_color(Color(0.5, 0.5, 0.5, alpha))
		_grid_mesh.surface_add_vertex(Vector3(x, 0, half))
		x += step

	var z := -half
	while z <= half + 0.001:
		var alpha := 0.15 if fmod(abs(z), major_step) > 0.001 else 0.4
		_grid_mesh.surface_set_color(Color(0.5, 0.5, 0.5, alpha))
		_grid_mesh.surface_add_vertex(Vector3(-half, 0, z))
		_grid_mesh.surface_set_color(Color(0.5, 0.5, 0.5, alpha))
		_grid_mesh.surface_add_vertex(Vector3(half, 0, z))
		z += step

	_grid_mesh.surface_end()


func _update_grid_visibility() -> void:
	RenderingServer.instance_set_visible(_grid_instance, _enabled)
