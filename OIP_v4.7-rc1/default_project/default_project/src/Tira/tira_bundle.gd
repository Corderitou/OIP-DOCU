@tool
class_name TiraBundle
extends Node3D

## Agrupa las N tiras de un ciclo de Dispenser en un único objeto y las une
## físicamente entre sí con cross-joints rígidos entre segmentos homólogos de
## cada par de cadenas (una "escalera"): el conjunto se dobla como una cinta
## doble pero las tiras no se separan lateralmente.

@export_category("Bind")
## Limite lineal de los cross-joints entre segmentos homologos (m).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var cross_linear_limit: float = 0.0015
## Limite angular de los cross-joints entre segmentos homologos (rad).
@export_custom(PROPERTY_HINT_NONE, "suffix:rad") var cross_angular_limit: float = 0.001
## Imprime logs de bind/unbind en runtime.
@export var debug := false

const CROSS_LINEAR_LIMIT := 0.0015
const CROSS_ANGULAR_LIMIT := 0.001

var _tiras: Array[Tira] = []
var _cross_joints: Array[Generic6DOFJoint3D] = []
var _bound := false


func _enter_tree() -> void:
	Simulation.stopped.connect(_on_simulation_stopped)


func _exit_tree() -> void:
	if Simulation.stopped.is_connected(_on_simulation_stopped):
		Simulation.stopped.disconnect(_on_simulation_stopped)


func _ready() -> void:
	# En el EDITOR las tiras pegadas/copiadas desde un bundle de runtime traen
	# top_level=true (lo setea Stringer.release()); con eso el gizmo mueve el
	# bundle pero las tiras no lo siguen. En editor se fuerzan a locales para
	# que el transform del bundle sea directamente editable.
	if Engine.is_editor_hint():
		for child in get_children():
			if child is Tira:
				child.top_level = false


func add_tira(tira: Tira) -> void:
	if tira and not _tiras.has(tira):
		_tiras.append(tira)


func get_tiras() -> Array[Tira]:
	return _tiras


func is_bound() -> bool:
	return _bound


func _process(_delta: float) -> void:
	if _bound:
		return
	if _tiras.size() < 2:
		return
	var can_bind := true
	for t in _tiras:
		if t == null or not is_instance_valid(t):
			return
		if t.held or t.anchored_dispenser or t.anchored_picker:
			can_bind = false
			break
		if not t.has_chain():
			return
	if can_bind:
		bind()


func bind() -> void:
	if _bound:
		return
	unbind()
	var a := _tiras[0]
	var b := _tiras[1]
	var count := mini(a.get_segment_count(), b.get_segment_count())
	if count < 2:
		return
	var basis := _safe_basis(a.get_segment(0).global_transform.basis)
	for i in count:
		var sa := a.get_segment(i)
		var sb := b.get_segment(i)
		if sa == null or sb == null or not is_instance_valid(sa) or not is_instance_valid(sb):
			continue
		var joint := Generic6DOFJoint3D.new()
		joint.name = "Cross%d" % i
		add_child(joint, true)
		var mid := _safe((sa.global_position + sb.global_position) * 0.5)
		joint.global_transform = Transform3D(basis, mid)
		_configure_cross(joint)
		joint.node_a = sa.get_path()
		joint.node_b = sb.get_path()
		_cross_joints.append(joint)
	_bound = true


func unbind() -> void:
	for joint in _cross_joints:
		if is_instance_valid(joint):
			joint.free()
	_cross_joints.clear()
	_bound = false


func _configure_cross(joint: Generic6DOFJoint3D) -> void:
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -CROSS_LINEAR_LIMIT)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -CROSS_LINEAR_LIMIT)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -CROSS_LINEAR_LIMIT)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, CROSS_LINEAR_LIMIT)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, CROSS_LINEAR_LIMIT)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, CROSS_LINEAR_LIMIT)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -CROSS_ANGULAR_LIMIT)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -CROSS_ANGULAR_LIMIT)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -CROSS_ANGULAR_LIMIT)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, CROSS_ANGULAR_LIMIT)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, CROSS_ANGULAR_LIMIT)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, CROSS_ANGULAR_LIMIT)


func _on_simulation_stopped() -> void:
	unbind()
	var keep := false
	for t in _tiras:
		if is_instance_valid(t) and not t.remove_on_stop:
			keep = true
	if not keep:
		queue_free()


func _safe(v: Vector3) -> Vector3:
	if not v.is_finite():
		return Vector3.ZERO
	return v


func _safe_basis(b: Basis) -> Basis:
	if not b.is_finite():
		return Basis.IDENTITY
	return b
