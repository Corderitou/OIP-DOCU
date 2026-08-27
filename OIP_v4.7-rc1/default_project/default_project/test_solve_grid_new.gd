extends SceneTree

const SIM_SCENE := "res://Simulation.tscn"
const UNIT_SPACING := 0.172
const COL_PITCH := 1.2 * UNIT_SPACING
const ROW_PITCH := 6.2 * UNIT_SPACING
const OLD_CENTER_X := -8.9336
const OLD_CENTER_Z := -12.7997
const MAX_WRIST_ITERS := 240
const WRIST_STEP_DEG := 0.01
const WRIST_LAMBDA_INIT := 0.001
const WRIST_MAX_STEP := 10.0
const LM_ITERS := 300
const LM_STEP_CLAMP := 8.0
const LM_DT := 0.01

var _robot: Node3D
var _pickup_basis: Basis
var _target_object_basis: Basis = Basis.from_euler(Vector3(0.0, deg_to_rad(90.0), 0.0))


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load(SIM_SCENE)
	if scene == null:
		print("FAIL: load Simulation"); quit(1); return
	var instance: Node3D = scene.instantiate()
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(instance)
	_robot = instance.get_node("SixAxisRobot") as Node3D
	if _robot == null:
		print("FAIL: robot node"); quit(1); return

	var p1_angles: Array[float] = [29.82666699, -2.9, 101.1, 0.00000053, 81.79999916, 29.82665835]
	_set_angles(p1_angles)
	_pickup_basis = _tool_basis()

	print("Old grid center=(%.4f, %.4f)" % [OLD_CENTER_X, OLD_CENTER_Z])
	print("Col pitch = %.4f m, Row pitch = %.4f m" % [COL_PITCH, ROW_PITCH])
	print("")

	var z_pos: float = OLD_CENTER_Z + 0.5 * ROW_PITCH
	var z_neg: float = OLD_CENTER_Z - 0.5 * ROW_PITCH

	var old_seeds_pos: Array = [
		[138.23, -29.11, 129.72],
		[146.97, -15.19, 121.63],
		[153.25, -0.63, 109.29],
		[157.52, 13.2, 93.71],
	]
	var old_seeds_neg: Array = [
		[-137.39, -29.12, 129.72],
		[-146.75, -15.19, 121.63],
		[-152.69, -0.63, 109.29],
		[-157.05, 13.2, 93.71],
	]

	var names: Array = ["4: Point12", "5: Point13", "6: Point14", "7: Point15",
		"8: Point16", "9: Point17", "10: Point18", "11: Point19"]
	var targets: Array = []
	for cx in range(4):
		var px: float = OLD_CENTER_X + (cx - 1.5) * COL_PITCH
		targets.append(Vector3(px, 0.87, z_pos))
	for cx in range(4):
		var px: float = OLD_CENTER_X + (cx - 1.5) * COL_PITCH
		targets.append(Vector3(px, 0.87, z_neg))

	var max_pos_err: float = 0.0
	var max_ori_err: float = 0.0

	for i in range(names.size()):
		var key: String = names[i]
		var tgt: Vector3 = targets[i]
		var old_seeds: Array = old_seeds_pos if i < 4 else old_seeds_neg

		var best_angles: Array[float] = [old_seeds[0][0], old_seeds[0][1], old_seeds[0][2], 0.0, 75.0, 0.0]
		var best_err: float = 1.0e10
		for seed in old_seeds:
			var trial: Array[float] = [seed[0], seed[1], seed[2], 0.0, 75.0, 0.0]
			_set_angles(trial)
			var tip: Vector3 = _robot.get_tool_tip_position()
			var err: float = (tgt - tip).length()
			if err < best_err:
				best_err = err
				best_angles = trial.duplicate()

		var lm_result: Array[float] = _lm_refine(tgt, best_angles)
		var j456: Array[float] = _solve_wrist(lm_result)
		lm_result[3] = j456[0]; lm_result[4] = j456[1]; lm_result[5] = j456[2]

		_set_angles(lm_result)
		var final_tip: Vector3 = _robot.get_tool_tip_position()
		var pos_err: float = (tgt - final_tip).length()
		var obj_basis: Basis = _object_basis(lm_result)
		var obj_euler_rad: Vector3 = obj_basis.get_euler()
		var obj_euler: Vector3 = Vector3(rad_to_deg(obj_euler_rad.x), rad_to_deg(obj_euler_rad.y), rad_to_deg(obj_euler_rad.z))
		var dx: float = absf(obj_euler.x)
		var dy: float = absf(obj_euler.y - 90.0)
		var dz: float = absf(obj_euler.z)
		var max_axis: float = maxf(dx, maxf(dy, dz))
		var status: String = "OK" if (pos_err < 0.01 and max_axis < 0.5) else "FAIL"

		if pos_err > max_pos_err: max_pos_err = pos_err
		if max_axis > max_ori_err: max_ori_err = max_axis

		print("--- %s [%s] ---" % [key, status])
		print("  target=(%.4f, %.4f, %.4f) tip=(%.4f, %.4f, %.4f) pos_err=%.6f m" %
			[tgt.x, tgt.y, tgt.z, final_tip.x, final_tip.y, final_tip.z, pos_err])
		print("  joints: [%.8f, %.8f, %.8f, %.8f, %.8f, %.8f]" % lm_result)
		print("  object Euler=(%.6f, %.6f, %.6f) max_axis=%.6f deg" %
			[obj_euler.x, obj_euler.y, obj_euler.z, max_axis])
		print("")

	print("=== SUMMARY ===")
	print("max_pos_err=%.4f m  max_object_euler=%.4f deg" % [max_pos_err, max_ori_err])
	quit(0)


