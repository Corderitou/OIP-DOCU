extends SceneTree

var _tick := 0


func _init() -> void:
	call_deferred("_run")


func _on_init(g: String) -> void:
	print("SIG tag_group_initialized: '", g, "'")


func _on_poll(g: String) -> void:
	_tick += 1
	if _tick <= 3:
		print("SIG tag_group_polled: '", g, "'")


func _on_err() -> void:
	print("SIG comms_error")


func _run() -> void:
	print("=== TEST REPRO3 START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	comms.tag_group_initialized.connect(_on_init)
	comms.tag_group_polled.connect(_on_poll)
	comms.comms_error.connect(_on_err)
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	for child in sim.get_children():
		if child.get("enable_comms") == true:
			print("PART ", child.name, " tag_group_name='", child.get("tag_group_name"), "'")
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	print("=== emitting started ===")
	s.emit_signal("started")
	for i in range(32):
		await create_timer(0.25).timeout
	print("=== TEST REPRO3 END ===")
	quit(0)
