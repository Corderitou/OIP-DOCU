extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST REPRO7 START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	print("--- method_list ---")
	for m in comms.get_method_list():
		print("M ", m.get("name"), " args=", m.get("args"))
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	print("--- register_tag('', 'ns=2;s=X', 1) ---")
	var r1: bool = comms.register_tag("", "ns=2;s=X", 1) == true
	print("result=", r1, " get_tag_groups=", comms.get_tag_groups())
	print("--- register_tag('EMPTY', '', 1) ---")
	var r2: bool = comms.register_tag("EMPTY", "", 1) == true
	print("result=", r2, " get_tag_groups=", comms.get_tag_groups())
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	for i in range(24):
		await create_timer(0.25).timeout
	print("--- get_tag_groups AFTER run: ", comms.get_tag_groups())
	print("=== TEST REPRO7 END ===")
	quit(0)
