@tool
class_name Celda
extends Node3D

## Initial velocity applied to this celda when simulation starts.
@export var initial_linear_velocity: Vector3 = Vector3.ZERO

var _initial_transform: Transform3D
var _paused: bool = false
var instanced: bool = false
var _enable_initial_transform: bool = false
var _in_composite: bool = false


## When true the part is frozen and collision-disabled inside a Sandwich
## composite; its Simulation callbacks become no-ops so the sled drives it.
func set_composite_mode(composite: bool) -> void:
	if _in_composite == composite:
		return
	_in_composite = composite
	var body := _rigid_body_3d if is_inside_tree() else null
	if composite:
		if body:
			var g := body.global_transform
			body.top_level = false
			body.global_transform = g
			body.freeze = true
			body.collision_layer = 0
			body.collision_mask = 0
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
		var rg := global_transform
		top_level = false
		global_transform = rg
		instanced = false
	else:
		if body:
			body.collision_layer = 10
			body.collision_mask = 15
			body.freeze = not Simulation.is_running()

@onready var _rigid_body_3d: RigidBody3D = $RigidBody3D
@onready var _model: MeshInstance3D = _find_mesh_instance($RigidBody3D)


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	Simulation.pause_toggled.connect(_on_simulation_set_paused)


func _ready() -> void:
	_generate_collision_from_mesh()
	_rigid_body_3d.freeze = not Simulation.is_running()
	if Simulation.is_running():
		instanced = true
		_rigid_body_3d.linear_velocity = initial_linear_velocity


func _generate_collision_from_mesh() -> void:
	if not _model or not _model.mesh:
		return
	var old_shape: CollisionShape3D = $RigidBody3D/CollisionShape3D
	var mesh: Mesh = _model.mesh
	var new_shape: ConvexPolygonShape3D = mesh.create_convex_shape()
	if new_shape:
		var new_collision: CollisionShape3D = CollisionShape3D.new()
		new_collision.shape = new_shape
		new_collision.transform = _rigid_body_3d.global_transform.affine_inverse() * _model.global_transform
		new_collision.name = "CollisionShape3D"
		_rigid_body_3d.add_child(new_collision, true)
		_rigid_body_3d.remove_child(old_shape)
		old_shape.queue_free()


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	Simulation.pause_toggled.disconnect(_on_simulation_set_paused)
	if instanced and not _in_composite:
		queue_free()


func selected() -> void:
	if _paused or not Simulation.is_running():
		return

	if _rigid_body_3d.freeze:
		_rigid_body_3d.top_level = false
		if _rigid_body_3d.transform != Transform3D.IDENTITY:
			_rigid_body_3d.transform = Transform3D.IDENTITY
	else:
		_rigid_body_3d.top_level = true
		if transform != _rigid_body_3d.transform:
			transform = _rigid_body_3d.transform


func use() -> void:
	_rigid_body_3d.freeze = not _rigid_body_3d.freeze


func _on_simulation_started() -> void:
	if _in_composite:
		return
	if _enable_initial_transform:
		return
	_initial_transform = global_transform
	_rigid_body_3d.linear_velocity = initial_linear_velocity
	_rigid_body_3d.top_level = true
	_rigid_body_3d.freeze = false
	_enable_initial_transform = true


func _on_simulation_ended() -> void:
	if _in_composite:
		return
	if instanced:
		queue_free()
	else:
		_rigid_body_3d.top_level = false
		_rigid_body_3d.transform = Transform3D.IDENTITY
		_rigid_body_3d.linear_velocity = Vector3.ZERO
		_rigid_body_3d.angular_velocity = Vector3.ZERO
		if _enable_initial_transform:
			global_transform = _initial_transform
			_enable_initial_transform = false


func _on_simulation_set_paused(paused: bool) -> void:
	if _in_composite:
		return
	_paused = paused
	_rigid_body_3d.top_level = true
	_rigid_body_3d.freeze = paused
	transform = _rigid_body_3d.transform
	_rigid_body_3d.top_level = not paused


static func _find_mesh_instance(parent: Node) -> MeshInstance3D:
	for child in parent.get_children():
		if child is MeshInstance3D:
			return child
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found:
			return found
	return null
