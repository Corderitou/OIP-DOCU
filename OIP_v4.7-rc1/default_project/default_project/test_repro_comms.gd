extends SceneTree

var _repro := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST REPRO START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	print("=== OIPComms singleton: ", comms)
	if comms:
		comms.set_enable_comms(true)
		comms.clear_tag_groups()
		comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
		print("=== tag groups registered ===")
	var packed: PackedScene = load("res://Simulation.tscn")
	print("=== loaded Simulation.tscn: ", packed)
	if packed == null:
		print("=== TEST REPRO END (no scene) ===")
		quit(1)
		return
	var sim := packed.instantiate()
	root.add_child(sim)
	print("=== instantiated, children: ", sim.get_child_count())
	await process_frame
	var sim_sig: Object = Engine.get_singleton("Simulation")
	print("=== emitting started ===")
	sim_sig.emit_signal("started")
	for i in range(40):
		await create_timer(0.25).timeout
	print("=== TEST REPRO END ===")
	quit(0)
