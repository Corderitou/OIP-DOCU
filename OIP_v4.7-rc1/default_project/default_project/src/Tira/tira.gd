@tool
class_name Tira
extends Node3D

const SEGMENT_LENGTH: float = 0.02
const SEGMENT_MASS: float = 0.005
const BEND_LIMIT_DEG: float = 15.0
const LATERAL_LIMIT_DEG: float = 3.0
const TWIST_LIMIT_DEG: float = 2.0
const LINEAR_LIMIT: float = 0.001
const ANGULAR_DAMP: float = 3.0
const LINEAR_DAMP: float = 0.5
const SETTLE_DAMP_LINEAR: float = 2.5
const SETTLE_DAMP_ANGULAR: float = 10.0
const SETTLE_FRAMES: int = 240
const FLOOR_TOP: float = 0.0
const FLOOR_MARGIN: float = 0.01
const DISPENSER_EDGE_MARGIN: float = 0.02

# Transport mode: looser, drag-friendly tuning for free tiras riding a belt.
const TRANSPORT_LATERAL_LIMIT_DEG: float = 8.0
const TRANSPORT_TWIST_LIMIT_DEG: float = 4.0
const TRANSPORT_LINEAR_LIMIT: float = 0.003
const TRANSPORT_LINEAR_DAMP: float = 0.15
const TRANSPORT_ANGULAR_DAMP: float = 1.5
const TRANSPORT_FRICTION: float = 0.85

var _segments: Array[RigidBody3D] = []
var _joints: Array[Generic6DOFJoint3D] = []
var _anchor_joint: PinJoint3D = null
var _head_joint: PinJoint3D = null
var _seg_material: StandardMaterial3D = null
var held: bool = false
var _dynamic: bool = false
var anchored_dispenser: bool = false
var anchored_picker: bool = false
var _settle_frames_left: int = 0
var _in_composite: bool = false
var _transport_mode: bool = false
var _lateral_limit_deg: float = LATERAL_LIMIT_DEG
var _twist_limit_deg: float = TWIST_LIMIT_DEG
var _linear_limit_m: float = LINEAR_LIMIT
var _seg_physics_material: PhysicsMaterial = null

@export_range(0.0, 4.0, 0.05, "suffix:g") var fall_gravity_scale: float = 1.0
## When true, the tira (and any Sandwich composite it rides) is removed from the
## scene when the simulation stops, leaving the line clean for the next run.
@export var remove_on_stop: bool = true


static func _safe_basis(b: Basis) -> Basis:
	if not b.is_finite():
		return Basis.IDENTITY
	return b


static func _chain_basis(start: Vector3, end: Vector3) -> Basis:
	var dir := (end - start)
	if dir.length_squared() < 1e-8:
		return Basis.IDENTITY
	var d := dir.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.98:
		up = Vector3.RIGHT
	return Basis.looking_at(d, up)


static func lateral_axis(start: Vector3, end: Vector3) -> Vector3:
	var d := end - start
	if d.length_squared() < 1e-8:
		d = Vector3.FORWARD
	var n := d.normalized()
	var h := n.cross(Vector3.UP)
	if h.length_squared() < 1e-6:
		h = n.cross(Vector3.RIGHT)
	return h.normalized()


static func get_common_container(node: Node) -> Node:
	var n := node
	while n and n.get_parent() and not (n.get_parent() is Viewport):
		n = n.get_parent()
	return n


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)


func _safe(v: Vector3) -> Vector3:
	if not v.is_finite():
		return Vector3.ZERO
	return v


func _set_anchor(side: String, value: bool, reason: String) -> void:
	if side == "dispenser":
		if anchored_dispenser == value:
			return
		anchored_dispenser = value
	elif side == "picker":
		if anchored_picker == value:
			return
		anchored_picker = value


func _get_dispenser_body() -> PhysicsBody3D:
	var parent := get_parent()
	while parent:
		if parent is Dispenser:
			var body := parent.get_node_or_null("Body") as PhysicsBody3D
			if body:
				return body
		parent = parent.get_parent()
	return null


