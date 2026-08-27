@tool
class_name CeldaSpawner
extends ResizableNode3D

## Alimentador de la etapa 1 (S1). Emite celdas por comando del PLC
## (CMD/EXEC → DONE) o en modo automático por tasa mientras corre la simulación.

## La escena a alimentar (debe derivar de Producto o Celda).
@export var scene: PackedScene
## Posición de emisión relativa al spawner (boca de la tolva).
@export var spawn_offset: Vector3 = Vector3(0, -0.02, 0)
## Velocidad inicial al emitir (hacia el conveyor).
@export var spawn_velocity: Vector3 = Vector3.ZERO

@export_group("Auto Spawn")
## Cuando está habilitado, detiene el spawn.
@export var disable: bool = false:
	set(value):
		if value == disable:
			return
		disable = value

## Celdas emitidas por minuto en modo automático (sin PLC).
@export_range(1, 1000) var spawn_per_minute: int = 30:
	set(value):
		spawn_per_minute = clampi(value, 1, 1000)

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for communicating with the PLC.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

@export_subgroup("S1 Tags")
@export var cmd_tag: String = "_CMD"
@export var exec_tag: String = "_EXEC"
@export var done_tag: String = "_DONE"
@export var running_tag: String = "_RUNNING"
@export var ready_tag: String = "_READY"
@export var count_tag: String = "_COUNT"
@export var auto_enable_tag: String = "_AUTO_ENABLE"
@export var rate_tag: String = "_RATE"

const STATION_PREFIX: String = "S1"
const BATCH_INTERVAL: float = 0.2

var _comms := PlantComms.new()
var _exec_prev: bool = false
var _done: bool = false
var _pending: int = 0
var _batch_timer: float = 0.0
var _count: int = 0
var _auto_running: bool = false
var _auto_interval: float = 0.0
var _auto_pending: bool = false


func _init() -> void:
	super._init()
	size_default = Vector3(1.0, 0.8, 1.0)


func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property)


func _enter_tree() -> void:
	super._enter_tree()
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized)
	super._exit_tree()


func _physics_process(delta: float) -> void:
	if _comms.is_ready():
		var exec := _comms.read_bit(_tag(exec_tag))
		if exec and not _exec_prev:
			_start_command(_comms.read_int(_tag(cmd_tag)))
		_exec_prev = exec

		var auto_enable := _comms.read_bit(_tag(auto_enable_tag))
		_auto_running = auto_enable
		if auto_enable:
			_batch_timer -= delta
			if _batch_timer <= 0.0 and _pending <= 0:
				_pending = 1
				_auto_pending = true
				_batch_timer = 60.0 / maxf(_read_float_tag(rate_tag), 1.0)
			_done = _pending <= 0
		elif _auto_pending:
			# Auto desactivado: cancelar la celda pendiente (no emitir tras el stop).
			_pending = 0
			_auto_pending = false
			_done = true

		_comms.write_bit(_tag(running_tag), _pending > 0, true)
		_comms.write_bit(_tag(done_tag), _done, true)
		_comms.write_bit(_tag(ready_tag), scene != null, true)

	if _pending > 0:
		_batch_timer -= delta
		if _batch_timer <= 0.0:
			_spawn_one()
			_pending -= 1
			_batch_timer = BATCH_INTERVAL
			if _pending <= 0:
				_done = true
				_auto_pending = false
		return

	if not enable_comms:
		_auto_spawn(delta)


func _auto_spawn(delta: float) -> void:
	if disable or not Simulation.is_running():
		return
	_auto_interval += delta
	var period := 60.0 / float(spawn_per_minute)
	if _auto_interval >= period:
		_spawn_one()
		_auto_interval = 0.0


func _on_simulation_started() -> void:
	_exec_prev = false
	_done = false
	_pending = 0
	_count = 0
	_auto_interval = 0.0
	_auto_pending = false
	if enable_comms:
		_comms.setup(tag_group_name, _build_tag_spec())
		_comms.register_all()


func _on_simulation_ended() -> void:
	if _comms.is_ready():
		_comms.write_bit(_tag(ready_tag), false, true)
	_exec_prev = false
	_done = false
	_pending = 0
	_count = 0
	_auto_running = false
	_auto_interval = 0.0
	_auto_pending = false


func _tag_group_initialized(group: String) -> void:
	if _comms.on_group_initialized(group):
		_comms.write_bit(_tag(ready_tag), scene != null)


func _build_tag_spec() -> Dictionary:
	return {
		_tag(cmd_tag): OIPComms.TAG_TYPE_INT32,
		_tag(exec_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(done_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(running_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(ready_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(count_tag): OIPComms.TAG_TYPE_INT32,
		_tag(auto_enable_tag): OIPComms.TAG_TYPE_BOOL,
		_tag(rate_tag): OIPComms.TAG_TYPE_FLOAT32,
	}


func _tag(suffix: String) -> String:
	# OPC UA tags are full NodeIds (ns=...); pass them through unchanged.
	# Legacy S7/EIP suffixes (e.g. "_CMD") keep the STATION_PREFIX + suffix form.
	if suffix.contains("="):
		return suffix
	return STATION_PREFIX + suffix


func _start_command(cmd: int) -> void:
	_done = false
	if cmd >= 1:
		_pending = maxi(cmd, 1)
		_auto_pending = false
		_batch_timer = 0.0
	else:
		_done = true


func _spawn_one() -> void:
	if scene == null:
		_done = true
		return
	var item := scene.instantiate() as Node3D
	if item == null:
		push_warning("CeldaSpawner: la escena configurada no pudo instanciarse")
		_done = true
		return
	var product := item as Producto
	var celda := item as Celda
	if product == null and celda == null:
		push_warning("CeldaSpawner: la escena configurada no deriva de Producto ni de Celda")
		item.queue_free()
		_done = true
		return
	item.position = position + spawn_offset
	item.rotation = rotation
	if product:
		product.instanced = true
		product.initial_linear_velocity = spawn_velocity
	else:
		celda.instanced = true
		celda.initial_linear_velocity = spawn_velocity
	add_child(item, true)
	item.owner = get_tree().edited_scene_root
	_count += 1
	if _comms.is_ready():
		_comms.write_int(_tag(count_tag), _count)


func use() -> void:
	disable = not disable


func _read_float_tag(suffix: String) -> float:
	return _comms.read_float(_tag(suffix))
