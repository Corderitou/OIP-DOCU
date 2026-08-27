extends SceneTree

var _comms: Object


func _init() -> void:
	call_deferred("_run")


func _dump_tags(node: Node, depth: int = 0) -> void:
	for prop in ["_speed_tag", "_running_tag", "_tag", "_command_tag", "_execute_tag", "_done_tag", "_vacuum_tag"]:
		var v: Variant = node.get(prop)
		if v is OIPCommsTag:
			print("TAG ", node.name, " .", prop, " group='", v.tag_group_name, "' tag='", v.tag_name, "' reg=", v.is_registered(), " ready=", v.is_ready())
	for child in node.get_children():
		_dump_tags(child, depth + 1)


func _run() -> void:
	print("=== TEST REPRO6 START ===")
	_comms = Engine.get_singleton("OIPComms")
	_comms.set_enable_comms(true)
	_comms.clear_tag_groups()
	_comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	_comms.tag_group_polled.connect(_on_poll)
	_comms.comms_error.connect(_on_err)
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	print("=== emitting started ===")
	s.emit_signal("started")
	await create_timer(2.5).timeout
	print("=== DUMP @2.5s ===")
	_dump_tags(sim)
	await create_timer(5.5).timeout
	print("=== DUMP @8s ===")
	_dump_tags(sim)
	print("=== TEST REPRO6 END ===")
	quit(0)


func _on_poll(g: String) -> void:
	print("POLL '", g, "'")


func _on_err() -> void:
	print("SIG comms_error")