func _get_anchor_body_path() -> NodePath:
	var body := _get_dispenser_body()
	if body:
		return body.get_path()
	return NodePath()


func _effective_spawn_start(start: Vector3, end: Vector3) -> Vector3:
	var body := _get_dispenser_body()
	if not body or not is_instance_valid(body):
		return start
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape or not (shape.shape is BoxShape3D):
		return start
	var half := (shape.shape as BoxShape3D).size * 0.5
	var xform := body.global_transform
	var basis := _safe_basis(xform.basis)
	var center := xform.origin
	var local_start := basis.inverse() * (start - center)
	var inside := true
	for a in 3:
		if absf(local_start[a]) > half[a]:
			inside = false
			break
	if not inside:
		return start
	var dir := end - start
	if dir.length_squared() < 1e-8:
		return start
	dir = dir.normalized()
	var local_dir := basis.inverse() * dir
	var exit_t := INF
	for a in 3:
		var ad := local_dir[a]
		if absf(ad) < 1e-6:
			continue
		var tt: float
		if ad > 0.0:
			tt = (half[a] - local_start[a]) / ad
		else:
			tt = (-half[a] - local_start[a]) / ad
		if tt > 0.0:
			exit_t = minf(exit_t, tt)
	if not is_finite(exit_t):
		return start
	return _safe(start + dir * (exit_t + DISPENSER_EDGE_MARGIN))


func _ensure_material() -> StandardMaterial3D:
	if _seg_material:
		return _seg_material
	_seg_material = StandardMaterial3D.new()
	_seg_material.albedo_color = Color(0.72, 0.45, 0.2, 1.0)
	_seg_material.metallic = 0.7
	_seg_material.roughness = 0.3
	return _seg_material


func _configure_6dof(joint: Generic6DOFJoint3D) -> void:
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	_apply_6dof_limits(joint)


func _apply_6dof_limits(joint: Generic6DOFJoint3D) -> void:
	var linear := _linear_limit_m
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -linear)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, linear)

	var bend := deg_to_rad(BEND_LIMIT_DEG)
	var lateral := deg_to_rad(_lateral_limit_deg)
	var twist := deg_to_rad(_twist_limit_deg)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -bend)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, bend)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -lateral)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lateral)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -twist)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, twist)


func build_chain(start_pos: Vector3, end_pos: Vector3, offset: Vector3) -> void:
	clear_chain()
	_hide_placeholder()
	# A freshly built (taut) chain uses the strict limits, not transport tuning.
	_transport_mode = false
	_lateral_limit_deg = LATERAL_LIMIT_DEG
	_twist_limit_deg = TWIST_LIMIT_DEG
	_linear_limit_m = LINEAR_LIMIT

	var start := _safe(start_pos)
	var end := _safe(end_pos)
	start = _effective_spawn_start(start, end)
	var dist := start.distance_to(end)
	if dist < 0.001:
		return

	var count := maxi(1, ceili(dist / SEGMENT_LENGTH))
	var seg_len := dist / float(count)
	var mat := _ensure_material()
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0
	pm.friction = 0.6
	_seg_physics_material = pm
	var basis := _safe_basis(_chain_basis(start, end))

	for i in count:
		var seg := RigidBody3D.new()
		seg.name = "Seg%d" % i
		seg.freeze = true
		seg.gravity_scale = 0
		seg.can_sleep = true
		seg.continuous_cd = true
		seg.angular_damp = ANGULAR_DAMP
		seg.linear_damp = LINEAR_DAMP
		seg.collision_layer = 10
		seg.collision_mask = 15
		seg.mass = SEGMENT_MASS
		seg.physics_material_override = pm

		var shape := BoxShape3D.new()
		shape.size = Vector3(0.006, 0.002, seg_len * 0.95)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		seg.add_child(cs)

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.006, 0.002, seg_len * 0.99)
		mesh.material = mat
		mi.mesh = mesh
		seg.add_child(mi)

		add_child(seg, true)
		_segments.append(seg)

		var t := float(i) / float(maxi(count - 1, 1))
		var pos := _safe(start.lerp(end, t) + _safe(offset))
		seg.global_transform = Transform3D(basis, pos)

	_anchor_joint = PinJoint3D.new()
	_anchor_joint.name = "PinAnchor"
	add_child(_anchor_joint, true)
	_anchor_joint.global_transform = Transform3D(basis, _safe(_segments[0].global_position))
	_anchor_joint.node_a = _segments[0].get_path()
	_anchor_joint.node_b = _get_anchor_body_path()
	_set_anchor("dispenser", true, "build_chain (grab/anclaje)")

	_head_joint = PinJoint3D.new()
	_head_joint.name = "PinHead"
	add_child(_head_joint, true)
	_head_joint.global_transform = Transform3D(basis, _safe(end + _safe(offset)))
	_head_joint.node_a = _segments[count - 1].get_path()
	_set_anchor("picker", true, "build_chain (grab/anclaje)")

	for i in range(count - 1):
		var joint := Generic6DOFJoint3D.new()
		joint.name = "Pin%d_%d" % [i, i + 1]
		add_child(joint, true)
		var mid := _safe((_segments[i].global_position + _segments[i + 1].global_position) * 0.5)
		joint.global_transform = Transform3D(basis, mid)
		_configure_6dof(joint)
		joint.node_a = _segments[i].get_path()
		joint.node_b = _segments[i + 1].get_path()
		_joints.append(joint)

	_sync_joints()


