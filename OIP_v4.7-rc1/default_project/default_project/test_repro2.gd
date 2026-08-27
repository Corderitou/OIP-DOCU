extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST MIN START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	print("=== get_tag_groups: ", comms.get_tag_groups())
	var ok: bool = comms.register_tag("PLCSIM", "ns=2;s=ProbeOne", 1) == true
	print("=== register_tag ProbeOne -> ", ok)
	var ok2: bool = comms.register_tag("PLCSIM", "ns=2;s=ProbeTwo", 1) == true
	print("=== register_tag ProbeTwo -> ", ok2)
	for i in range(16):
		await create_timer(0.25).timeout
	print("=== TEST MIN END ===")
	quit(0)
