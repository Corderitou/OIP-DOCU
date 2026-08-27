extends SceneTree

var failures := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS | " + label)
	else:
		print("FAIL | " + label)
		failures += 1


func _init() -> void:
	var packed := load("res://parts/Maquina1.tscn") as PackedScene
	_check(packed != null, "load parts/Maquina1.tscn")
	if packed == null:
		quit(1)
		return
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	await process_frame

	var mq := inst as Maquina1
	var stringer := inst.get_node_or_null("Stringer") as Stringer
	var dispenser := inst.get_node_or_null("Dispenser") as Dispenser
	_check(mq != null, "script Maquina1 attached")
	_check(stringer != null, "Stringer child found")
	_check(dispenser != null, "Dispenser child found")
	if stringer == null:
		inst.free()
		quit(1 if failures > 0 else 0)
		return

	var head := stringer.get_node_or_null("Head")
	_check(head != null, "Stringer/Head found")
	var picker := stringer.get_node_or_null("Head/picker")
	_check(picker != null, "Stringer/Head/picker found")

	if head != null:
		var start: Vector3 = head.position
		mq.z_position = 0.5
		mq.y_position = 0.4
		await process_frame
		var after: Vector3 = head.position
		_check(after != start, "head moved with z/y (start=" + str(start) + " after=" + str(after) + ")")
		_check(absf(after.y - 0.4) < 0.001 and absf(after.z - 0.5) < 0.001,
				"head at target y=0.4 z=0.5 (got " + str(after) + ")")

	var sim := load("res://Simulation.tscn") as PackedScene
	_check(sim != null, "load Simulation.tscn")
	if sim != null:
		var s_inst := sim.instantiate() as Node3D
		root.add_child(s_inst)
		await process_frame
		await process_frame
		var s_mq := s_inst.get_node_or_null("Maquina1") as Maquina1
		var s_st := s_inst.get_node_or_null("Maquina1/Stringer") as Stringer
		_check(s_mq != null, "Simulation Maquina1 script attached")
		_check(s_st != null, "Simulation Maquina1/Stringer found")
		if s_st != null:
			var s_head := s_st.get_node_or_null("Head")
			_check(s_head != null, "Simulation Stringer/Head found")
			if s_head != null:
				var s_start: Vector3 = s_head.position
				s_mq.z_position = 0.3
				s_mq.y_position = 0.25
				await process_frame
				var s_after: Vector3 = s_head.position
				_check(s_after != s_start, "Simulation head moved (start=" + str(s_start) + " after=" + str(s_after) + ")")
		s_inst.free()

	inst.free()
	quit(1 if failures > 0 else 0)
