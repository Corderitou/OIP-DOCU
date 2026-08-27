@tool
class_name Maquina1
extends Node3D

@export_category("Actions")
@export var cut_trigger: bool = false:
	set(v):
		if v:
			_cut()
		cut_trigger = false

@export var release_trigger: bool = false:
	set(v):
		if v:
			_release()
		release_trigger = false

@export_category("Axis Positions")
@export_range(0.0, 2.0, 0.001, "suffix:m") var z_position: float = 0.0:
	set(value):
		z_position = clampf(value, z_range.x, z_range.y)
		_sync_stringer_axis()

@export_range(0.0, 2.0, 0.001, "suffix:m") var y_position: float = 0.0:
	set(value):
		y_position = clampf(value, y_range.x, y_range.y)
		_sync_stringer_axis()

@export_category("Limits")
@export var z_range: Vector2 = Vector2(0.0, 1.5):
	set(value):
		z_range = value
		if _stringer:
			_stringer.z_range = z_range
			z_position = z_position

@export var y_range: Vector2 = Vector2(0.0, 1.0):
	set(value):
		y_range = value
		if _stringer:
			_stringer.y_range = y_range
			y_position = y_position

@export_category("Motion")
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var motion_speed: float = 1.0:
	set(value):
		motion_speed = value
		if _stringer:
			_stringer.motion_speed = motion_speed

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for communicating with the PLC.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

@export_subgroup("Maquina1 Tags")
## Rising edge cuts the strip at the dispenser.
## Datatype: [code]BOOL[/code] — full OPC UA NodeId (e.g. [code]ns=2;s=Maquina1_Cut[/code]).
@export var cut_tag: String = "ns=2;s=Maquina1_Cut"
## Rising edge releases the strip from the stringer.
## Datatype: [code]BOOL[/code] — full OPC UA NodeId (e.g. [code]ns=2;s=Maquina1_Release[/code]).
@export var release_tag: String = "ns=2;s=Maquina1_Release"
## Target Z axis position (m) of the stringer.
## Datatype: [code]FLOAT[/code] — full OPC UA NodeId (e.g. [code]ns=2;s=Maquina1_Z[/code]).
@export var z_tag: String = "ns=2;s=Maquina1_Z"
## Target Y axis position (m) of the stringer.
## Datatype: [code]FLOAT[/code] — full OPC UA NodeId (e.g. [code]ns=2;s=Maquina1_Y[/code]).
@export var y_tag: String = "ns=2;s=Maquina1_Y"
## Stringer motion speed (m/s).
## Datatype: [code]FLOAT[/code] — full OPC UA NodeId (e.g. [code]ns=2;s=Maquina1_Speed[/code]).
@export var speed_tag: String = "ns=2;s=Maquina1_Speed"

var _stringer: Stringer
var _dispenser: Dispenser

var _comms := PlantComms.new()
var _last_cut: bool = false
var _last_release: bool = false
var _last_z: float = NAN
var _last_y: float = NAN
var _last_speed: float = NAN


func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property)


func _ready() -> void:
	_stringer = get_node_or_null("Stringer") as Stringer
	_dispenser = get_node_or_null("Dispenser") as Dispenser
	_sync_stringer_axis()
	if _stringer:
		_stringer.motion_speed = motion_speed


func _enter_tree() -> void:
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized)


func _physics_process(_delta: float) -> void:
	if not _comms.is_ready():
		return

	var cut := _comms.read_bit(cut_tag)
	if cut and not _last_cut:
		_cut()
	_last_cut = cut

	var release := _comms.read_bit(release_tag)
	if release and not _last_release:
		_release()
	_last_release = release

	var zv := _comms.read_float(z_tag)
	if _last_z != zv:
		_last_z = zv
		z_position = zv
	if not y_tag.is_empty():
		var yv := _comms.read_float(y_tag)
		if _last_y != yv:
			_last_y = yv
			y_position = yv
	if not speed_tag.is_empty():
		var sv := _comms.read_float(speed_tag)
		if _last_speed != sv:
			_last_speed = sv
			motion_speed = sv


func _sync_stringer_axis() -> void:
	if not _stringer:
		return
	_stringer.z_position = z_position
	_stringer.y_position = y_position


func _cut() -> void:
	if _dispenser:
		_dispenser.cut()


func _release() -> void:
	if _stringer:
		_stringer.release()


func _on_simulation_started() -> void:
	_last_cut = false
	_last_release = false
	_last_z = NAN
	_last_y = NAN
	_last_speed = NAN
	if enable_comms:
		_comms.setup(tag_group_name, _build_tag_spec())
		_comms.register_all()


func _on_simulation_ended() -> void:
	_last_cut = false
	_last_release = false


func _tag_group_initialized(group: String) -> void:
	_last_z = NAN
	_last_y = NAN
	_last_speed = NAN
	_comms.on_group_initialized(group)


func _build_tag_spec() -> Dictionary:
	var spec: Dictionary = {}
	if not cut_tag.is_empty():
		spec[cut_tag] = OIPComms.TAG_TYPE_BOOL
	if not release_tag.is_empty():
		spec[release_tag] = OIPComms.TAG_TYPE_BOOL
	if not z_tag.is_empty():
		spec[z_tag] = OIPComms.TAG_TYPE_FLOAT32
	if not y_tag.is_empty():
		spec[y_tag] = OIPComms.TAG_TYPE_FLOAT32
	if not speed_tag.is_empty():
		spec[speed_tag] = OIPComms.TAG_TYPE_FLOAT32
	return spec