func _lm_refine(target: Vector3, seed: Array[float]) -> Array[float]:
	var angles: Array[float] = seed.duplicate()
	var mu: float = 0.1
	var best: Array[float] = seed.duplicate()
	_set_angles(angles)
	var best_err: float = (target - _robot.get_tool_tip_position()).length()

	for _iter in range(LM_ITERS):
		if best_err < 0.0001:
			break
		_set_angles(angles)
		var tip: Vector3 = _robot.get_tool_tip_position()
		var e: Vector3 = target - tip
		var err: float = e.length()
		if err < best_err:
			best_err = err
			best = angles.duplicate()
		if err < 0.0001:
			break

		var Jp: Array = []
		for j in range(3):
			var sv: float = angles[j]
			angles[j] = sv + LM_DT
			_set_angles(angles)
			var tp: Vector3 = _robot.get_tool_tip_position()
			angles[j] = sv - LM_DT
			_set_angles(angles)
			var tm: Vector3 = _robot.get_tool_tip_position()
			angles[j] = sv
			Jp.append([(tp.x - tm.x) / (2.0 * LM_DT), (tp.y - tm.y) / (2.0 * LM_DT), (tp.z - tm.z) / (2.0 * LM_DT)])

		var improved: bool = false
		for _retry in range(12):
			var a3: Array = []
			for r in range(3):
				var row: Array = []
				for c in range(3):
					var s: float = 0.0
					for k in range(3):
						s += Jp[k][r] * Jp[k][c]
					row.append(s + (mu if r == c else 0.0))
				row.append(-(Jp[0][r] * e.x + Jp[1][r] * e.y + Jp[2][r] * e.z))
				a3.append(row)
			if not _gauss_3x3(a3):
				mu *= 10.0
				continue
			var dth: Array = [a3[0][3], a3[1][3], a3[2][3]]
			var trial: Array[float] = angles.duplicate()
			for j in range(3):
				trial[j] += clampf(dth[j], -LM_STEP_CLAMP, LM_STEP_CLAMP)
			while trial[0] > 180.0: trial[0] -= 360.0
			while trial[0] < -180.0: trial[0] += 360.0
			trial[1] = clampf(trial[1], -135.0, 135.0)
			trial[2] = clampf(trial[2], -160.0, 160.0)
			_set_angles(trial)
			var terr: float = (target - _robot.get_tool_tip_position()).length()
			if terr < err:
				angles = trial
				mu = maxf(mu * 0.5, 1.0e-6)
				improved = true
				break
			else:
				mu *= 3.0
		if not improved:
			break

	return best


func _gauss_3x3(a3: Array) -> bool:
	for col in range(3):
		var mr: int = col
		for r2 in range(col + 1, 3):
			if absf(a3[r2][col]) > absf(a3[mr][col]):
				mr = r2
		var tmp: Array = a3[col]; a3[col] = a3[mr]; a3[mr] = tmp
		if absf(a3[col][col]) < 1.0e-15:
			return false
		var p: float = a3[col][col]
		for cc in range(col, 4):
			a3[col][cc] /= p
		for r2 in range(3):
			if r2 != col:
				var f: float = a3[r2][col]
				for cc in range(col, 4):
					a3[r2][cc] -= f * a3[col][cc]
	return true


func _solve_wrist(j123_full: Array[float]) -> Array[float]:
	var target_tool: Basis = (_target_object_basis * _pickup_basis).orthonormalized()
	var best: Array[float] = [j123_full[3], j123_full[4], j123_full[5]]
	_set_angles(j123_full)
	var best_error: float = _orientation_error(target_tool, _tool_basis()).length()

	for d4 in [-180.0, -90.0, 0.0, 90.0, 180.0]:
		for d5 in [-90.0, 0.0, 90.0]:
			for d6 in [-180.0, 0.0, 180.0]:
				var seed: Array[float] = [j123_full[3] + d4, j123_full[4] + d5, j123_full[5] + d6]
				seed[0] = clampf(seed[0], -180.0, 180.0)
				seed[1] = clampf(seed[1], -120.0, 120.0)
				seed[2] = clampf(seed[2], -360.0, 360.0)
				var candidate: Array = _iterate_wrist(j123_full, seed, target_tool)
				if candidate[1] < best_error:
					best = candidate[0]
					best_error = candidate[1]
	return best


