extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_script: Script = load("res://parts/TestRobotGrid.gd")
	if scene_script == null:
		print("FAIL: TestRobotGrid.gd failed to load")
		quit(1)
		return
	print("PASS: TestRobotGrid.gd loaded OK")

	var packed: PackedScene = load("res://parts/TestRobotGrid.tscn")
	if packed == null:
		print("FAIL: TestRobotGrid.tscn failed to load")
		quit(1)
		return
	print("PASS: TestRobotGrid.tscn loaded OK")

	var scene: Node3D = packed.instantiate()
	root.add_child(scene)

	var robot: Node3D = scene.get_node_or_null("Robot")
	if robot == null:
		print("FAIL: Robot node not found")
		quit(1)
		return
	print("PASS: Robot found")

	# Check blocks
	var block_count: int = 0
	for child in scene.get_children():
		if child is RigidBody3D and child.name.begins_with("TestBlock"):
			block_count += 1
	print("PASS: %d TestBlocks found" % block_count)

	# Check waypoints
	var wp: Dictionary = robot.waypoints
	print("PASS: %d waypoints" % wp.size())

	# Move robot to Point1 and check tip position
	robot.robot_scale = 0.7
	robot.show_gizmos = false
	var angles1: Array = wp["1: Point1"]
	robot.set_joint_angles(angles1)
	var tip1: Vector3 = robot.get_tool_tip_position()
	print("Point1 tip: (%.3f, %.3f, %.3f)" % [tip1.x, tip1.y, tip1.z])

	# Check block positions vs tip
	for child in scene.get_children():
		if child is RigidBody3D and child.name.begins_with("TestBlock"):
			var dist: float = child.global_position.distance_to(tip1)
			print("  %s at (%.3f, %.3f, %.3f) dist=%.3f" % [
				child.name, child.global_position.x, child.global_position.y, child.global_position.z, dist])

	quit(0)
