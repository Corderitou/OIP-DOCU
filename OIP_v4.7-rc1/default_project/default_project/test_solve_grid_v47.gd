extends SceneTree

# Regenera la grilla de deposito del SixAxisRobot de Simulation.tscn con los
# pitches confirmados por el usuario (2026-08-26):
#   columnas = 1.15 x unit_spacing (0.172) = 0.1978 m
#   filas    = 6.00 x unit_spacing (0.172) = 1.0320 m
# El centro del rectangulo se MIDE desde los tooltips actuales de la escena,
# no se usa una constante vieja. Para cada celda resuelve J1-J3 por IK
# (Levenberg-Marquardt sobre el tooltip, sembrado con la rama de J1 que
# corresponde a su fila) y luego J4-J6 con el solver de muneca para que el
# objeto liberado quede en Euler (0, 90, 0). No toca comms ni guarda escenas.

const SIM_SCENE := "res://Simulation.tscn"
const UNIT_SPACING := 0.172
const COL_PITCH := 1.1 * UNIT_SPACING
const ROW_PITCH := 6.3 * UNIT_SPACING
const GRID_Y := 0.87
const MAX_WRIST_ITERS := 240
const WRIST_STEP_DEG := 0.01
const WRIST_LAMBDA_INIT := 0.001
const WRIST_MAX_STEP := 10.0
const JMIN: Array[float] = [-180.0, -135.0, -160.0, -180.0, -120.0, -360.0]
const JMAX: Array[float] = [180.0, 135.0, 160.0, 180.0, 120.0, 360.0]

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

	var p1: Array[float] = [29.82666699, -2.9, 101.1, 0.00000053, 81.79999916, 29.82665835]
	_set_angles(p1)
	_pickup_basis = _tool_basis()

	var names: Array = ["4: Point12", "5: Point13", "6: Point14", "7: Point15",
		"8: Point16", "9: Point17", "10: Point18", "11: Point19"]

	# --- Fase 1: medir centro y separaciones actuales ---
	var scene_joints: Dictionary = {}
	var old_tips: Array = []
	var sum := Vector3.ZERO
	for key in names:
		var src: Array = _robot.waypoints[key]
		var angles: Array[float] = [src[0], src[1], src[2], src[3], src[4], src[5]]
		scene_joints[key] = angles
		_set_angles(angles)
		var tip: Vector3 = _robot.get_tool_tip_position()
		old_tips.append(tip)
		sum += tip
	var center := Vector3(sum.x / 8.0, GRID_Y, sum.z / 8.0)

	print("Pitches objetivo: col=%.4f m (1.15x) fila=%.4f m (6x)" % [COL_PITCH, ROW_PITCH])
	print("Centro medido actual: (%.4f, %.4f)" % [center.x, center.z])
	print("--- Tips actuales ---")
	for i in names.size():
		print("%s tip=(%.4f, %.4f, %.4f)" % [names[i], old_tips[i].x, old_tips[i].y, old_tips[i].z])
	var old_col: float = 0.0
	for cx in range(3):
		old_col += old_tips[cx + 1].distance_to(old_tips[cx])
	old_col /= 3.0
	var old_row: float = old_tips[4].distance_to(old_tips[0])
	print("Separacion actual medida: col=%.4f m fila=%.4f m" % [old_col, old_row])
	print("")

	# --- Fase 2: objetivos del rectangulo nuevo ---
	var targets: Array = []
	for cx in range(4):
		targets.append(Vector3(center.x + (cx - 1.5) * COL_PITCH, GRID_Y, center.z + 0.5 * ROW_PITCH))
	for cx in range(4):
		targets.append(Vector3(center.x + (cx - 1.5) * COL_PITCH, GRID_Y, center.z - 0.5 * ROW_PITCH))

	# Semillas por rama: valores de la propia escena (fila positiva 12-15,
	# fila negativa 16-19), que conservan la configuracion del brazo.
	var results: Dictionary = {}
	var solved_sols: Dictionary = {}
	var fails := 0
	var max_pos_err: float = 0.0
	var max_axis_err: float = 0.0

	for i in names.size():
		var key: String = names[i]
		var tgt: Vector3 = targets[i]
		var seed_row: Array = scene_joints[key]

		# Elegir semilla dentro de la MISMA rama + soluciones ya resueltas +
		# variantes sinteticas de muneca (la escena tiene J6 corrupto en col 3-4)
		var branch_idx: int = i if i < 4 else i - 4
		var same_branch: Array = []
		for j in range(4):
			same_branch.append(scene_joints[names[j if i < 4 else j + 4]])

		var cand: Array = [seed_row, same_branch[branch_idx]]
		for sk in solved_sols.keys():
			cand.append(solved_sols[sk])
		for b123 in [seed_row, same_branch[branch_idx]]:
			for w in [[-180.0, -78.62, -124.1], [-180.0, -73.69, -118.22],
					[180.0, 78.62, 124.1], [180.0, 73.69, 118.22],
					[0.0, 79.39, 48.23], [0.0, -79.39, -48.23]]:
				cand.append([b123[0], b123[1], b123[2], w[0], w[1], w[2]])
		# Extrapolacion manual del patron resuelto para la ultima columna
		if key == "7: Point15":
			for ex in [[160.6, 6.9, 104.0, -180.0, -68.8, -106.5],
					[161.5, 10.5, 98.5, -180.0, -66.0, -102.0],
					[159.0, 3.0, 109.5, -180.0, -70.0, -111.0]]:
				cand.append(ex)
		elif key == "11: Point19":
			for ex in [[-160.3, 6.9, 104.0, 0.0, -68.8, 108.5],
					[-161.2, 10.5, 98.5, 180.0, -66.0, 103.0],
					[-158.7, 3.0, 109.5, 0.0, -70.0, 112.5]]:
				cand.append(ex)

		var lm_result: Array[float] = _solve_coupled(tgt, cand)
		if lm_result.is_empty():
			fails += 1
			print("--- %s [FAIL: sin convergencia] ---" % key)
			continue
		var j456: Array[float] = _solve_wrist(lm_result)
		lm_result[3] = j456[0]; lm_result[4] = j456[1]; lm_result[5] = j456[2]
		solved_sols[key] = lm_result

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
		var ok: bool = (pos_err < 0.01 and max_axis < 0.5)
		if not ok:
			fails += 1
		if pos_err > max_pos_err: max_pos_err = pos_err
		if max_axis > max_axis_err: max_axis_err = max_axis
		results[key] = lm_result

		print("--- %s [%s] ---" % [key, "OK" if ok else "FAIL"])
		print("  target=(%.4f, %.4f, %.4f) tip=(%.4f, %.4f, %.4f) pos_err=%.6f m" %
			[tgt.x, tgt.y, tgt.z, final_tip.x, final_tip.y, final_tip.z, pos_err])
		print("  joints: %s" % _fmt(lm_result))
		print("  object Euler=(%.6f, %.6f, %.6f) max_axis=%.6f deg" %
			[obj_euler.x, obj_euler.y, obj_euler.z, max_axis])
		print("")

	# --- Verificacion geometrica de la grilla resultante ---
	print("--- Verificacion geometria nueva ---")
	if fails == 0:
		var new_tips: Array = []
		for key in names:
			_set_angles(results[key])
			new_tips.append(_robot.get_tool_tip_position())
		print("Fila1 col-to-col:")
		for i in range(3):
			var d: float = Vector2(new_tips[i].x - new_tips[i + 1].x,
				new_tips[i].z - new_tips[i + 1].z).length()
			print("  P%d->P%d = %.4f m" % [i + 12, i + 13, d])
		print("Fila2 col-to-col:")
		for i in range(3):
			var d: float = Vector2(new_tips[i + 4].x - new_tips[i + 5].x,
				new_tips[i + 4].z - new_tips[i + 5].z).length()
			print("  P%d->P%d = %.4f m" % [i + 16, i + 17, d])
		var dr: float = Vector2(new_tips[0].x - new_tips[4].x,
			new_tips[0].z - new_tips[4].z).length()
		print("Row pitch real P12-P16: %.4f m" % dr)
	else:
		print("(omitida: hay celdas sin convergencia)")
	print("")

	print("=== SUMMARY ===")
	print("fails=%d max_pos_err=%.6f m max_object_euler=%.6f deg" % [fails, max_pos_err, max_axis_err])
	if fails == 0:
		print("---- READY TO PASTE ----")
		for key in names:
			print("\"%s\": Array[float](%s)," % [key, _fmt(results[key])])
	quit(0 if fails == 0 else 1)


