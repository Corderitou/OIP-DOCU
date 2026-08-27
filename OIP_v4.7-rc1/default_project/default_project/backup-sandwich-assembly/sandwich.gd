@tool
class_name Sandwich
extends Node3D

## Composite "sandwich" (Placer / Tira / Celda / Tira) that rides a conveyor as
## a single rigid body ("sled") so it advances cleanly instead of snagging on
## the jointed tira floor. Parts are frozen and collision-disabled while
## assembled; the sled is the only physics body contacting the belt.

const SLED_HEIGHT := 0.01
const SLED_FOOTPRINT := 0.156

var assembled := false
var _parts: Dictionary = {}
var _part_nodes: Array[Node3D] = []
var _sled: RigidBody3D = null


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)


func _exit_tree() -> void:
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.disconnect(_on_simulation_ended)


func _ready() -> void:
	_sled = get_node_or_null("RigidBody3D") as RigidBody3D


func get_sled() -> RigidBody3D:
	if not _sled:
		_sled = get_node_or_null("RigidBody3D") as RigidBody3D
	return _sled


func has_part(key: String) -> bool:
	return _parts.has(key)


func get_part(key: String):
	return _parts.get(key, null)


## Assemble the sandwich from a dictionary of parts. Recognized keys:
## "placer", "celda" (single Node3D) and "tira_bottom" / "tira_top" (Node3D or
## Array[Node3D]). At least "celda" is required. Returns true on success.
func assemble(parts: Dictionary) -> bool:
	print("[Sandwich] assemble() inicio: keys=%s sled=%s" % [parts.keys(), get_sled() != null])
	if assembled:
		push_warning("Sandwich: already assembled")
		return false
	_sled = get_sled()
	if _sled == null:
		push_warning("Sandwich: sled RigidBody3D not found")
		return false
	if not parts.has("celda"):
		push_warning("Sandwich: missing celda, cannot assemble")
		return false

	_parts = parts.duplicate(true)
	_rebuild_part_nodes()

	# Position the sled under the stack so its box sits on the belt.
	var xform := _compute_sled_transform()
	_sled.top_level = true
	_sled.global_transform = xform
	_sled.collision_layer = 10
	# Only collide with Static/Belt surfaces (layer 1): the sled is the belt's
	# grip but must NOT push/lift incoming parts, or it catches the next stack.
	_sled.collision_mask = 1
	_sled.freeze = not Simulation.is_running()
	_sled.can_sleep = false
	_sled.continuous_cd = true
	_sled.mass = _sum_mass()
	_sled.linear_velocity = Vector3.ZERO
	_sled.angular_velocity = Vector3.ZERO

	# Flatten the sled's collider to SLED_HEIGHT so its top stays flush with
	# the belt floor instead of forming a lip that can catch parts.
	var sled_shape := _sled.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if sled_shape and sled_shape.shape is BoxShape3D:
		var b := sled_shape.shape as BoxShape3D
		b.size = Vector3(b.size.x, SLED_HEIGHT, b.size.z)

	# Take ownership of each part: freeze it into composite mode first (so its
	# _exit_tree during reparent does not queue_free runtime instances), then
	# reparent under the sled keeping the global transform.
	for part in _part_nodes:
		_attach_part(part)

	assembled = true
	print("[Sandwich] assemble() OK, sled en ", _sled.global_position, " partes=", _parts.keys())
	return true


## Detach a part group back to the scene as independent dynamic bodies.
## Accepts single nodes and arrays (tira_bottom / tira_top). Returns the freed
## node, the array of freed nodes, or null.
func detach_part(key: String):
	if not assembled:
		return null
	if not _parts.has(key):
		return null
	var value = _parts[key]
	if value is Array:
		var detached: Array = []
		for n in value:
			var part := _detach_node(n as Node3D)
			if part:
				detached.append(part)
		_parts.erase(key)
		_rebuild_part_nodes()
		return detached
	var part := _detach_node(value as Node3D)
	_parts.erase(key)
	_rebuild_part_nodes()
	return part


func detach_placer() -> Node3D:
	return detach_part("placer")


