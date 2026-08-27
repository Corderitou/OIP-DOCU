extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST REPRO5 START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	comms.register_tag("PLCSIM", "ns=2;s=ProbeOne", 1) == true

	print("--- write_bit(PLCSIM, '', true) ---")
	comms.write_bit("PLCSIM", "", true)
	print("--- write_bit('', 'ns=2;s=ProbeOne', true) ---")
	comms.write_bit("", "ns=2;s=ProbeOne", true)
	print("--- write_bit(PLCSIM, ns=2;s=ProbeOne, true) ---")
	comms.write_bit("PLCSIM", "ns=2;s=ProbeOne", true)

	var s: Object = Engine.get_singleton("Simulation")
	print("=== emitting started (starts polling) ===")
	s.emit_signal("started")
	for i in range(32):
		await create_timer(0.25).timeout
		comms.write_bit("PLCSIM", "ns=2;s=ProbeOne", true)
		if i % 4 == 0:
			print("tick ", i)
	print("=== TEST REPRO5 END ===")
	quit(0)
