@tool
extends Node3D

@export var auto_run: bool = false

var robot: Node3D = null
var blocks: Array = []
var wp_keys: Array = []
var _phase: String = "idle"
var _timer: float = 0.0
var _deposit_idx: int = 0
var _current_block: Node3D = null
var _start_delay: float = 0.0
var _results: Array = []

func _ready() -> void:
	print("=== TestRobotGrid _ready() ===")
	robot = $Robot
	if robot == null:
		push_error("No Robot node found"); return

	for child in get_children():
		if child is RigidBody3D and child.name.begins_with("TestBlock"):
			blocks.append(child)

	wp_keys = robot.waypoints.keys()
	wp_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ai: int = int(a.get_slice(": ", 0))
		var bi: int = int(b.get_slice(": ", 0))
		return ai < bi)

	if Engine.is_editor_hint():
		print("  Editor mode — skipping runtime")
		return

	print("  Runtime mode — auto_run=%s" % str(auto_run))
	print("  Found %d blocks, %d waypoints" % [blocks.size(), wp_keys.size()])
	_start_delay = 0.5


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not auto_run:
		return

	if _start_delay > 0.0:
		_start_delay -= delta
		if _start_delay <= 0.0:
			print("Starting cycle...")
			_start_cycle()
		return

	if _phase == "idle" or _phase == "done":
		return

	_timer += delta

	if _phase == "goto_pickup":
		if robot.is_moving():
			_timer = 0.0
			return
		if _timer >= 0.5:
			print("At pickup — enabling vacuum...")
			robot.vacuum_on = true
			_phase = "pickup_wait"
			_timer = 0.0

	elif _phase == "pickup_wait":
		if _timer >= 2.0:
			if robot.holding_object:
				var bname: String = str(_current_block.name) if _current_block != null else "?"
				print("  Holding %s — moving to deposit" % bname)
				_move_to_waypoint(_deposit_idx + 1)
				_phase = "goto_deposit"
				_timer = 0.0
			else:
				print("  FAILED to pick up. Retrying...")
				robot.vacuum_on = false
				_timer = 0.0
				_phase = "goto_pickup"

	elif _phase == "goto_deposit":
		if robot.is_moving():
			_timer = 0.0
			return
		if _timer >= 0.5:
			print("At deposit — releasing...")
			robot.vacuum_on = false
			_phase = "release_wait"
			_timer = 0.0

	elif _phase == "release_wait":
		if _timer >= 1.0:
			_check_rotation()
			_deposit_idx += 1
			_current_block = null
			_timer = 0.0
			if _deposit_idx >= wp_keys.size() - 1:
				_print_summary()
				_phase = "done"
			else:
				_move_to_waypoint(0)
				_phase = "goto_pickup"


func _start_cycle() -> void:
	_deposit_idx = 0
	_current_block = null
	robot.vacuum_on = false
	_move_to_waypoint(0)
	_phase = "goto_pickup"


func _move_to_waypoint(idx: int) -> void:
	var key: String = str(wp_keys[idx])
	var angles: Array = robot.waypoints[key]
	robot.move_to_position(angles)
	print("Moving to %s" % key)


func _check_rotation() -> void:
	var tip: Vector3 = robot.get_tool_tip_position()
	var closest_block: Node3D = null
	var closest_dist: float = 999999.0

	for i in blocks.size():
		var block: Node3D = blocks[i] as Node3D
		var block_pos: Vector3 = block.global_position
		var d: float = block_pos.distance_to(tip)
		if d < closest_dist:
			closest_dist = d
			closest_block = block

	if _current_block != null and is_instance_valid(_current_block):
		var d2: float = _current_block.global_position.distance_to(tip)
		if d2 < closest_dist:
			closest_dist = d2
			closest_block = _current_block

	if closest_block == null or closest_dist > 2.0:
		print("  WARNING: no block near tip (dist=%.2f)" % closest_dist)
		_results.append({"wp": str(wp_keys[_deposit_idx + 1]), "block": "?", "status": "NO BLOCK"})
		return

	closest_block.freeze = true
	var basis: Basis = closest_block.global_transform.basis.orthonormalized()
	var euler_rad: Vector3 = basis.get_euler()
	var euler_x: float = rad_to_deg(euler_rad.x)
	var euler_y: float = rad_to_deg(euler_rad.y)
	var euler_z: float = rad_to_deg(euler_rad.z)
	var pos: Vector3 = closest_block.global_position

	var dx: float = absf(euler_x)
	var dy: float = minf(absf(euler_y - 90.0), absf(euler_y + 90.0))
	var dz: float = absf(euler_z)
	var status: String = "OK" if (dx < 0.001 and dy < 0.001 and dz < 0.001) else "NEEDS FIX"

	print("  %s @ %s => Euler(%.6f, %.6f, %.6f) [%s]" % [
		str(closest_block.name), str(wp_keys[_deposit_idx + 1]),
		euler_x, euler_y, euler_z, status])

	_results.append({
		"wp": str(wp_keys[_deposit_idx + 1]),
		"block": str(closest_block.name),
		"pos": pos,
		"euler": Vector3(euler_x, euler_y, euler_z),
		"status": status
	})


func _print_summary() -> void:
	print("")
	print("==========================================")
	print("  DEPOSIT SUMMARY")
	print("==========================================")
	for r in _results:
		if r.has("pos"):
			var p: Vector3 = r["pos"] as Vector3
			var e: Vector3 = r["euler"] as Vector3
			print("  %s | %s | pos=(%.3f, %.3f, %.3f) | rot=(%.6f, %.6f, %.6f) | %s" % [
				r["wp"], r["block"],
				p.x, p.y, p.z,
				e.x, e.y, e.z,
				r["status"]])
		else:
			print("  %s | %s | %s" % [r["wp"], r["block"], r["status"]])
	print("==========================================")
