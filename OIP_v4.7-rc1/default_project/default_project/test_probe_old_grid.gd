extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://Simulation.tscn")
	if scene == null:
		print("FAIL"); quit(1); return
	var instance: Node3D = scene.instantiate()
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(instance)
	var robot: Node3D = instance.get_node("SixAxisRobot") as Node3D

	var old_angles: Array = [
		[138.23, -29.11, 129.72],
		[146.97, -15.19, 121.63],
		[153.25, -0.63, 109.29],
		[157.52, 13.2, 93.71],
		[-137.39, -29.12, 129.72],
		[-146.75, -15.19, 121.63],
		[-152.69, -0.63, 109.29],
		[-157.05, 13.2, 93.71],
	]
	var names: Array = ["Point12", "Point13", "Point14", "Point15", "Point16", "Point17", "Point18", "Point19"]
	for i in range(8):
		var a: Array = old_angles[i]
		var angles: Array[float] = [a[0], a[1], a[2], 0.0, 75.0, 0.0]
		robot.set_joint_angles(angles)
		var tip: Vector3 = robot.get_tool_tip_position()
		print("%s tip=(%.4f, %.4f, %.4f)" % [names[i], tip.x, tip.y, tip.z])

	var cx: float = 0.0
	var cz: float = 0.0
	for a in old_angles:
		var angles2: Array[float] = [a[0], a[1], a[2], 0.0, 75.0, 0.0]
		robot.set_joint_angles(angles2)
		var tip: Vector3 = robot.get_tool_tip_position()
		cx += tip.x
		cz += tip.z
	cx /= 8.0
	cz /= 8.0
	print("Center=(%.4f, %.4f)" % [cx, cz])
	quit(0)
