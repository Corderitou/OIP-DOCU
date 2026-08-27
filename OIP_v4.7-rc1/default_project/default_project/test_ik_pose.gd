extends SceneTree

# Validacion headless del IK de pose (solve_ik_pose) + flujo IKTarget.

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"


func _angle_err(b_a: Basis, b_b: Basis) -> float:
	var q_a: Quaternion = b_a.get_rotation_quaternion()
	var q_b: Quaternion = b_b.get_rotation_quaternion()
	return absf(q_a.angle_to(q_b))


func _run() -> void:
	var ok := true

	var robot_script: Script = load("res://src/SixAxisRobot/six_axis_robot.gd")
	var target_script: Script = load("res://src/SixAxisRobot/robot_ik_target.gd")
	var plugin_script: Script = load("res://addons/robot_gizmo/robot_gizmo_plugin.gd")
	print("PARSE robot=", robot_script != null, " target=", target_script != null, " plugin=", plugin_script != null)
	if robot_script == null or target_script == null or plugin_script == null:
		quit(1)
		return

	var packed: PackedScene = load(ROBOT_SCENE)
	var robot: Node3D = packed.instantiate()
	root.add_child(robot)
	robot.robot_scale = 0.7
	robot.show_gizmos = false
	robot.set_joint_angles([180.0, 0.6, 106.2, -1.0, 67.8, 90.0] as Array[float])

	var child := robot.get_node_or_null(NodePath("IKTarget"))
	print("RUNTIME_IKTARGET_ABSENT=", child == null)
	if child != null:
		ok = false

	var p4_pos: Vector3 = robot.get_tool_tip_position()
	var p4_basis: Basis = robot.get_tool_tip_transform().basis

	# Caso A: rotar 90 grados en Y manteniendo la posicion de P4
	var basis_a: Basis = p4_basis.rotated(Vector3.UP, deg_to_rad(90.0))
	var ok_a: bool = robot.solve_ik_pose(p4_pos, basis_a)
	var err_a: float = robot.get_tool_tip_position().distance_to(p4_pos)
	var ang_a: float = rad_to_deg(_angle_err(robot.get_tool_tip_transform().basis, basis_a))
	print("A rotY90  ok=", ok_a, " pos_err=%.4f ang_err=%.2f" % [err_a, ang_a])
	if not ok_a or err_a > 0.01 or ang_a > 2.5:
		ok = false

	# Caso B: celda lejana (4,2) con la copa inclinada 25 grados en X
	var pos_b: Vector3 = p4_pos + Vector3(0.34, 0.0, -0.17)
	var basis_b: Basis = p4_basis.rotated(Vector3.RIGHT, deg_to_rad(25.0))
	var ok_b: bool = robot.solve_ik_pose(pos_b, basis_b)
	var err_b: float = robot.get_tool_tip_position().distance_to(pos_b)
	var ang_b: float = rad_to_deg(_angle_err(robot.get_tool_tip_transform().basis, basis_b))
	print("B celda+tilt ok=", ok_b, " pos_err=%.4f ang_err=%.2f" % [err_b, ang_b])
	if not ok_b or err_b > 0.01 or ang_b > 2.5:
		ok = false

	# Caso C: solo rotacion (posicion fija), volver a P4 pero copa mirando otro lado
	robot.set_joint_angles([180.0, 0.6, 106.2, -1.0, 67.8, 90.0] as Array[float])
	var basis_c: Basis = p4_basis.rotated(Vector3.BACK, deg_to_rad(-30.0))
	var ok_c: bool = robot.solve_ik_pose(p4_pos, basis_c)
	var err_c: float = robot.get_tool_tip_position().distance_to(p4_pos)
	var ang_c: float = rad_to_deg(_angle_err(robot.get_tool_tip_transform().basis, basis_c))
	print("C solo-rot ok=", ok_c, " pos_err=%.4f ang_err=%.2f" % [err_c, ang_c])
	if not ok_c or err_c > 0.01 or ang_c > 2.5:
		ok = false

	# Caso D: solve_ik clasico sigue funcionando igual
	robot.set_joint_angles([180.0, 0.6, 106.2, -1.0, 67.8, 90.0] as Array[float])
	var ok_d: bool = robot.solve_ik(p4_pos + Vector3(-0.17, 0, 0))
	var err_d: float = robot.get_tool_tip_position().distance_to(p4_pos + Vector3(-0.17, 0, 0))
	print("D clasico ok=", ok_d, " pos_err=%.4f" % err_d)
	if not ok_d or err_d > 0.01:
		ok = false

	robot.queue_free()
	print("RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
