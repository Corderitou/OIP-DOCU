extends SceneTree

var _t := 0.0


func _init() -> void:
	call_deferred("_run")


func _on_polled(g: String) -> void:
	print("P t=%.1f POLL '%s'" % [_t, g])


func _on_group_init(g: String) -> void:
	print("P t=%.1f INIT '%s'" % [_t, g])


func _on_err() -> void:
	print("P t=%.1f SIG comms_error" % _t)


func _run() -> void:
	print("=== TEST REPRO10 START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.tag_group_polled.connect(_on_polled)
	comms.tag_group_initialized.connect(_on_group_init)
	comms.comms_error.connect(_on_err)
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	comms.register_tag("PLCSIM", "ns=2;s=BeltConveyor_Running", 1)
	comms.set_sim_running(true)
	for i in range(60):
		await create_timer(0.1).timeout
		_t += 0.1
	print("=== TEST REPRO10 END ===")
	quit(0)
