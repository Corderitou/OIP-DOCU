extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _dump_tags(node: Node, depth: int = 0) -> void:
	var indent := "  ".repeat(depth)
	if node.get("tag_group_name") != null:
		print(indent, node.name, " tag_group_name='", node.get("tag_group_name"), "'")
	for prop in ["_speed_tag", "_running_tag", "_tag", "_comms", "_command_tag", "_execute_tag", "_done_tag", "_vacuum_tag", "_gate_tag", "_pushbutton_tag"]:
		var v: Variant = node.get(prop)
		if v is OIPCommsTag:
			print(indent, node.name, " .", prop, " group='", v.tag_group_name, "' tag='", v.tag_name, "' registered=", v.is_registered())
	for child in node.get_children():
		_dump_tags(child, depth + 1)


func _run() -> void:
	print("=== TEST REPRO4 START ===")
	var comms: Object = Engine.get_singleton("OIPComms")
	comms.set_enable_comms(true)
	comms.clear_tag_groups()
	comms.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	print("=== emitting started ===")
	s.emit_signal("started")
	for i in range(12):
		await create_timer(0.25).timeout
	print("=== TAG DUMP AFTER START ===")
	_dump_tags(sim)
	print("=== TEST REPRO4 END ===")
	quit(0)
