@tool
class_name Stringer
extends Node3D

@export_category("Axis Positions")
@export_range(0.0, 2.0, 0.001, "suffix:m") var z_position: float = 0.0:
	set(value):
		z_position = clampf(value, z_range.x, z_range.y)
		_update_position()
		_poll_dispenser_detection()

@export_range(0.0, 2.0, 0.001, "suffix:m") var y_position: float = 0.0:
	set(value):
		y_position = clampf(value, y_range.x, y_range.y)
		_update_position()
		_poll_dispenser_detection()

@export_category("Limits")
@export var z_range: Vector2 = Vector2(0.0, 1.5)
@export var y_range: Vector2 = Vector2(0.0, 1.0)

@export_category("Motion")
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var motion_speed: float = 1.0

@export_category("Actions")
@export var release_trigger: bool = false:
	set(v):
		if v:
			release()
		release_trigger = false

var _head: Node3D
var _picker: Node3D
var _detected_dispenser: Dispenser = null
var _is_moving: bool = false
var _detect_distance: float = 0.6
var _motion_tween: Tween = null

var _held_tiras: Array[Node3D] = []
var _held_dispenser: Dispenser = null
var _can_regrab: bool = true

const _POLL_INTERVAL := 0.1
const PICKER_EDGE_MARGIN: float = 0.012
var _poll_timer: float = 0.0


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer < _POLL_INTERVAL:
		return
	_poll_timer = 0.0
	if is_inside_tree():
		_poll_dispenser_detection()


func _ready() -> void:
	_head = get_node_or_null("Head")
	_picker = get_node_or_null("Head/picker")
	_update_position()
	_poll_dispenser_detection()


func _get_end_anchor() -> Node3D:
	return _picker if _picker else _head


func _effective_end_pos(origin: Node3D) -> Vector3:
	var picker := _get_end_anchor()
	if not picker or not is_instance_valid(picker):
		return _head.global_position if _head else global_position
	var center := picker.global_position
	if not origin or not is_instance_valid(origin):
		return center
	var delta := origin.global_position - center
	if delta.length_squared() < 1e-8:
		return center
	var dir := delta.normalized()
	var ad := Vector3(absf(dir.x), absf(dir.y), absf(dir.z))
	var reach := _global_half_size(picker).dot(ad)
	return center + dir * (reach + PICKER_EDGE_MARGIN)


func _poll_dispenser_detection() -> void:
	if not is_inside_tree():
		return

	if not _held_tiras.is_empty() and _head:
		_update_tira_extensions()
		return

	var end_anchor := _get_end_anchor()
	var head_pos: Vector3
	if end_anchor:
		head_pos = end_anchor.global_position
	elif _head:
		head_pos = _head.global_position
	else:
		head_pos = global_position

	var closest: Dispenser = null
	var closest_dist := INF

	var tree := get_tree()
	if not tree:
		return
	var root := Tira.get_common_container(self)
	if not root:
		return
	for d in root.find_children("*", "Dispenser", true, false):
		var disp := d as Dispenser
		if not disp:
			continue
		var origin := disp.get_spawn_origin()
		if not origin:
			continue
		var dist := head_pos.distance_to(origin.global_position)
		var thresh := _detect_distance
		if end_anchor:
			thresh = minf(_contact_threshold(end_anchor, origin), _detect_distance)
		if dist < thresh and dist < closest_dist:
			closest_dist = dist
			closest = disp
	if closest:
		if not _can_regrab:
			return
		if closest.has_active_tira():
			return
		if closest != _detected_dispenser:
			_detected_dispenser = closest
			closest.set_detected(true)
			grab(closest)
	else:
		_can_regrab = true
		if _detected_dispenser:
			_detected_dispenser.set_detected(false)
			_detected_dispenser = null