func _detach_node(part: Node3D) -> Node3D:
	if part == null or not is_instance_valid(part):
		return null
	var gt := part.global_transform
	var sled := get_sled()
	if sled and part.get_parent() == sled:
		sled.remove_child(part)
	else:
		var p := part.get_parent()
		if p:
			p.remove_child(part)
	var root := Tira.get_common_container(self) if is_inside_tree() else null
	if root:
		root.add_child(part, true)
		part.global_transform = gt
		part.owner = root
	else:
		add_child(part, true)
		part.global_transform = gt
	if part.has_method("set_composite_mode"):
		part.set_composite_mode(false)
	return part


func _rebuild_part_nodes() -> void:
	_part_nodes.clear()
	for key in _parts:
		var value = _parts[key]
		if value is Array:
			for n in value:
				if n is Node3D and is_instance_valid(n):
					_part_nodes.append(n)
		elif value is Node3D and is_instance_valid(value):
			_part_nodes.append(value)


func _attach_part(part: Node3D) -> void:
	if part.has_method("set_composite_mode"):
		part.set_composite_mode(true)
	var gt := part.global_transform
	part.reparent(_sled, true)
	part.global_transform = gt


func _on_simulation_started() -> void:
	if _sled:
		_sled.freeze = false


func _on_simulation_ended() -> void:
	if _sled:
		_sled.freeze = true
		_sled.linear_velocity = Vector3.ZERO
		_sled.angular_velocity = Vector3.ZERO


func _compute_sled_transform() -> Transform3D:
	# Los roots contenedor (Celda/Placer) quedan anclados a su spawn mientras
	# sus RigidBody3D top_level van por la cinta, asi que x/z NO pueden salir de
	# `celda.global_position`. Centramos el sled en el body de la celda (el
	# producto) y apoyamos su base en el suelo real: el bottom mas bajo de todos
	# los bodies (las tiras reposando en la cinta). El top del sled queda a nivel
	# del suelo para no crear un labio que levante la pila o la siguiente parte.
	var celda := _parts.get("celda") as Node3D
	var center_ref: Array[RigidBody3D] = []
	var all_bodies: Array[RigidBody3D] = []
	for part in _part_nodes:
		if part == null or not is_instance_valid(part):
			continue
		var bodies := _collect_bodies(part)
		all_bodies.append_array(bodies)
		if part == celda:
			center_ref.append_array(bodies)
	if center_ref.is_empty():
		center_ref = all_bodies

	var sum := Vector3.ZERO
	var count := 0
	var floor_y := INF
	for body in all_bodies:
		if not is_instance_valid(body):
			continue
		var p: Vector3 = body.global_position
		var half_y := _body_half_height(body)
		floor_y = minf(floor_y, p.y - half_y)
	for body in center_ref:
		if is_instance_valid(body):
			sum += body.global_position
			count += 1

	if count == 0:
		return Transform3D(Basis.IDENTITY, Vector3(global_position.x, global_position.y, global_position.z))
	if not is_finite(floor_y):
		floor_y = global_position.y
	var center := sum / count
	var cy := floor_y - SLED_HEIGHT * 0.5
	cy = _clamp_to_floor(cy, center)
	return Transform3D(Basis.IDENTITY, Vector3(center.x, cy, center.z))


## Safety net against the sled hovering above the belt: if the computed floor
## sits clearly above the static surface below (e.g. a stack assembled before
## settling), snap the sled down so its top never leaves the belt surface.
func _clamp_to_floor(cy: float, center: Vector3) -> float:
	const TOLERANCE := 0.02
	var world := _sled.get_world_3d() if _sled and _sled.get_world_3d() else null
	if world == null:
		return cy
	var from := Vector3(center.x, cy + 0.5, center.z)
	var to := Vector3(center.x, cy - 0.5, center.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return cy
	var belt_top: float = hit.position.y
	if cy + SLED_HEIGHT * 0.5 > belt_top + TOLERANCE:
		return belt_top - SLED_HEIGHT * 0.5
	return cy


func _body_half_height(body: RigidBody3D) -> float:
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		return (cs.shape as BoxShape3D).size.y * 0.5
	return 0.005


func _collect_bodies(node: Node) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	if node is RigidBody3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_bodies(c))
	return out


func _sum_mass() -> float:
	var total := 0.0
	for part in _part_nodes:
		if part == null:
			continue
		for body in _collect_bodies(part):
			if is_instance_valid(body):
				total += body.mass
	if total <= 0.0:
		total = 0.1
	return total