func place_chain(start_pos: Vector3, end_pos: Vector3, offset: Vector3) -> void:
	if _segments.is_empty():
		return
	if _dynamic:
		if anchored_picker and _head_joint and is_instance_valid(_head_joint):
			_move_head_pin(_safe(end_pos) + _safe(offset))
		return
	var start := _safe(start_pos)
	var end := _safe(end_pos)
	start = _effective_spawn_start(start, end)
	var dist := start.distance_to(end)
	if dist < 0.001:
		return
	var material_len := _segments.size() * SEGMENT_LENGTH
	var needed := maxi(1, ceili(dist / SEGMENT_LENGTH))
	if dist > material_len or needed + 2 < _segments.size():
		build_chain(start_pos, end_pos, offset)
		return
	var off := _safe(offset)
	var basis := _safe_basis(_chain_basis(start, end))
	var count := _segments.size()
	var seg_len := dist / float(count)
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var pos := _safe(start.lerp(end, t) + off)
		_segments[i].global_transform = Transform3D(basis, pos)
		var child_shape := _segments[i].get_child(0) as CollisionShape3D
		if child_shape and child_shape.shape is BoxShape3D:
			(child_shape.shape as BoxShape3D).size = Vector3(0.006, 0.002, seg_len * 0.95)
		var mi := _segments[i].get_child(1) as MeshInstance3D
		if mi and mi.mesh is BoxMesh:
			(mi.mesh as BoxMesh).size = Vector3(0.006, 0.002, seg_len * 0.99)
	_sync_joints()


func _sync_joints() -> void:
	if _segments.is_empty():
		return
	for i in _joints.size():
		var joint := _joints[i]
		if not is_instance_valid(joint):
			continue
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		var basis := _safe_basis(_chain_basis(_segments[i].global_position, _segments[i + 1].global_position))
		var mid := _safe((_segments[i].global_position + _segments[i + 1].global_position) * 0.5)
		joint.global_transform = Transform3D(basis, mid)
		joint.node_a = _segments[i].get_path()
		joint.node_b = _segments[i + 1].get_path()
	if _anchor_joint and is_instance_valid(_anchor_joint):
		_anchor_joint.node_a = NodePath()
		_anchor_joint.node_b = NodePath()
		var basis := _safe_basis(_chain_basis(_segments[0].global_position, _segments[1].global_position if _segments.size() > 1 else _segments[0].global_position))
		_anchor_joint.global_transform = Transform3D(basis, _safe(_segments[0].global_position))
		_anchor_joint.node_a = _segments[0].get_path()
		_anchor_joint.node_b = _get_anchor_body_path()
	if _head_joint and is_instance_valid(_head_joint):
		_head_joint.node_a = NodePath()
		_head_joint.node_b = NodePath()
		var last := _segments.size() - 1
		var basis := _safe_basis(_chain_basis(_segments[last].global_position, _segments[last - 1].global_position if last > 0 else _segments[last].global_position))
		_head_joint.global_transform = Transform3D(basis, _safe(_segments[last].global_position))
		_head_joint.node_a = _segments[last].get_path()


