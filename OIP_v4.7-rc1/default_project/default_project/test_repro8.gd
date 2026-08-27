extends SceneTree

var _t := 0.0


func _init() -> void:
	call_deferred("_run")


func _on_polled(g: String) -> void:
	print("P t=%.1f POLL '%s'" % [_t, g])


func _on_group_init(g: String) -> void:
	print("P t=%.1f INIT '%s'" % [_t, g])


func _on_read(g: String, tag: String, v: Variant) -> void:
	print("P t=%.1f READ group='%s' tag='%s' -> %s" % [_t, g, tag, str(v)])


func _on_written(g: String, tag: String, v: Variant) -> void:
	print("P t=%.1f WRITE group='%s' tag='%s' = %s" % [_t, g, tag, str(v)])


func _on_err() -> void:
	print("P t=%.1f SIG comms_error" % _t)


func _run() -> void:
	print("=== TEST REPRO8 START ===")
	var hub: Object = root.get_node_or_null("CommsHub")
	if hub == null:
		hub = Engine.get_singleton("OIPComms")
	print("hub=", hub)
	hub.tag_group_polled.connect(_on_polled)
	hub.tag_group_initialized.connect(_on_group_init)
	if hub.has_signal("tag_read"):
		hub.tag_read.connect(_on_read)
	if hub.has_signal("tag_written"):
		hub.tag_written.connect(_on_written)
	hub.comms_error.connect(_on_err)
	hub.set_enable_comms(true)
	hub.clear_tag_groups()
	hub.register_tag_group("PLCSIM", 1000, "opc_ua", "opc.tcp://localhost:4840", "1,0", "ControlLogix")
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	for i in range(80):
		await create_timer(0.1).timeout
		_t += 0.1
	print("=== TEST REPRO8 END ===")
	quit(0)
