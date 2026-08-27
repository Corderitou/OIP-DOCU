@tool
class_name IndexingBeltConveyor
extends Node3D

## Simple indexing belt conveyor. Each rising edge on [member step_tag] advances
## the belt by [member step_distance] at [member step_speed]. The distance is
## measured locally in Godot, so OPC UA latency only affects when the step starts,
## not how far the belt moves.

@export_tool_button("Step") var step_action: Callable = advance

@export_category("Dimensions")
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var length: float = 1.0:
	set(value):
		length = maxf(0.1, value)
		_rebuild_visuals()

@export_custom(PROPERTY_HINT_NONE, "suffix:m") var width: float = 0.6:
	set(value):
		width = maxf(0.1, value)
		_rebuild_visuals()

## Belt height in meters. Also sets end-pulley radius (= height / 2).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var height: float = 0.5:
	set(value):
		height = maxf(0.01, value)
		_rebuild_visuals()

@export_category("Indexing")
## Distance the belt advances per step command.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var step_distance: float = 0.16:
	set(value):
		step_distance = maxf(0.001, value)

## Belt speed while executing a step.
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var step_speed: float = 0.2:
	set(value):
		step_speed = maxf(0.0, value)

@export_category("Visual")
@export var belt_color: Color = Color.WHITE:
	set(value):
		belt_color = value
		_update_belt_material()

@export var belt_texture: BeltConveyor.BeltTexture = BeltConveyor.BeltTexture.STANDARD:
	set(value):
		belt_texture = value
		_update_belt_material()

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for communicating with the PLC.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value

@export_subgroup("Indexing Belt Tags")
## Rising edge triggers one indexing step.[br]Datatype: [code]BOOL[/code] — full OPC UA NodeId.
@export var step_tag: String = ""
## Optional speed override from PLC. If empty, uses [member step_speed].[br]Datatype: [code]REAL[/code].
@export var speed_tag: String = ""
## Optional step distance override from PLC. If empty, uses [member step_distance].[br]Datatype: [code]REAL[/code].
@export var step_distance_tag: String = ""
## True while the belt is moving to complete a step.[br]Datatype: [code]BOOL[/code].
@export var running_tag: String = ""

var _step_tag := OIPCommsTag.new()
var _speed_tag := OIPCommsTag.new()
var _step_distance_tag := OIPCommsTag.new()
var _running_tag := OIPCommsTag.new()

var _last_step: bool = false
var _target_position: float = 0.0
var _current_position: float = 0.0
var _current_speed: float = 0.0
var _belt_material: ShaderMaterial

@onready var _body: StaticBody3D
@onready var _belt_mesh: MeshInstance3D
@onready var _frame_left: MeshInstance3D
@onready var _frame_right: MeshInstance3D


func _validate_property(property: Dictionary) -> void:
	if OIPCommsSetup.validate_tag_property(property, "tag_group_name", "tag_groups", "step_tag"):
		return
	if OIPCommsSetup.validate_tag_property(property, "tag_group_name", "tag_groups", "speed_tag"):
		return
	if OIPCommsSetup.validate_tag_property(property, "tag_group_name", "tag_groups", "step_distance_tag"):
		return
	if OIPCommsSetup.validate_tag_property(property, "tag_group_name", "tag_groups", "running_tag"):
		return


func _enter_tree() -> void:
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_stopped)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_stopped)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)


func _ready() -> void:
	_ensure_nodes()
	_rebuild_visuals()


func _ensure_nodes() -> void:
	if has_meta("is_preview"):
		return
	_body = get_node_or_null("BeltBody") as StaticBody3D
	if not is_instance_valid(_body):
		_body = StaticBody3D.new()
		_body.name = "BeltBody"
		_body.physics_material_override = preload("res://parts/BeltSurfaceMaterial.tres")
		add_child(_body, false, Node.INTERNAL_MODE_FRONT)
		_body.owner = self
	var cs := _body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(cs):
		cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		_body.add_child(cs)
		cs.owner = self
		cs.shape = BoxShape3D.new()

	_belt_mesh = get_node_or_null("BeltMesh") as MeshInstance3D
	if not is_instance_valid(_belt_mesh):
		_belt_mesh = MeshInstance3D.new()
		_belt_mesh.name = "BeltMesh"
		_belt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		add_child(_belt_mesh, false, Node.INTERNAL_MODE_FRONT)
		_belt_mesh.owner = self

	_frame_left = get_node_or_null("FrameLeft") as MeshInstance3D
	if not is_instance_valid(_frame_left):
		_frame_left = MeshInstance3D.new()
		_frame_left.name = "FrameLeft"
		add_child(_frame_left, false, Node.INTERNAL_MODE_FRONT)
		_frame_left.owner = self

	_frame_right = get_node_or_null("FrameRight") as MeshInstance3D
	if not is_instance_valid(_frame_right):
		_frame_right = MeshInstance3D.new()
		_frame_right.name = "FrameRight"
		add_child(_frame_right, false, Node.INTERNAL_MODE_FRONT)
		_frame_right.owner = self