func _move_head_pin(world_pos: Vector3) -> void:
	if not _head_joint or not is_instance_valid(_head_joint):
		return
	if _segments.is_empty():
		return
	_head_joint.node_a = NodePath()
	var basis := _safe_basis(_head_joint.global_basis)
	_head_joint.global_transform = Transform3D(basis, _safe(world_pos))
	_head_joint.node_a = _segments[_segments.size() - 1].get_path()


func cut_chain() -> void:
	var disp_body := _get_dispenser_body()
	_set_anchor("dispenser", false, "cut_chain (cut)")
	_dynamic = true
	if _anchor_joint:
		_anchor_joint.free()
		_anchor_joint = null
	if disp_body:
		for seg in _segments:
			if is_instance_valid(seg):
				seg.add_collision_exception_with(disp_body)
	if not anchored_picker:
		_drop_chain()
	else:
		unfreeze_chain()


func detach_after_reparent() -> void:
	unfreeze_chain()


func release_from_stringer() -> void:
	held = false
	_set_anchor("picker", false, "release_from_stringer (release)")
	_dynamic = true
	if _head_joint:
		_head_joint.queue_free()
		_head_joint = null
	if not anchored_dispenser:
		_drop_chain()
	else:
		unfreeze_chain()
		_start_settle_damping()


func _drop_chain() -> void:
	if anchored_dispenser or anchored_picker:
		return
	held = false
	_dynamic = true
	if _anchor_joint:
		_anchor_joint.queue_free()
		_anchor_joint = null
	if _head_joint:
		_head_joint.queue_free()
		_head_joint = null
	unfreeze_chain()
	set_transport_mode(true)


func _start_settle_damping() -> void:
	_settle_frames_left = SETTLE_FRAMES
	for seg in _segments:
		seg.linear_damp = SETTLE_DAMP_LINEAR
		seg.angular_damp = SETTLE_DAMP_ANGULAR


func _process(_delta: float) -> void:
	if _settle_frames_left <= 0:
		return
	_settle_frames_left -= 1
	if _settle_frames_left <= 0:
		for seg in _segments:
			if is_instance_valid(seg):
				seg.linear_damp = LINEAR_DAMP
				seg.angular_damp = ANGULAR_DAMP


func freeze_chain() -> void:
	for seg in _segments:
		seg.freeze = true
		seg.gravity_scale = 0
		seg.linear_velocity = Vector3.ZERO
		seg.angular_velocity = Vector3.ZERO
		seg.linear_damp = LINEAR_DAMP
		seg.angular_damp = ANGULAR_DAMP
	_settle_frames_left = 0


func unfreeze_chain() -> void:
	_sync_joints()
	for seg in _segments:
		var p := _safe(seg.global_position)
		if p.y < FLOOR_TOP + FLOOR_MARGIN:
			p.y = FLOOR_TOP + FLOOR_MARGIN
			seg.global_position = p
		seg.linear_velocity = Vector3.ZERO
		seg.angular_velocity = Vector3.ZERO
		seg.freeze = false
		seg.sleeping = false
		seg.gravity_scale = fall_gravity_scale


func has_chain() -> bool:
	return not _segments.is_empty()


func get_segment_count() -> int:
	return _segments.size()


func get_segment(index: int) -> RigidBody3D:
	if index < 0 or index >= _segments.size():
		return null
	return _segments[index]


