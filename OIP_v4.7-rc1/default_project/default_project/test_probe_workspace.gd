extends SceneTree

# Probe: map radial reach range by varying J2/J3 at J1=+180 and J1=-180

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"

var REF: Array[float] = [-156.80, -12.66, 119.78, -0.19, 71.70, 114.08]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("SCRIPT OK")
	var packed: PackedScene = load(ROBOT_SCENE)
	if packed == null:
		push_error("No scene")
		quit(1)
		return
	var robot: Node3D = packed.instantiate()
	root.add_child(robot)
	robot.robot_scale = 0.7
	robot.show_gizmos = false
	var vac: Node3D = robot._vacuum_area as Node3D

	# Vary J2 to see reach range at J1=+180
	print("=== REACH RANGE at J1=+180 (vary J2) ===")
	for j2 in range(-40, 45, 5):
		var angles: Array[float] = [180.0, float(j2), 119.78, -0.19, 71.70, 114.08]
		robot.set_joint_angles(angles)
		var tip: Vector3 = robot.get_tool_tip_position()
		var cup_y: float = vac.global_transform.basis.orthonormalized().y.dot(Vector3.UP)
		print("J2=%+4d  tip=(%.3f, %.3f, %.3f)  cupY=%.4f" % [j2, tip.x, tip.y, tip.z, cup_y])

	# Vary J2 to see reach range at J1=-180
	print("\n=== REACH RANGE at J1=-180 (vary J2) ===")
	for j2 in range(-40, 45, 5):
		var angles: Array[float] = [-180.0, float(j2), 119.78, -0.19, 71.70, 114.08]
		robot.set_joint_angles(angles)
		var tip: Vector3 = robot.get_tool_tip_position()
		var cup_y: float = vac.global_transform.basis.orthonormalized().y.dot(Vector3.UP)
		print("J2=%+4d  tip=(%.3f, %.3f, %.3f)  cupY=%.4f" % [j2, tip.x, tip.y, tip.z, cup_y])

	# Also try varying J3 at J1=+180
	print("\n=== REACH RANGE at J1=+180 (vary J3) ===")
	for j3 in range(80, 165, 5):
		var angles: Array[float] = [180.0, -12.66, float(j3), -0.19, 71.70, 114.08]
		robot.set_joint_angles(angles)
		var tip: Vector3 = robot.get_tool_tip_position()
		var cup_y: float = vac.global_transform.basis.orthonormalized().y.dot(Vector3.UP)
		print("J3=%+4d  tip=(%.3f, %.3f, %.3f)  cupY=%.4f" % [j3, tip.x, tip.y, tip.z, cup_y])

	quit(0)