func _rebuild_visuals() -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_belt_mesh):
		return

	# Collision: box covering the top surface. Centered on the belt's local midpoint.
	var half_len := length * 0.5
	_body.position = Vector3(half_len, -height * 0.5, 0.0)
	var cs := _body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if is_instance_valid(cs) and cs.shape is BoxShape3D:
		(cs.shape as BoxShape3D).size = Vector3(length, height, width)

	# Visual: full belt mesh with end pulleys, using the same builder as BeltConveyor.
	# BeltConveyorMesh centers X=0 at the midpoint of the flat run, so we offset the
	# MeshInstance by half_len so the belt tail aligns with this node's origin.
	var belt_mesh: ArrayMesh = BeltConveyorMesh.create_belt(length, height, width)
	_belt_mesh.mesh = belt_mesh
	_belt_mesh.position = Vector3(half_len, 0.0, 0.0)
	if belt_mesh != null and belt_mesh.get_surface_count() > 0:
		_belt_mesh.set_surface_override_material(0, _belt_material)

	_rebuild_frame_rails()

	_update_belt_material()


func _rebuild_frame_rails() -> void:
	if not is_instance_valid(_frame_left) or not is_instance_valid(_frame_right):
		return
	var segment := BeltSegment.new()
	segment.length = maxf(0.01, length - height)
	var path := BeltPath.build([segment], 0.0, 0.0, 0.0, height)
	if path == null or path.runs.is_empty():
		return
	var pulley_radius: float = height * 0.5
	_reconcile_frame_rail(_frame_left, path, -1.0, pulley_radius)
	_reconcile_frame_rail(_frame_right, path, 1.0, pulley_radius)


func _reconcile_frame_rail(mi: MeshInstance3D, path: BeltPath, side_sign: float, overhang: float) -> void:
	var mesh: ArrayMesh = ConveyorFrameMesh.create_along_path(
			path, height, width, side_sign, overhang, overhang, true)
	if mesh == null or mesh.get_surface_count() == 0:
		mi.mesh = null
		return
	mi.mesh = mesh
	mi.set_surface_override_material(0, ConveyorFrameMesh.create_material())


func _update_belt_material() -> void:
	if not is_instance_valid(_belt_mesh):
		return
	if not is_instance_valid(_belt_material):
		_belt_material = BeltSurface.create_material(belt_color, belt_texture)
	else:
		_belt_material.set_shader_parameter("ColorMix", belt_color)
		_belt_material.set_shader_parameter("use_alternate_texture", belt_texture == BeltConveyor.BeltTexture.ALTERNATE)
	if is_instance_valid(_belt_material):
		_belt_material.set_shader_parameter("Scale", maxf(1.0, length))
		if _belt_mesh.get_surface_override_material_count() > 0:
			_belt_mesh.set_surface_override_material(0, _belt_material)


func use() -> void:
	advance()


## Advance the belt by one step ([member step_distance]).
func advance() -> void:
	_target_position += step_distance


func _physics_process(delta: float) -> void:
	var moving := _current_position < _target_position - 0.0001
	if moving:
		var remaining := _target_position - _current_position
		var dist := minf(remaining, step_speed * delta)
		_current_position += dist
		_current_speed = step_speed if dist > 0.0 else 0.0
	else:
		_current_position = _target_position
		_current_speed = 0.0

	BeltSurface.apply_velocity(_body, _current_speed)
	if is_instance_valid(_belt_material):
		BeltSurface.advance_belt_position(_belt_material, _current_speed, delta, _current_position)

	if enable_comms and _running_tag.is_ready():
		_running_tag.write_bit(moving)


func _on_simulation_started() -> void:
	if not enable_comms:
		return
	if not step_tag.is_empty():
		_step_tag.register(tag_group_name, step_tag, OIPComms.TAG_TYPE_BOOL)
	if not speed_tag.is_empty():
		_speed_tag.register(tag_group_name, speed_tag, OIPComms.TAG_TYPE_FLOAT32)
	if not step_distance_tag.is_empty():
		_step_distance_tag.register(tag_group_name, step_distance_tag, OIPComms.TAG_TYPE_FLOAT32)
	if not running_tag.is_empty():
		_running_tag.register(tag_group_name, running_tag, OIPComms.TAG_TYPE_BOOL)
	_target_position = 0.0
	_current_position = 0.0
	_current_speed = 0.0


func _on_simulation_stopped() -> void:
	_target_position = 0.0
	_current_position = 0.0
	_current_speed = 0.0
	if is_instance_valid(_body):
		BeltSurface.apply_velocity(_body, 0.0)
	if _running_tag.is_ready():
		_running_tag.write_bit(false)


func _tag_group_initialized(group: String) -> void:
	_step_tag.on_group_initialized(group)
	_speed_tag.on_group_initialized(group)
	_step_distance_tag.on_group_initialized(group)
	_running_tag.on_group_initialized(group)


func _tag_group_polled(group: String) -> void:
	if not enable_comms:
		return
	if _step_tag.matches_group(group) and _step_tag.is_ready():
		var step_val := _step_tag.read_bit()
		if step_val and not _last_step:
			print("[IndexingBelt %s] STEP: distance=%.3f speed=%.3f" % [name, step_distance, step_speed])
			_target_position += step_distance
		_last_step = step_val
	if _speed_tag.matches_group(group) and _speed_tag.is_ready():
		step_speed = _speed_tag.read_float32()
	if _step_distance_tag.matches_group(group) and _step_distance_tag.is_ready():
		step_distance = _step_distance_tag.read_float32()
