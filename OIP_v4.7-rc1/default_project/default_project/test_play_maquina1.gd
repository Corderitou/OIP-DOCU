extends SceneTree

var _t := 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== PLAY MAQUINA1 START ===")
	var packed: PackedScene = load("res://Simulation.tscn")
	if packed == null:
		print("FAIL load Simulation.tscn")
		quit(1)
		return
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	await process_frame
	var mq := sim.get_node_or_null("Maquina1") as Maquina1
	var st := sim.get_node_or_null("Maquina1/Stringer") as Node3D
	if mq == null or st == null:
		print("FAIL: Maquina1 o Stringer ausentes en disco")
		quit(1)
		return
	var head := st.get_node_or_null("Head") as Node3D
	if head == null:
		print("FAIL: Head ausente")
		quit(1)
		return
	var passed := false
	for i in range(40):
		await create_timer(0.2).timeout
		_t += 0.2
		if i == 10:
			print("t=%.1f SET manual z=0.5 y=0.4" % _t)
			mq.z_position = 0.5
			mq.y_position = 0.4
		if i == 15:
			passed = is_equal_approx(mq.z_position, 0.5) and is_equal_approx(mq.y_position, 0.4)
			print("t=%.1f axis stick -> %s (z=%.3f y=%.3f)" % [_t, "OK" if passed else "NO", mq.z_position, mq.y_position])
	print(passed and "ALL_OK" or "HAS_FAILURES")
	print("=== PLAY MAQUINA1 END ===")
	quit(0 if passed else 1)
