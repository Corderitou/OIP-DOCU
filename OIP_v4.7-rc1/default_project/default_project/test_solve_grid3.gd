extends SceneTree

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"
const UNIT_SPACING := 0.172
const COL_PITCH := 1.5 * UNIT_SPACING
const ROW_PITCH := 7.0 * UNIT_SPACING

var REF_ANG: Array[float] = [-156.80, -12.66, 119.78, -0.19, 71.70, 114.08]

func _init() -> void:
	call_deferred("_run")

func solve_pos_3dof(robot: Node3D, vac: Node3D, target_pos: Vector3,
seed: Array[float], iters: int) -> Array[float]:
	var angles: Array[float] = seed.duplicate()
	var mu: float = 0.1
	var best: Array[float] = seed.duplicate()
	var best_err: float = 1e10
	for _i in range(iters):
		robot.set_joint_angles(angles)
		var tip: Vector3 = robot.get_tool_tip_position()
		var e: Vector3 = target_pos - tip
		var err: float = e.length()
		if err < best_err:
			best_err = err
			best = angles.duplicate()
		if err < 0.0002:
			break
		var dt: float = 0.005
		var Jp: Array = []
		for j in range(3):
			var sv: float = angles[j]
			angles[j] = sv + dt
			robot.set_joint_angles(angles)
			var tp: Vector3 = robot.get_tool_tip_position()
			angles[j] = sv - dt
			robot.set_joint_angles(angles)
			var tm: Vector3 = robot.get_tool_tip_position()
			angles[j] = sv
			Jp.append([(tp.x - tm.x) / (2.0 * dt), (tp.y - tm.y) / (2.0 * dt), (tp.z - tm.z) / (2.0 * dt)])
		for _retry in range(4):
			var JJt: Array = []
			for r in range(3):
				JJt.append([])
				for c in range(3):
					var s: float = 0.0
					for k in range(3):
						s += Jp[k][r] * Jp[k][c]
					JJt[r].append(s + (mu if r == c else 0.0))
			var a3: Array = []
			for r in range(3):
				a3.append(JJt[r].duplicate() + [e[r]])
			var ok_solve: bool = true
			for col in range(3):
				var mr: int = col
				for r2 in range(col + 1, 3):
					if absf(a3[r2][col]) > absf(a3[mr][col]):
						mr = r2
				var tmp: Array = a3[col]; a3[col] = a3[mr]; a3[mr] = tmp
				if absf(a3[col][col]) < 1e-15:
					ok_solve = false; break
				var p: float = a3[col][col]
				for cc in range(col, 4):
					a3[col][cc] /= p
				for r2 in range(3):
					if r2 != col:
						var f: float = a3[r2][col]
						for cc in range(col, 4):
							a3[r2][cc] -= f * a3[col][cc]
			if not ok_solve:
				mu *= 10.0; continue
			var xx: Array = [a3[0][3], a3[1][3], a3[2][3]]
			var dth: Array = []
			for j in range(3):
				var s: float = 0.0
				for r2 in range(3):
					s += Jp[j][r2] * xx[r2]
				dth.append(s)
			var trial: Array[float] = angles.duplicate()
			for j in range(3):
				trial[j] += clampf(dth[j], -2.0, 2.0)
			while trial[0] > 180.0: trial[0] -= 360.0
			while trial[0] < -180.0: trial[0] += 360.0
			robot.set_joint_angles(trial)
			var tt: Vector3 = robot.get_tool_tip_position()
			var terr: float = (target_pos - tt).length()
			if terr < err:
				angles = trial
				mu = maxf(mu * 0.5, 1e-6)
				break
			else:
				mu *= 3.0
	return best


func solve_wrist_6dof(robot: Node3D, vac: Node3D,
j123: Array[float], target_cup: Vector3, target_basisX: Vector3) -> Array[float]:
	var best_w: Array[float] = [REF_ANG[3], REF_ANG[4], REF_ANG[5]]
	var best_cost: float = 1e10
	# J6 is the rotation axis for the rectangle; scan wide range
	for dj4 in range(-20, 21, 4):
		for dj5 in range(-20, 21, 4):
			for dj6 in range(-90, 91, 4):
				var trial: Array[float] = [j123[0], j123[1], j123[2],
					REF_ANG[3] + dj4, REF_ANG[4] + dj5, REF_ANG[5] + dj6]
				robot.set_joint_angles(trial)
				var basis: Basis = vac.global_transform.basis.orthonormalized()
				var cup: Vector3 = basis.y
				var bx: Vector3 = basis.x
				var oe: float = acos(clampf(cup.dot(target_cup), -1.0, 1.0))
				var xe: float = acos(clampf(bx.dot(target_basisX), -1.0, 1.0))
				var cost: float = 10.0 * oe + 1.0 * xe
				if cost < best_cost:
					best_cost = cost
					best_w = [REF_ANG[3] + dj4, REF_ANG[4] + dj5, REF_ANG[5] + dj6]
	# Fine scan
	for dj4 in range(-4, 5, 1):
		for dj5 in range(-4, 5, 1):
			for dj6 in range(-4, 5, 1):
				var trial: Array[float] = [j123[0], j123[1], j123[2],
					best_w[0] + dj4, best_w[1] + dj5, best_w[2] + dj6]
				robot.set_joint_angles(trial)
				var basis: Basis = vac.global_transform.basis.orthonormalized()
				var cup: Vector3 = basis.y
				var bx: Vector3 = basis.x
				var oe: float = acos(clampf(cup.dot(target_cup), -1.0, 1.0))
				var xe: float = acos(clampf(bx.dot(target_basisX), -1.0, 1.0))
				var cost: float = 10.0 * oe + 1.0 * xe
				if cost < best_cost:
					best_cost = cost
					best_w = [best_w[0] + dj4, best_w[1] + dj5, best_w[2] + dj6]
	return best_w


