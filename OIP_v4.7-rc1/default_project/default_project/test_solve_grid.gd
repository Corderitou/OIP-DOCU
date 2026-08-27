extends SceneTree

# Resuelve por IK las 8 posiciones de la grilla 4x2 (pitch 0.17 m).
# Convencion confirmada: (2,1)=Point4 existente; izq=-X; abajo(fila 2)=-Z;
# altura constante. Siembra cada solve con la solucion anterior para mantener
# configuracion de brazo consistente. No toca comms ni guarda la escena.

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

	var seed_angles: Array[float] = []
	for v in WP4:
		seed_angles.append(float(v))
	robot.set_joint_angles(seed_angles)
	var p4: Vector3 = robot.get_tool_tip_position()
	var base_pos: Vector3 = robot.global_position
	print("P4 tip = ", p4, "  base = ", base_pos)

	var results := {}
	var fails := 0
	var prev: Array[float] = seed_angles

	for entry in ORDER:
		var wname: String = entry[0]
		var cell: Vector2 = entry[1]
		var target := p4 + Vector3((cell.x - 2.0) * PITCH, 0.0, -(cell.y - 1.0) * PITCH)
		robot.set_joint_angles(prev.duplicate())
		var ok: bool = robot.solve_ik(target)
		var tip: Vector3 = robot.get_tool_tip_position()
		var err := tip.distance_to(target)
		var rad := Vector2(tip.x - base_pos.x, tip.z - base_pos.z).length()
		var angles: Array[float] = robot.get_joint_angles()
		print("%s celda=(%d,%d) ok=%s err=%.4f radial=%.3f" % [wname, int(cell.x), int(cell.y), ok, err, rad])
		print("   target=", target, " tip=", tip)
		print("   angles=", angles)
		if ok and err <= 0.01:
			results[wname] = angles
			prev = angles
		else:
			fails += 1

	print("---- RESUMEN fails=%d ----" % fails)
	for wname in results.keys():
		var a: Array = results[wname]
		var s := "["
		for i in a.size():
			s += String.num(a[i], 10)
			if i < a.size() - 1:
				s += ", "
		s += "]"
		print("%s = Array[float](%s)" % [wname, s])
	quit(0 if fails == 0 else 1)
