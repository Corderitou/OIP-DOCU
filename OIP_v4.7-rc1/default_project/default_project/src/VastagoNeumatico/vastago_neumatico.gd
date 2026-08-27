@tool
class_name VastagoNeumatico
extends Node3D

## Button to toggle the cylinder in the editor.
@export_tool_button("Toggle Cylinder") var toggle_action: Callable = toggle
## Time in seconds for the rod to extend or retract.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var extend_time: float = 0.5
## Distance the rod travels when extended.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var stroke_length: float = 0.4:
	set(value):
		stroke_length = maxf(value, 0.0)
		_update_measurements()
## Length of the cylinder barrel.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var cylinder_length: float = 0.6:
	set(value):
		cylinder_length = maxf(value, 0.05)
		_update_measurements()
## Outer diameter of the cylinder barrel.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var cylinder_diameter: float = 0.1:
	set(value):
		cylinder_diameter = maxf(value, 0.02)
		_update_measurements()
## Diameter of the pusher rod.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var rod_diameter: float = 0.02:
	set(value):
		rod_diameter = clampf(value, 0.004, cylinder_diameter * 0.5)
		_update_measurements()

var size: Vector3 = Vector3(0.24, 0.122, 1.0)

var _extended: bool = false
var _tag := OIPCommsTag.new()
@onready var _animator: VastagoNeumaticoAnimator = $VastagoNeumaticoAnimator

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for reading extend commands from external systems.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value
## The tag name for the extend trigger in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var tag_name: String = ""

func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property)

func _ready() -> void:
	if has_meta("is_preview"):
		return
	_update_measurements()

func _enter_tree() -> void:
	if has_meta("is_preview"):
		return
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_stopped)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)

func _exit_tree() -> void:
	if has_meta("is_preview"):
		return
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_stopped)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)

func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/VastagoNeumatico.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node

func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)

func use() -> void:
	toggle()

## Extend the rod and hold it until retracted.
func extend() -> void:
	_extended = true

## Retract the rod back to its home position.
func retract() -> void:
	_extended = false

func toggle() -> void:
	_extended = not _extended

func _update_measurements() -> void:
	size = Vector3(cylinder_diameter * 2.4, cylinder_diameter * 1.22, cylinder_length + stroke_length)
	if not is_inside_tree():
		return
	var anim := _animator
	if anim:
		anim.set_measurements(cylinder_length, cylinder_diameter, rod_diameter, stroke_length)

func _physics_process(_delta: float) -> void:
	_animator.set_target(_extended, extend_time)

func _on_simulation_started() -> void:
	if enable_comms:
		_tag.register(tag_group_name, tag_name, OIPComms.TAG_TYPE_BOOL)

func _on_simulation_stopped() -> void:
	_extended = false
	_animator.reset()

func _tag_group_initialized(tag_group_name_param: String) -> void:
	if _tag.on_group_initialized(tag_group_name_param):
		_tag.write_bit(_extended)

func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms or not _tag.matches_group(tag_group_name_param):
		return
	_extended = _tag.read_bit()
