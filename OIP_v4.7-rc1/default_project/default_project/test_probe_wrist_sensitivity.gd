extends SceneTree

# Diagnostico: sensibilidad del tooltip (VacuumArea) a J4/J5/J6 en la pose
# vieja de Point12. Si mover la muneca corre mucho el tooltip, orientacion
# y posicion estan fuertemente acopladas y hay que resolverlas juntos.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://Simulation.tscn")
	var inst: Node3D = packed.instantiate()
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(inst)
	var robot: Node3D = inst.get_node("SixAxisRobot")

	var base: Array[float] = [138.23, -29.11, 129.72, -0.00000137, 79.38999489, 48.22997348]
	robot.set_joint_angles(base)
	var p0: Vector3 = robot.get_tool_tip_position()
	var b0: Basis = robot.get_tool_tip_transform().basis.orthonormalized()
	print("base tip=", p0)
	print("base euler cabezal=", b0.get_euler())

	for case in [["J4+45", 3, 45.0], ["J5+20", 4, 20.0], ["J5-20", 4, -20.0],
			["J6+90", 5, 90.0], ["J6-90", 5, -90.0]]:
		var a := base.duplicate()
		a[case[1]] += case[2]
		robot.set_joint_angles(a)
		var p1: Vector3 = robot.get_tool_tip_position()
		print("%s dpos=%s |d|=%.4f m" % [case[0], p1 - p0, (p1 - p0).length()])

	quit(0)