func _run() -> void:
	print("=== GRID IK SOLVER + IKTarget VERIFICATION ===")
	var packed: PackedScene = load(ROBOT_SCENE)
	if packed == null:
		push_error("No scene"); quit(1); return
	var robot: Node3D = packed.instantiate()
	root.add_child(robot)
	robot.robot_scale = 0.7
	robot.show_gizmos = false
	var vac: Node3D = robot._vacuum_area as Node3D

	robot.set_joint_angles(REF_ANG)
	var ref_tip: Vector3 = robot.get_tool_tip_position()
	var ref_basis: Basis = vac.global_transform.basis.orthonormalized()
	print("ref_tip=(%.3f, %.3f, %.3f)" % [ref_tip.x, ref_tip.y, ref_tip.z])

	var target_cup: Vector3 = Vector3(0.0, -1.0, 0.0)
	var target_basisX: Vector3 = ref_basis.x.normalized()
	print("target_basisX=(%.4f, %.4f, %.4f)" % [target_basisX.x, target_basisX.y, target_basisX.z])

	var half_z: float = 0.5 * ROW_PITCH
	var x_center: float = ref_tip.x

	var grid: Array = []
	var gnames: Array = []
	for cx in range(4):
		grid.append(Vector3(x_center + (cx - 1.5) * COL_PITCH, ref_tip.y, half_z))
		gnames.append("R1C%d" % [cx + 1])
	for cx in range(4):
		grid.append(Vector3(x_center + (cx - 1.5) * COL_PITCH, ref_tip.y, -half_z))
		gnames.append("R2C%d" % [cx + 1])

	var j1_range_pos: Array = [155.0, 160.0, 165.0, 170.0, 175.0, 178.0]
	var j1_range_neg: Array = [-155.0, -160.0, -165.0, -170.0, -175.0, -178.0]
	var all_ok: bool = true
	var max_pos_err: float = 0.0
	var max_ori_err: float = 0.0

	for i in range(8):
		var tgt: Vector3 = grid[i]
		var j1_pool: Array = j1_range_pos if i < 4 else j1_range_neg
		var best_final: Array[float] = REF_ANG.duplicate()
		var best_cost: float = 1e10

		for j1_seed in j1_pool:
			var j456: Array[float] = [REF_ANG[3], REF_ANG[4], REF_ANG[5]]
			var pos_ang: Array[float] = [j1_seed, REF_ANG[1], REF_ANG[2], j456[0], j456[1], j456[2]]
			for _iter in range(5):
				pos_ang[3] = j456[0]; pos_ang[4] = j456[1]; pos_ang[5] = j456[2]
				pos_ang = solve_pos_3dof(robot, vac, tgt, pos_ang, 400)
				j456 = solve_wrist_6dof(robot, vac, [pos_ang[0], pos_ang[1], pos_ang[2]], target_cup, target_basisX)
				pos_ang[3] = j456[0]; pos_ang[4] = j456[1]; pos_ang[5] = j456[2]
			robot.set_joint_angles(pos_ang)
			var ft: Vector3 = robot.get_tool_tip_position()
			var fb: Basis = vac.global_transform.basis.orthonormalized()
			var pe: float = (tgt - ft).length()
			var cd: float = fb.y.dot(target_cup)
			var oe: float = acos(clampf(cd, -1.0, 1.0))
			var cost: float = pe + 0.5 * oe
			if cost < best_cost:
				best_cost = cost
				best_final = pos_ang.duplicate()

		robot.set_joint_angles(best_final)
		var ft: Vector3 = robot.get_tool_tip_position()
		var fb: Basis = vac.global_transform.basis.orthonormalized()
		var err_mm: float = (tgt - ft).length() * 1000.0
		var cd: float = fb.y.dot(target_cup)
		var ori_deg: float = rad_to_deg(acos(clampf(cd, -1.0, 1.0)))
		var bx_align: float = rad_to_deg(acos(clampf(fb.x.dot(target_basisX), -1.0, 1.0)))
		if err_mm > max_pos_err: max_pos_err = err_mm
		if ori_deg > max_ori_err: max_ori_err = ori_deg

		var ok: bool = (err_mm < 10.0 and ori_deg < 2.0)
		if not ok: all_ok = false

		var status: String = "OK" if ok else "FAIL"
		print("\n--- %s [%s] ---" % [gnames[i], status])
		print("  joints: J1=%+.2f J2=%+.2f J3=%+.2f J4=%+.2f J5=%+.2f J6=%+.2f" %
			[best_final[0], best_final[1], best_final[2], best_final[3], best_final[4], best_final[5]])
		print("  IKTarget pos: (%.3f, %.3f, %.3f)  pos_err=%.1fmm" % [ft.x, ft.y, ft.z, err_mm])
		print("  IKTarget basisX: (%.4f, %.4f, %.4f)  align_err=%.2f" % [fb.x.x, fb.x.y, fb.x.z, bx_align])
		print("  IKTarget basisY: (%.4f, %.4f, %.4f)  cupY=%.4f" % [fb.y.x, fb.y.y, fb.y.z, cd])
		print("  IKTarget basisZ: (%.4f, %.4f, %.4f)" % [fb.z.x, fb.z.y, fb.z.z])
		print("  orientation error: %.2f°" % ori_deg)

	print("\n=== SUMMARY ===")
	print("max_pos_err=%.1fmm  max_ori_err=%.2f°" % [max_pos_err, max_ori_err])
	print("RESULT: %s" % ["ALL PASS" if all_ok else "SOME FAILED"])

	quit(0 if all_ok else 1)
