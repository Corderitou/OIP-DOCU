extends SceneTree

# Segunda pasada: para cada celda prueba 2 semillas (WP4 y solucion previa)
# y elige la que mantenga la copa mas alineada con la referencia de P4
# (eje +Y del VacuumArea ~ vertical) con error <= 1 cm.

const ROBOT_SCENE := "res://parts/SixAxisRobot.tscn"
const PITCH := 0.17

var WP4 := [180.0, 0.6, 106.19999999999999, -1.0, 67.80000000000001, 90.0]

var ORDER := [
	["5: Point5", Vector2(1, 1)],
	["6: Point6", Vector2(3, 1)],
	["7: Point7", Vector2(4, 1)],
	["8: Point8", Vector2(4, 2)],
	["9: Point9", Vector2(3, 2)],
	["10: Point10", Vector2(2, 2)],
	["11: Point11", Vector2(1, 2)],
]

func _to_f(a: Array) -> Array[float]:
	var out: Array[float] = []
	for v in a:
		out.append(float(v))
	return out

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

	var wp4a := _to_f(WP4)
	robot.set_joint_angles(wp4a)
	var p4: Vector3 = robot.get_tool_tip_position()
	var vac: Area3D = robot._vacuum_area
	if vac == null:
		push_error("VacuumArea no encontrada")
		quit(1)
		return
	var cup_ref: float = vac.global_transform.basis.y.dot(Vector3.UP)
	print("P4 tip=", p4, " cupYdotUP=%.4f" % cup_ref)

	var chosen := {}
	var fails := 0
	var prev_seed := wp4a

	for entry in ORDER:
		var wname: String = entry[0]
		var cell: Vector2 = entry[1]
		var target := p4 + Vector3((cell.x - 2.0) * PITCH, 0.0, -(cell.y - 1.0) * PITCH)
		var best_score := INF
		var best_err := INF
		var best_cup := 0.0
		var best_angles: Array[float] = []
		for seed in [wp4a, prev_seed]:
			robot.set_joint_angles(_to_f(seed))
			robot.solve_ik(target)
			var err: float = robot.get_tool_tip_position().distance_to(target)
			var cup: float = vac.global_transform.basis.y.dot(Vector3.UP)
			print("%s err=%.4f cupYdotUP=%.4f angles=%s" % [wname, err, cup, robot.get_joint_angles()])
			var score: float = absf(cup - cup_ref) * 10.0 + err
			if err <= 0.01 and score < best_score:
				best_score = score
				best_err = err
				best_cup = cup
				best_angles = robot.get_joint_angles()
		if best_angles.is_empty():
			fails += 1
			print("!! %s SIN SOLUCION ACEPTABLE" % wname)
		else:
			chosen[wname] = best_angles
			prev_seed = best_angles
			print(">> %s elegido err=%.4f cupYdotUP=%.4f" % [wname, best_err, best_cup])

	print("---- RESUMEN fails=%d ----" % fails)
	for wname in chosen.keys():
		var a: Array = chosen[wname]
		var s := "["
		for i in a.size():
			s += String.num(a[i], 12)
			if i < a.size() - 1:
				s += ", "
		s += "]"
		print('%s = Array[float](%s)' % [wname, s])
	quit(0 if fails == 0 else 1)
