extends SceneTree

# Probe: mide la posicion de la ventosa del SixAxisRobot para cada waypoint
# de la grilla (cmds 4-11) directamente desde los datos de Simulation.tscn.

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"

var WPS := {
	"4": [-156.79773595638318, -12.658969999263624, 119.7773205080408, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"5": [-153.85993904, -25.20324317, 127.21582442, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"6": [-159.62914789, -2.50053, 110.93979028, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"7": [-161.84674358, 6.88841214, 101.14231896, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"8": [-156.13531381, 10.53992462, 96.79634148, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"9": [-153.02160126, 1.36845678, 106.91599157, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"10": [-149.62326223, -7.07172081, 115.52620104, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
	"11": [-144.40804678, -17.6568456, 123.25490662, -0.18531342611845203, 71.70228757134491, 114.0817522666217],
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(ROBOT_SCENE)
	if packed == null:
		push_error("No se pudo cargar " + ROBOT_SCENE)
		quit(1)
		return
	var robot: Node3D = packed.instantiate()
	root.add_child(robot)
	robot.robot_scale = 0.7
	robot.show_gizmos = false

	var base_pos: Vector3 = robot.global_position
	var vac: Area3D = robot._vacuum_area
	print("BASE global = ", base_pos)

	# Reference tip (cmd4)
	robot.set_joint_angles(WPS["4"])
	var ref_tip: Vector3 = robot.get_tool_tip_position()
	var ref_cup: float = vac.global_transform.basis.y.dot(Vector3.UP)
	print("REF cmd4 tip=", ref_tip, " cupYdotUP=%.4f" % ref_cup)
	print("REF cmd4 radial=", Vector2(ref_tip.x - base_pos.x, ref_tip.z - base_pos.z).length())

	var PITCH := 0.17
	var fails := 0

	for key in WPS.keys():
		var angles: Array[float] = []
		for v in WPS[key]:
			angles.append(float(v))
		robot.set_joint_angles(angles)
		var tip: Vector3 = robot.get_tool_tip_position()
		var cup: float = vac.global_transform.basis.y.dot(Vector3.UP)
		var radial: float = Vector2(tip.x - base_pos.x, tip.z - base_pos.z).length()

		# Expected position from grid
		var cell_x: float = 0.0
		var cell_y: float = 0.0
		match key:
			"4": cell_x = 2.0; cell_y = 1.0
			"5": cell_x = 1.0; cell_y = 1.0
			"6": cell_x = 3.0; cell_y = 1.0
			"7": cell_x = 4.0; cell_y = 1.0
			"8": cell_x = 4.0; cell_y = 2.0
			"9": cell_x = 3.0; cell_y = 2.0
			"10": cell_x = 2.0; cell_y = 2.0
			"11": cell_x = 1.0; cell_y = 2.0
		var expected := ref_tip + Vector3((cell_x - 2.0) * PITCH, 0.0, -(cell_y - 1.0) * PITCH)
		var pos_err := tip.distance_to(expected)

		print("cmd%s tip=%s cupYdotUP=%.4f radial=%.4f pos_err=%.4f J1=%.1f J5=%.1f" % [
			key, tip, cup, radial, pos_err, angles[0], angles[4]])

		if pos_err > 0.05:
			fails += 1
			print("  !! cmd%s position error too large: %.4f" % [key, pos_err])

	# Check cup consistency
	print("\n---- CUP CONSISTENCY CHECK ----")
	var cups: Array[float] = []
	for key in ["4", "5", "6", "7", "8", "9", "10", "11"]:
		robot.set_joint_angles(WPS[key])
		var cup: float = vac.global_transform.basis.y.dot(Vector3.UP)
		cups.append(cup)
	var min_cup: float = cups.min()
	var max_cup: float = cups.max()
	print("Cup range: [%.4f, %.4f] spread=%.4f" % [min_cup, max_cup, max_cup - min_cup])

	# Check spacing
	print("\n---- SPACING CHECK ----")
	var tips: Array[Vector3] = []
	for key in ["4", "5", "6", "7", "8", "9", "10", "11"]:
		robot.set_joint_angles(WPS[key])
		tips.append(robot.get_tool_tip_position())
	# Row 1: 4-5, 5-6, 6-7
	for idx in range(3):
		var dist: float = tips[idx].distance_to(tips[idx + 1])
		print("Row1 cmd%d<->cmd%d = %.4f" % [idx + 4, idx + 5, dist])
	# Row 2: 8-9, 9-10, 10-11
	for idx in range(4, 7):
		var dist: float = tips[idx].distance_to(tips[idx + 1])
		print("Row2 cmd%d<->cmd%d = %.4f" % [idx + 4, idx + 5, dist])
	# Columns: 4-10, 5-11, 6-9, 7-8
	var col_pairs := [[0, 6], [1, 7], [2, 5], [3, 4]]
	for p in col_pairs:
		var dist: float = tips[p[0]].distance_to(tips[p[1]])
		print("Col cmd%d<->cmd%d = %.4f" % [p[0] + 4, p[1] + 4, dist])

	print("\nPROBE %s (fails=%d)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