func _iterate_wrist(j123_full: Array[float], start: Array[float], target_tool: Basis) -> Array:
	var current: Array[float] = start.duplicate()
	var lambda: float = WRIST_LAMBDA_INIT
	for _i in range(MAX_WRIST_ITERS):
		j123_full[3] = current[0]; j123_full[4] = current[1]; j123_full[5] = current[2]
		_set_angles(j123_full)
		var current_basis: Basis = _tool_basis()
		var residual: Vector3 = _orientation_error(target_tool, current_basis)
		var residual_len: float = residual.length()
		if residual_len < 1.0e-10:
			break

		var jacobian: Array = _orientation_jacobian(j123_full, target_tool, residual)
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
		if step.length() > WRIST_MAX_STEP:
			step = step.normalized() * WRIST_MAX_STEP

		var trial: Array[float] = current.duplicate()
		trial[0] = clampf(trial[0] + step.x, -180.0, 180.0)
		trial[1] = clampf(trial[1] + step.y, -120.0, 120.0)
		trial[2] = clampf(trial[2] + step.z, -360.0, 360.0)
		j123_full[3] = trial[0]; j123_full[4] = trial[1]; j123_full[5] = trial[2]
		_set_angles(j123_full)
		var trial_error: float = _orientation_error(target_tool, _tool_basis()).length()
		if trial_error < residual_len:
			current = trial
			lambda = maxf(lambda * 0.5, 1.0e-9)
		else:
			lambda = minf(lambda * 5.0, 1000.0)

	j123_full[3] = current[0]; j123_full[4] = current[1]; j123_full[5] = current[2]
	_set_angles(j123_full)
	return [current, _orientation_error(target_tool, _tool_basis()).length()]


func _orientation_jacobian(j123_full: Array[float], target_tool: Basis, base_residual: Vector3) -> Array:
	var result: Array = [
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0]
	]
	var base_angles: Array[float] = [j123_full[3], j123_full[4], j123_full[5]]
	for wrist in range(3):
		var perturbed: Array[float] = base_angles.duplicate()
		perturbed[wrist] += WRIST_STEP_DEG
		j123_full[3] = perturbed[0]; j123_full[4] = perturbed[1]; j123_full[5] = perturbed[2]
		_set_angles(j123_full)
		var delta: Vector3 = (_orientation_error(target_tool, _tool_basis()) - base_residual) / WRIST_STEP_DEG
		result[0][wrist] = delta.x
		result[1][wrist] = delta.y
		result[2][wrist] = delta.z
	j123_full[3] = base_angles[0]; j123_full[4] = base_angles[1]; j123_full[5] = base_angles[2]
	_set_angles(j123_full)
	return result


func _orientation_error(target: Basis, current: Basis) -> Vector3:
	var angle: float = _angular_error(target, current)
	if angle < 0.5:
		return _basis_residual(target, current)
	return _rotation_vector(target, current)


func _basis_residual(target: Basis, current: Basis) -> Vector3:
	var relative: Basis = target * current.inverse()
	return Vector3(
		relative.z.y - relative.y.z,
		relative.x.z - relative.z.x,
		relative.y.x - relative.x.y
	) * 0.5


func _rotation_vector(target: Basis, current: Basis) -> Vector3:
	var a: Quaternion = target.get_rotation_quaternion()
	var b: Quaternion = current.get_rotation_quaternion()
	var err: Quaternion = a * b.inverse()
	if err.w < 0.0:
		err = Quaternion(-err.x, -err.y, -err.z, -err.w)
	var angle: float = err.get_angle()
	if angle < 1.0e-8:
		return Vector3.ZERO
	return err.get_axis().normalized() * angle


func _angular_error(target: Basis, current: Basis) -> float:
	var a: Quaternion = target.get_rotation_quaternion()
	var b: Quaternion = current.get_rotation_quaternion()
	var dot: float = absf(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
	return 2.0 * acos(clampf(dot, -1.0, 1.0))


func _set_angles(angles: Array[float]) -> void:
	_robot.set_joint_angles(angles)


func _tool_basis() -> Basis:
	return _robot.get_tool_tip_transform().basis.orthonormalized()


func _object_basis(angles: Array[float]) -> Basis:
	_set_angles(angles)
	var cup: Basis = _tool_basis()
	return (cup * _pickup_basis.inverse()).orthonormalized()


func _solve_3x3(matrix: Array, rhs: Array) -> Array:
	var det: float = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) \
		- matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) \
		+ matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
	if absf(det) < 1.0e-12:
		return []

	var inv: Array = [
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
		inv[0][0] * rhs[0] + inv[0][1] * rhs[1] + inv[0][2] * rhs[2],
		inv[1][0] * rhs[0] + inv[1][1] * rhs[1] + inv[1][2] * rhs[2],
		inv[2][0] * rhs[0] + inv[2][1] * rhs[1] + inv[2][2] * rhs[2]
	]