## Transport mode improves how a free tira slides on a conveyor: segments
## stay awake, damping is lowered, lateral/twist limits and linear slack are
## loosened so the belt can drag the chain without fighting stiff joints, and
## segment friction is raised for better surface transfer.
func set_transport_mode(enabled: bool) -> void:
	if _transport_mode == enabled:
		return
	_transport_mode = enabled
	_lateral_limit_deg = TRANSPORT_LATERAL_LIMIT_DEG if enabled else LATERAL_LIMIT_DEG
	_twist_limit_deg = TRANSPORT_TWIST_LIMIT_DEG if enabled else TWIST_LIMIT_DEG
	_linear_limit_m = TRANSPORT_LINEAR_LIMIT if enabled else LINEAR_LIMIT
	var lin_damp := TRANSPORT_LINEAR_DAMP if enabled else LINEAR_DAMP
	var ang_damp := TRANSPORT_ANGULAR_DAMP if enabled else ANGULAR_DAMP
	if _seg_physics_material:
		_seg_physics_material.friction = TRANSPORT_FRICTION if enabled else 0.6
	for seg in _segments:
		if not is_instance_valid(seg):
			continue
		seg.can_sleep = not enabled
		seg.linear_damp = lin_damp
		seg.angular_damp = ang_damp
	for joint in _joints:
		if is_instance_valid(joint):
			_apply_6dof_limits(joint)


## When true the chain is frozen and its segments' collisions are disabled so
## it can ride a Sandwich composite sled as a passive, visual-only layer.
func set_composite_mode(composite: bool) -> void:
	if _in_composite == composite:
		return
	_in_composite = composite
	if composite:
		var rg := global_transform
		top_level = false
		global_transform = rg
		held = false
		_dynamic = false
		freeze_chain()
		_free_joints()
		for seg in _segments:
			if is_instance_valid(seg):
				seg.collision_layer = 0
				seg.collision_mask = 0
	else:
		for seg in _segments:
			if is_instance_valid(seg):
				seg.collision_layer = 10
				seg.collision_mask = 15


func _free_joints() -> void:
	if _anchor_joint and is_instance_valid(_anchor_joint):
		_anchor_joint.queue_free()
		_anchor_joint = null
	if _head_joint and is_instance_valid(_head_joint):
		_head_joint.queue_free()
		_head_joint = null
	for joint in _joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_joints.clear()


func clear_chain() -> void:
	_anchor_joint = null
	_head_joint = null
	_joints.clear()
	_set_anchor("dispenser", false, "clear_chain (rebuild)")
	_set_anchor("picker", false, "clear_chain (rebuild)")
	_dynamic = false
	for child in get_children():
		if child.name == "Placeholder":
			continue
		child.free()
	_segments.clear()
	if not _dynamic:
		_show_placeholder()


func _show_placeholder() -> void:
	if not Engine.is_editor_hint():
		return
	var ph := get_node_or_null("Placeholder") as Node3D
	if ph:
		ph.visible = true


func _hide_placeholder() -> void:
	if not Engine.is_editor_hint():
		return
	var ph := get_node_or_null("Placeholder") as Node3D
	if ph:
		ph.visible = false


func _on_simulation_started() -> void:
	if _in_composite:
		return
	if held and not _dynamic:
		return
	unfreeze_chain()
	if _dynamic and anchored_dispenser and not anchored_picker:
		_start_settle_damping()


func _on_simulation_ended() -> void:
	# Si la tira vive en un TiraBundleExample (escena de ejemplo/referencia),
	# NUNCA se auto-elimina: solo desaparece si alguien la despawna explicitamente
	# (queue_free). Evita el timing de _ready/señales que borraba las tiras al parar.
	if _inside_example_bundle():
		freeze_chain()
		return
	if not remove_on_stop:
		if _in_composite:
			return
		freeze_chain()
		return
	queue_free()


func _inside_example_bundle() -> bool:
	var n: Node = get_parent()
	while n:
		if n is TiraBundleExample:
			return true
		n = n.get_parent()
	return false