func _fmt(a: Array) -> String:
	var s := "["
	for i in a.size():
		s += String.num(float(a[i]), 10)
		if i < a.size() - 1:
			s += ", "
	return s + "]"


func _solve_coupled(target: Vector3, candidates: Array) -> Array[float]:
	# LM de pose completa sobre los SEIS joints: el tooltip depende fuerte de
	# J4/J5 (medido: J4±45 mueve 19.6 cm), asi que posicion y orientacion se
	# resuelven juntas por minimos cuadrados, nunca por etapas separadas.
	var target_tool: Basis = (_target_object_basis * _pickup_basis).orthonormalized()
	var best: Array[float] = []
	var best_score := INF
	for s in candidates:
		var start: Array[float] = [s[0], s[1], s[2], s[3], s[4], s[5]]
		var res: Array = _lm_pose(start, target, target_tool)
		if res.is_empty():
			continue
		var fin: Array[float] = res[0]
		var f_pos: float = _robot.get_tool_tip_position().distance_to(target)
		var f_ori: float = rad_to_deg(_angular_error(target_tool, _tool_basis()))
		if f_pos < 0.0008 and f_ori < 0.02:
			print("    cand(%.1f): OK pos=%.6f ori=%.6f" % [s[0], f_pos, f_ori])
			return fin
		print("    cand(%.1f): stall pos=%.6f ori=%.6f" % [s[0], f_pos, f_ori])
		var score: float = f_pos * 100.0 + f_ori
		if score < best_score:
			best_score = score
			best = fin.duplicate()
	if best.is_empty():
		return []
	# Fase C: restarts globales aleatorios con el mismo LM.
	print("    fase C: restarts globales...")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260826
	for _try in range(60):
		var j: Array[float] = [
			rng.randf_range(JMIN[0], JMAX[0]), rng.randf_range(JMIN[1], JMAX[1]),
			rng.randf_range(JMIN[2], JMAX[2]), rng.randf_range(JMIN[3], JMAX[3]),
			rng.randf_range(JMIN[4], JMAX[4]), rng.randf_range(JMIN[5], JMAX[5])]
		var res: Array = _lm_pose(j, target, target_tool)
		if res.is_empty():
			continue
		var fin: Array[float] = res[0]
		var cpos: float = _robot.get_tool_tip_position().distance_to(target)
		var cori: float = rad_to_deg(_angular_error(target_tool, _tool_basis()))
		if cpos < 0.0008 and cori < 0.02:
			print("    global %d: OK pos=%.6f ori=%.6f" % [_try, cpos, cori])
			return fin
	_set_angles(best)
	if _robot.get_tool_tip_position().distance_to(target) > 0.005:
		return []
	return best


