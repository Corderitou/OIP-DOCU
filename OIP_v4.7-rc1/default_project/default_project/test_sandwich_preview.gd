extends SceneTree

## Validates the editor preview of SandwichStation: calling _rebuild_preview()
## creates PreviewSandwichProduct with N segments as children; _clear_preview()
## removes it.

var _failures := 0


func _check(ok: bool, label: String) -> void:
	print(("PASS | " if ok else "FAIL | ") + label)
	if not ok:
		_failures += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST SANDWICH PREVIEW START ===")
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame

	var station := sim.get_node_or_null("SandwichStation") as SandwichStation
	_check(station != null, "SandwichStation presente")
	if station == null:
		quit(1)
		return

	station.preview_units = 1
	station._rebuild_preview()
	var pv := station.get_node_or_null("PreviewSandwichProduct")
	_check(pv != null, "preview creada")
	if pv != null:
		var celdas := 0
		var bundles := 0
		for c in pv.find_children("*", "Node3D", true, false):
			if str(c.name).begins_with("CeldaUnit"):
				celdas += 1
			elif str(c.name).begins_with("Bundle"):
				bundles += 1
		_check(celdas == 1 and bundles == 1, "preview con 1 unidad (celda=%d bundle=%d)" % [celdas, bundles])

	station.preview_units = 3
	station._rebuild_preview()
	pv = station.get_node_or_null("PreviewSandwichProduct")
	if pv != null:
		var celdas := 0
		for c in pv.find_children("*", "Node3D", true, false):
			if str(c.name).begins_with("CeldaUnit"):
				celdas += 1
		_check(celdas == 3, "preview regenerada con 3 celdas (patron 1->2->2) (celda=%d)" % celdas)

	station._clear_preview()
	_check(not is_instance_valid(station.get_node_or_null("PreviewSandwichProduct")), "preview limpiada")
	# _clear_preview no debe tocar el producto runtime
	_check(station._product == null or not station._product.visible, "producto runtime oculto antes de play")

	sim.queue_free()
	print("=== TEST SANDWICH PREVIEW END ===")
	quit(0 if _failures == 0 else 1)
