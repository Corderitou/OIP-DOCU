@tool
class_name Maquina
extends Node3D

## Base para máquinas de la línea controladas por PLCSIM.
##
## Implementa el handshake estándar de la planta (CMD/EXEC/DONE/RUNNING/READY/
## FAULT/IN_POS) sobre un único tag group S7, más el modelo de simulación.
## Subclases añaden analógicos (SETPOINT/MV/PV) y su lógica de proceso.

## Prefijo de los tags de esta estación (ej. "S2"). El tag final es
## `station_prefix + suffix` (ej. "S2_CMD").
@export var station_prefix: String = "S2"

@export_group("Ciclo")
## Tiempo del ciclo cuando CMD=1.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var cycle_time: float = 5.0

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for communicating with the PLC.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

@export_subgroup("Handshake Tags")
@export var cmd_tag: String = "_CMD"
@export var exec_tag: String = "_EXEC"
@export var done_tag: String = "_DONE"
@export var running_tag: String = "_RUNNING"
@export var ready_tag: String = "_READY"
@export var fault_tag: String = "_FAULT"
@export var in_pos_tag: String = "_IN_POS"

var _comms := PlantComms.new()
var _exec_prev: bool = false
var _cycle_active: bool = false
var _cycle_remaining: float = 0.0
var _done: bool = false
var _fault: bool = false
var _machine_ready: bool = true
var _product_present: bool = true


func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property)


func _enter_tree() -> void:
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized)


func _physics_process(delta: float) -> void:
	if _comms.is_ready():
		var exec := _comms.read_bit(_tag(exec_tag))
		if exec and not _exec_prev:
			_start_command(_comms.read_int(_tag(cmd_tag)))
		_exec_prev = exec

		if _cycle_active:
			_cycle_remaining -= delta
			if _cycle_remaining <= 0.0:
				_finish_cycle()

		_comms.write_bit(_tag(running_tag), _cycle_active, true)
		_comms.write_bit(_tag(done_tag), _done, true)
		_comms.write_bit(_tag(ready_tag), _machine_ready, true)
		_comms.write_bit(_tag(fault_tag), _fault, true)
		_comms.write_bit(_tag(in_pos_tag), _product_present, true)

	_on_tick(delta)


func _on_simulation_started() -> void:
	_exec_prev = false
	_done = false
	_cycle_active = false
	_fault = false
	if enable_comms:
		_comms.setup(tag_group_name, _build_tag_spec())
		_comms.register_all()


func _on_simulation_ended() -> void:
	_exec_prev = false
	_cycle_active = false
	_done = false


func _tag_group_initialized(group: String) -> void:
	_comms.on_group_initialized(group)


## Spec de tags base. Las subclases extienden con analógicos.
func _build_tag_spec() -> Dictionary:
	return {
		_tag(cmd_tag): OIPComms.TAG_TYPE_INT32,
		_tag(exec_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(done_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(running_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(ready_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(fault_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(in_pos_tag): OIPComms.TAG_TYPE_BOOL,
	}


func _tag(suffix: String) -> String:
	return station_prefix + suffix


func _start_command(cmd: int) -> void:
	_done = false
	if cmd == 1:
		_cycle_active = true
		_cycle_remaining = cycle_time
		on_cycle_started()
	else:
		on_command(cmd)


func _finish_cycle() -> void:
	_cycle_active = false
	_done = true
	on_cycle_finished()


## Llamado al arrancar un ciclo (CMD=1).
func on_cycle_started() -> void:
	pass


## Llamado para cualquier comando distinto de 1.
func on_command(cmd: int) -> void:
	pass


## Llamado al terminar el ciclo.
func on_cycle_finished() -> void:
	pass


## Llamado cada frame de física con comms listos (o no).
func _on_tick(_delta: float) -> void:
	pass


func set_product_present(value: bool) -> void:
	_product_present = value


func set_fault(value: bool) -> void:
	_fault = value
