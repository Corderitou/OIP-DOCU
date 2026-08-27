extends SceneTree

# Validacion headless del flujo IKTarget:
# 1) Los tres scripts parsean (robot, target, plugin).
# 2) El robot standalone (fuera del editor) NO crea el hijo IKTarget.
# 3) solve_ik sigue funcionando con J1..J6.

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true

	var robot_script: Script = load("res://src/SixAxisRobot/six_axis_robot.gd")
	var target_script: Script = load("res://src/SixAxisRobot/robot_ik_target.gd")
	var plugin_script: Script = load("res://addons/robot_gizmo/robot_gizmo_plugin.gd")
	print("PARSE robot=", robot_script != null, " target=", target_script != null, " plugin=", plugin_script != null)
	if robot_script == null or target_script == null or plugin_script == null:
		ok = false

	if ok:
		var packed: PackedScene = load(ROBOT_SCENE)
		var robot: Node3D = packed.instantiate()
		root.add_child(robot)
		robot.robot_scale = 0.7
		robot.show_gizmos = false
		var seed_angles: Array[float] = [180.0, 0.6, 106.2, -1.0, 67.8, 90.0]
		robot.set_joint_angles(seed_angles)

		# Fuera del editor NO debe existir el hijo IKTarget
		var child := robot.get_node_or_null(NodePath("IKTarget"))
		print("RUNTIME_IKTARGET_ABSENT=", child == null)
		if child != null:
			ok = false

		# solve_ik J1..J6 sigue operativo
		var tip: Vector3 = robot.get_tool_tip_position()
		for offset in [Vector3(-0.17, 0, 0), Vector3(0.34, 0, -0.17), Vector3(-0.17, -0.15, -0.17)]:
			var solved: bool = robot.solve_ik(tip + offset)
			var err: float = robot.get_tool_tip_position().distance_to(tip + offset)
			print("IK ok=", solved, " err=%.4f" % err, " j6=%.1f" % robot.j6_angle)
			if not solved or err > 0.01:
				ok = false
		robot.queue_free()

	print("RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
