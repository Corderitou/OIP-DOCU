extends SceneTree

# Validacion IK con J6 incluido + parse del plugin de gizmo reescrito.

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"

var WP4 := [180.0, 0.6, 106.19999999999999, -1.0, 67.80000000000001, 90.0]

func _init() -> void:
	call_deferred("_run")

func _to_f(a: Array) -> Array[float]:
	var out: Array[float] = []
	for v in a:
		out.append(float(v))
	return out

func _run() -> void:
	var plugin_script = load("res://addons/robot_gizmo/robot_gizmo_plugin.gd")
	print("PLUGIN_PARSE_OK=", plugin_script != null)

	var packed: PackedScene = load(ROBOT_SCENE)
	if packed == null:
		push_error("No se pudo cargar " + ROBOT_SCENE)
		quit(1)
		return
	var robot: Node3D = packed.instantiate()
	root.add_child(robot)
	robot.robot_scale = 0.7
	robot.show_gizmos = false

	var wp4a := _to_f(WP4)
	robot.set_joint_angles(wp4a)
	var p4: Vector3 = robot.get_tool_tip_position()
	print("P4 tip=", p4)

	var targets := {
		"celda_(1,1)": p4 + Vector3(-0.17, 0, 0),
		"celda_(4,2)": p4 + Vector3(0.34, 0, -0.17),
		"mas_bajo": p4 + Vector3(0, -0.2, 0),
	}
	var fails := 0
	for tname in targets.keys():
		robot.set_joint_angles(wp4a)
		var ok: bool = robot.solve_ik(targets[tname])
		var err: float = robot.get_tool_tip_position().distance_to(targets[tname])
		var ang: Array[float] = robot.get_joint_angles()
		print("%s ok=%s err=%.4f angles=%s" % [tname, ok, err, ang])
		if not ok or err > 0.01:
			fails += 1
	print("IK6_FAILS=", fails)
	quit(0 if fails == 0 else 1)
