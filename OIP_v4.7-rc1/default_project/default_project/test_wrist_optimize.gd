extends SceneTree

const MAX_ITERATIONS := 240
const JACOBIAN_STEP_DEG := 0.01

var _robot: Node3D
var _pickup_basis: Basis
var _target_object_basis: Basis = Basis.IDENTITY
var _target_pickup_basis: Basis = Basis.IDENTITY


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://Simulation.tscn")
	if scene == null:
		print("FAIL: Simulation scene")
		quit(1)
		return

	var instance: Node3D = scene.instantiate()
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(instance)

	_robot = instance.get_node("SixAxisRobot") as Node3D
	if _robot == null:
		print("FAIL: Robot node")
		quit(1)
		return

	var waypoints: Dictionary = _robot.waypoints
	var keys: Array = waypoints.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(str(a).get_slice(": ", 0)) < int(str(b).get_slice(": ", 0)))

	if keys.size() < 2:
		print("FAIL: missing waypoints")
		quit(1)
		return

	# The test blocks start with identity rotation. This is the head orientation
	# captured by the robot and later composed with every deposit orientation.
	var pickup_angles: Array = waypoints[str(keys[0])]
	_target_pickup_basis = Basis.from_euler(Vector3(0.0, 0.0, PI))
	var pickup_start: Array[float] = [pickup_angles[0], pickup_angles[1], pickup_angles[2], pickup_angles[3], pickup_angles[4], pickup_angles[5]]
	var pickup_result: Array = _solve_wrist_for_target(pickup_start, _target_pickup_basis)
	var solved_pickup: Array[float] = pickup_result[0]
	_set_angles(solved_pickup)
	_pickup_basis = _tool_basis()
	_target_object_basis = Basis.from_euler(Vector3(0.0, deg_to_rad(90.0), 0.0))

	print("Target block basis: Euler(0.000, 90.000, 0.000)")
	print("Point1 pickup angles: [%.8f, %.8f, %.8f, %.8f, %.8f, %.8f]" % solved_pickup)
	print("Pickup head basis: %s" % _format_basis(_pickup_basis))
	print("")

	for i in range(1, keys.size()):
		var key: String = str(keys[i])
		var source: Array = waypoints[key]
		var angles: Array[float] = [source[0], source[1], source[2], source[3], source[4], source[5]]
		_set_angles(angles)
		var target_position: Vector3 = _robot.get_tool_tip_position()
		var result: Array = _solve_wrist(angles)
		var solved: Array[float] = result[0]
		_set_angles(solved)

		var tool_basis: Basis = _tool_basis()
		var object_basis: Basis = (tool_basis * _pickup_basis.inverse()).orthonormalized()
		var error: float = _rotation_error(object_basis, _target_object_basis)
		var object_euler: Vector3 = _basis_euler_deg(object_basis)
		var pos_error: float = _robot.get_tool_tip_position().distance_to(target_position)

		print("%s" % key)
		print("  [%.8f, %.8f, %.8f, %.8f, %.8f, %.8f]" % solved)
		print("  block Euler=(%.6f, %.6f, %.6f) error=%.9f rad pos_delta=%.9f m" % [
			object_euler.x, object_euler.y, object_euler.z, error, pos_error])
		print("")

	quit(0)


func _set_angles(angles: Array[float]) -> void:
	_robot.set_joint_angles(angles)


func _tool_basis() -> Basis:
	return _robot.get_tool_tip_transform().basis.orthonormalized()


func _solve_wrist(start: Array[float]) -> Array:
	var target_tool: Basis = (_target_object_basis * _pickup_basis).orthonormalized()
	return _solve_wrist_for_target(start, target_tool)


func _solve_wrist_for_target(start: Array[float], target_tool: Basis) -> Array:
	var best: Array[float] = _clamp_angles(start)
	_set_angles(best)
	var best_error: float = _orientation_error(target_tool, _tool_basis()).length()
	for d4 in [-180.0, 0.0, 180.0]:
		for d5 in [-90.0, 0.0, 90.0]:
			for d6 in [-180.0, 0.0, 180.0]:
				var seed: Array[float] = _clamp_angles(start)
				seed[3] = clampf(seed[3] + d4, -180.0, 180.0)
				seed[4] = clampf(seed[4] + d5, -120.0, 120.0)
				seed[5] = clampf(seed[5] + d6, -360.0, 360.0)
				var candidate: Array = _iterate_wrist(seed, target_tool)
				if candidate[1] < best_error:
					best = candidate[0]
					best_error = candidate[1]
	return [best, best_error]


func _iterate_wrist(start: Array[float], target_tool: Basis) -> Array:
	var current: Array[float] = start.duplicate()
	var lambda: float = 0.001
	for _iteration in range(MAX_ITERATIONS):
		_set_angles(current)
		var current_basis: Basis = _tool_basis()
		var residual: Vector3 = _orientation_error(target_tool, current_basis)
		var residual_len: float = residual.length()
		if residual_len < 1.0e-10:
			break

		var jacobian: Array = _orientation_jacobian(current, target_tool, residual)
		var normal: Array = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		var rhs: Array = [0.0, 0.0, 0.0]
		for row in range(3):
			for col in range(3):
				for axis in range(3):
					normal[row][col] += jacobian[axis][row] * jacobian[axis][col]
				normal[row][col] += lambda if row == col else 0.0
			for axis in range(3):
				rhs[row] -= jacobian[axis][row] * residual[axis]

		var delta: Array = _solve_3x3(normal, rhs)
		if delta.is_empty():
			break
		var step := Vector3(delta[0], delta[1], delta[2])
		if step.length() > 10.0:
			step = step.normalized() * 10.0

		var trial: Array[float] = current.duplicate()
		trial[3] = clampf(trial[3] + step.x, -180.0, 180.0)
		trial[4] = clampf(trial[4] + step.y, -120.0, 120.0)
		trial[5] = clampf(trial[5] + step.z, -360.0, 360.0)
		_set_angles(trial)
		var trial_error: float = _orientation_error(target_tool, _tool_basis()).length()
		var current_error: float = residual_len
		if trial_error < current_error:
			current = trial
			lambda = maxf(lambda * 0.5, 1.0e-8)
		else:
			_set_angles(current)
			lambda = minf(lambda * 5.0, 1000.0)

	_set_angles(current)
	return [_clamp_angles(current), _orientation_error(target_tool, _tool_basis()).length()]