func _global_half_size(node: Node3D) -> Vector3:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return Vector3(0.02, 0.02, 0.02)
	var aabb := mi.get_aabb()
	var lo := aabb.position
	var hi := aabb.end
	var minv := Vector3.INF
	var maxv := -Vector3.INF
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var corner := Vector3(lo.x if ix == 0 else hi.x, lo.y if iy == 0 else hi.y, lo.z if iz == 0 else hi.z)
				var wp := node.global_transform * corner
				minv = minv.min(wp)
				maxv = maxv.max(wp)
	return (maxv - minv) * 0.5


func _contact_threshold(picker: Node3D, origin: Node3D) -> float:
	var delta := origin.global_position - picker.global_position
	var dir := delta.normalized() if delta.length_squared() > 1e-8 else Vector3.FORWARD
	var ad := Vector3(absf(dir.x), absf(dir.y), absf(dir.z))
	var hp := _global_half_size(picker)
	var ho := _global_half_size(origin)
	return hp.dot(ad) + ho.dot(ad) + 0.015


func _update_position() -> void:
	if not _head:
		return
	_head.position = Vector3(0.0, y_position, z_position)


func move_to(z: float, y: float) -> void:
	z = clampf(z, z_range.x, z_range.y)
	y = clampf(y, y_range.x, y_range.y)

	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()

	_is_moving = true
	var dz := absf(z - z_position)
	var dy := absf(y - y_position)
	var max_dist := maxf(dz, dy)
	var duration := maxf(max_dist / motion_speed, 0.1)

	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.tween_property(self, "z_position", z, duration)
	_motion_tween.tween_property(self, "y_position", y, duration)
	_motion_tween.chain().tween_callback(_on_motion_complete)


func _on_motion_complete() -> void:
	_is_moving = false


func is_moving() -> bool:
	return _is_moving


func get_head_position() -> Vector3:
	if _head and is_inside_tree():
		return _head.global_position
	return global_position


func stop_motion() -> void:
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()
	_is_moving = false


func grab(dispenser: Dispenser) -> bool:
	if not _held_tiras.is_empty():
		return false
	if dispenser.has_active_tira():
		return false
	if not _head:
		return false

	var sp := dispenser.get_spawn_origin()
	var start_pos := sp.global_position if sp else global_position
	var end_pos := _effective_end_pos(sp)
	var spacing := dispenser.tira_spacing
	var lateral := Tira.lateral_axis(start_pos, end_pos)

	var tiras := dispenser.spawn_tira(end_pos)
	if tiras.is_empty():
		return false

	_held_tiras = tiras.duplicate()
	_held_dispenser = dispenser

	for i in _held_tiras.size():
		var tira_node := _held_tiras[i]
		if not tira_node:
			continue
		var tira := tira_node as Tira
		if not tira:
			continue
		tira.held = true
		var offset := lateral * (float(i) - 0.5) * spacing
		tira.top_level = false
		tira.build_chain(start_pos, end_pos, offset)

	_update_tira_extensions()
	return true


func _update_tira_extensions() -> void:
	if _held_tiras.is_empty() or not _head or not _held_dispenser:
		return

	var sp := _held_dispenser.get_spawn_origin()
	if not sp:
		return

	var start_pos := sp.global_position
	var end_pos := _effective_end_pos(sp)
	var spacing := _held_dispenser.tira_spacing
	var lateral := Tira.lateral_axis(start_pos, end_pos)

	for i in _held_tiras.size():
		var tira_node := _held_tiras[i]
		if not tira_node:
			continue
		var tira := tira_node as Tira
		if not tira or not tira.has_chain():
			continue
		var offset := lateral * (float(i) - 0.5) * spacing
		tira.place_chain(start_pos, end_pos, offset)


func release() -> Node3D:
	if _held_tiras.is_empty():
		return null

	for tira_node in _held_tiras:
		if not tira_node:
			continue
		var gt := tira_node.global_transform
		tira_node.top_level = true
		tira_node.global_transform = gt
		var tira := tira_node as Tira
		if tira:
			tira.release_from_stringer()

	_held_tiras.clear()
	_held_dispenser = null
	_can_regrab = false

	if _detected_dispenser:
		_detected_dispenser.set_detected(false)
		_detected_dispenser = null

	return null