const POSE_ORI_WEIGHT := 0.18


func _clamp_angles(angles: Array[float]) -> Array[float]:
	var out := angles.duplicate()
	for k in range(6):
		out[k] = clampf(out[k], JMIN[k], JMAX[k])
	return out


func _pose_residual(target: Vector3, target_tool: Basis) -> Array[float]:
	var e := Vector3(target - _robot.get_tool_tip_position())
	var eo: Vector3 = _orientation_error(target_tool, _tool_basis())
	return [e.x, e.y, e.z, eo.x * POSE_ORI_WEIGHT, eo.y * POSE_ORI_WEIGHT, eo.z * POSE_ORI_WEIGHT]


func _pose_cost(res: Array[float]) -> float:
	var s := 0.0
	for v in res:
		s += v * v
	return s


func _lm_pose(start: Array[float], target: Vector3, target_tool: Basis) -> Array:
	var cur := _clamp_angles(start)
	_set_angles(cur)
	var cur_res := _pose_residual(target, target_tool)
	var cur_cost := _pose_cost(cur_res)
	var mu := 1.0e-3
	for _iter in range(400):
		if cur_cost < 1.0e-13:
			break
		# Jacobiano numerico 6x6 (rad->mezcla, paso en grados)
		var jac: Array = []
		for _r in range(6):
			jac.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		for jj in range(6):
			var pert := cur.duplicate()
			pert[jj] = clampf(pert[jj] + 0.05, JMIN[jj], JMAX[jj])
			_set_angles(pert)
			var p_res := _pose_residual(target, target_tool)
			for r in range(6):
				jac[r][jj] = (p_res[r] - cur_res[r]) / 0.05
			cur[jj] = clampf(cur[jj], JMIN[jj], JMAX[jj])
		_set_angles(cur)
		# (J^T J + mu I) d = -J^T r  en 6x6
		var n: Array = []
		for _r in range(6):
			n.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		for r in range(6):
			for c in range(r, 6):
				var sm := 0.0
				for k in range(6):
					sm += jac[k][r] * jac[k][c]
				n[r][c] = sm
				n[c][r] = sm
			n[r][r] += mu
		var rhs: Array[float] = []
		for r in range(6):
			var sm := 0.0
			for k in range(6):
				sm += jac[k][r] * cur_res[k]
			rhs.append(-sm)
		var delta := _gauss_solve(n, rhs)
		if delta.is_empty():
			mu *= 10.0
			if mu > 1.0e7:
				break
			continue
		var trial := cur.duplicate()
		for jj in range(6):
			trial[jj] = clampf(trial[jj] + clampf(delta[jj], -6.0, 6.0), JMIN[jj], JMAX[jj])
		_set_angles(trial)
		var t_res := _pose_residual(target, target_tool)
		var t_cost := _pose_cost(t_res)
		if t_cost < cur_cost:
			cur = trial
			cur_res = t_res
			cur_cost = t_cost
			mu = maxf(mu * 0.4, 1.0e-9)
		else:
			mu *= 4.0
			if mu > 1.0e7:
				break
	_set_angles(cur)
	return [cur]


func _gauss_solve(m: Array, rhs: Array) -> Array:
	var a: Array = []
	for r in range(m.size()):
		var row: Array = []
		for c in range(m.size()):
			row.append(m[r][c])
		row.append(rhs[r])
		a.append(row)
	var nn := a.size()
	for col in range(nn):
		var mr := col
		for r2 in range(col + 1, nn):
			if absf(a[r2][col]) > absf(a[mr][col]):
				mr = r2
		var tmp: Array = a[col]; a[col] = a[mr]; a[mr] = tmp
		if absf(a[col][col]) < 1.0e-16:
			return []
		var pv: float = a[col][col]
		for cc in range(col, nn + 1):
			a[col][cc] /= pv
		for r2 in range(nn):
			if r2 != col:
				var f: float = a[r2][col]
				for cc in range(col, nn + 1):
					a[r2][cc] -= f * a[col][cc]
	var out: Array[float] = []
	for r in range(nn):
		out.append(a[r][nn])
	return out


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