func _orientation_jacobian(current: Array[float], target_tool: Basis, base_residual: Vector3) -> Array:
	var result: Array = [
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0]
	]
	for wrist in range(3):
		var perturbed: Array[float] = current.duplicate()
		perturbed[3 + wrist] += JACOBIAN_STEP_DEG
		_set_angles(perturbed)
		var delta: Vector3 = (_orientation_error(target_tool, _tool_basis()) - base_residual) / JACOBIAN_STEP_DEG
		result[0][wrist] = delta.x
		result[1][wrist] = delta.y
		result[2][wrist] = delta.z
	_set_angles(current)
	return result


func _rotation_vector(target: Basis, current: Basis) -> Vector3:
	return _rotation_vector_between(current.get_rotation_quaternion(), target.get_rotation_quaternion())


func _basis_residual(target: Basis, current: Basis) -> Vector3:
	# Skew part of target * current^-1. This remains measurable near the
	# vertical tool pose where Euler angles and quaternion angle are ill-conditioned.
	var relative: Basis = target * current.inverse()
	return Vector3(
		relative.z.y - relative.y.z,
		relative.x.z - relative.z.x,
		relative.y.x - relative.x.y
	) * 0.5


func _orientation_error(target: Basis, current: Basis) -> Vector3:
	# Use axis-angle for large errors and basis axes near the target. The latter
	# preserves sub-degree corrections that are lost by quaternion float rounding.
	var angle: float = _angular_error(target, current)
	if angle < 0.5:
		return _basis_residual(target, current)
	return _rotation_vector(target, current)


func _rotation_vector_between(from: Quaternion, to: Quaternion) -> Vector3:
	var error: Quaternion = to * from.inverse()
	if error.w < 0.0:
		error = Quaternion(-error.x, -error.y, -error.z, -error.w)
	var angle: float = error.get_angle()
	if angle < 1.0e-8:
		return Vector3.ZERO
	return error.get_axis().normalized() * angle


func _rotation_error(a: Basis, b: Basis) -> float:
	return _orientation_error(a, b).length()


func _angular_error(target: Basis, current: Basis) -> float:
	var a: Quaternion = target.get_rotation_quaternion()
	var b: Quaternion = current.get_rotation_quaternion()
	var dot: float = absf(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
	return 2.0 * acos(clampf(dot, -1.0, 1.0))


func _basis_euler_deg(basis: Basis) -> Vector3:
	var radians: Vector3 = basis.get_euler()
	return Vector3(rad_to_deg(radians.x), rad_to_deg(radians.y), rad_to_deg(radians.z))


func _clamp_angles(angles: Array[float]) -> Array[float]:
	var result: Array[float] = angles.duplicate()
	result[3] = clampf(result[3], -180.0, 180.0)
	result[4] = clampf(result[4], -120.0, 120.0)
	result[5] = clampf(result[5], -360.0, 360.0)
	return result


func _solve_3x3(matrix: Array, rhs: Array) -> Array:
	var det: float = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) \
		- matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) \
		+ matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
	if absf(det) < 1.0e-12:
		return []

	var inverse: Array = [
		[(matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) / det,
			(matrix[0][2] * matrix[2][1] - matrix[0][1] * matrix[2][2]) / det,
			(matrix[0][1] * matrix[1][2] - matrix[0][2] * matrix[1][1]) / det],
		[(matrix[1][2] * matrix[2][0] - matrix[1][0] * matrix[2][2]) / det,
			(matrix[0][0] * matrix[2][2] - matrix[0][2] * matrix[2][0]) / det,
			(matrix[0][2] * matrix[1][0] - matrix[0][0] * matrix[1][2]) / det],
		[(matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]) / det,
			(matrix[0][1] * matrix[2][0] - matrix[0][0] * matrix[2][1]) / det,
			(matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]) / det]
	]
	return [
		inverse[0][0] * rhs[0] + inverse[0][1] * rhs[1] + inverse[0][2] * rhs[2],
		inverse[1][0] * rhs[0] + inverse[1][1] * rhs[1] + inverse[1][2] * rhs[2],
		inverse[2][0] * rhs[0] + inverse[2][1] * rhs[1] + inverse[2][2] * rhs[2]
	]


func _format_basis(basis: Basis) -> String:
	return "X(%.3f,%.3f,%.3f) Y(%.3f,%.3f,%.3f) Z(%.3f,%.3f,%.3f)" % [
		basis.x.x, basis.x.y, basis.x.z,
		basis.y.x, basis.y.y, basis.y.z,
		basis.z.x, basis.z.y, basis.z.z]
