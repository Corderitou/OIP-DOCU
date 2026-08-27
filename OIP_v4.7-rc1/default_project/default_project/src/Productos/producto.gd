@tool
class_name Producto
extends Node3D

## Base para productos de la línea de paneles (vidrio, EVA, backsheet, caja,
## panel). Comporta RigidBody3D: congelado hasta que la simulación arranca,
## liberado con velocidad inicial al hacerlo, y auto-eliminado si fue instanciado.

## Initial velocity applied to this product when simulation starts.
@export var initial_linear_velocity: Vector3 = Vector3.ZERO

var _initial_transform: Transform3D
var _paused: bool = false
var instanced: bool = false
var _enable_initial_transform: bool = false

@onready var _rigid_body_3d: RigidBody3D = $RigidBody3D


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	Simulation.pause_toggled.connect(_on_simulation_set_paused)


func _ready() -> void:
	_rigid_body_3d.freeze = not Simulation.is_running()
	if Simulation.is_running():
		instanced = true
		_rigid_body_3d.linear_velocity = initial_linear_velocity


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	Simulation.pause_toggled.disconnect(_on_simulation_set_paused)
	if instanced:
		queue_free()


func _on_simulation_started() -> void:
	if _enable_initial_transform:
		return
	_initial_transform = global_transform
	_rigid_body_3d.linear_velocity = initial_linear_velocity
	_rigid_body_3d.top_level = true
	_rigid_body_3d.freeze = false
	_enable_initial_transform = true


func _on_simulation_ended() -> void:
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
	_paused = paused
	_rigid_body_3d.top_level = true
	_rigid_body_3d.freeze = paused
	transform = _rigid_body_3d.transform
	_rigid_body_3d.top_level = not paused
