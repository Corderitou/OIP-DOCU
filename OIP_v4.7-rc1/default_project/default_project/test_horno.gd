extends SceneTree

## Test del Horno (src/Horno/horno.gd): cabezal que baja al detectar producto,
## ciclo auto-start, y sube al terminar. Sin depender de comms (fallback timer).

var _failures := 0


func _check(ok: bool, label: String) -> void:
	print(("PASS | " if ok else "FAIL | ") + label)
	if not ok:
		_failures += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST HORNO START ===")
	var scene: PackedScene = load("res://Simulation.tscn")
	var sim := scene.instantiate()
	root.add_child(sim)
	await process_frame
	await physics_frame

	var horno: Horno = sim.get_node_or_null("Horno")
	_check(horno != null, "Horno presente en Simulation.tscn")
	if horno == null:
		quit(1)
		return
	_check(horno is MaquinaTermica, "Horno extiende MaquinaTermica")

	var head: Node3D = horno.get_node_or_null("Head")
	_check(head != null, "cabezal 'Head' existe")

	# Spec de tags = base MaquinaTermica + prefijo H1.
	var spec := horno._build_tag_spec()
	for tag_name in [
		"H1_CMD", "H1_EXEC", "H1_DONE", "H1_RUNNING", "H1_READY",
		"H1_FAULT", "H1_IN_POS", "H1_SETPOINT", "H1_MV", "H1_PV", "H1_CYCLE_TIME"
	]:
		_check(spec.has(tag_name), "spec incluye %s" % tag_name)

	# Acelerar el ciclo para el test.
	horno.cycle_time = 0.4
	horno.head_move_time = 0.2
	var up_y: float = head.position.y

	Engine.get_singleton("Simulation").emit_signal("started")
	await process_frame

	_check(horno._running, "_running true tras started")

	# Producto falso bajo el horno (una unidad en la zona de deteccion).
	var prod := Node3D.new()
	prod.name = "SandwichProduct"
	root.add_child(prod)
	var unit := Node3D.new()
	unit.name = "CeldaUnit_0"
	prod.add_child(unit)
	unit.global_position = horno.global_position + Vector3(0, -0.5, 0)

	var detected := false
	var started := false
	var head_down := false
	for i in 80:
		await physics_frame
		if horno._product_present:
			detected = true
		if horno._cycle_active:
			started = true
		if detected and head.position.y < up_y - 0.01:
			head_down = true
	_check(detected, "producto detectado bajo el horno")
	_check(started, "auto-start: ciclo activo al detectar producto")
	_check(horno._product_present, "IN_POS (product_present) true")
	_check(head_down, "cabezal baja durante el ciclo")

	# Esperar fin de ciclo -> head sube.
	var finished := false
	for i in 200:
		await physics_frame
		if horno._done and not horno._cycle_active:
			finished = true
	_check(finished, "ciclo terminado (done true, cycle inactive)")

	var head_up := false
	for i in 120:
		await physics_frame
		if head.position.y >= up_y - 0.02:
			head_up = true
	_check(head_up, "cabezal sube al terminar el ciclo")

	# Sin producto -> IN_POS false.
	prod.queue_free()
	await process_frame
	await physics_frame
	var left := false
	for i in 40:
		await physics_frame
		if not horno._product_present:
			left = true
	_check(left, "sin producto: IN_POS false")

	Engine.get_singleton("Simulation").emit_signal("stopped")
	await process_frame
	_check(not horno._running, "_running false tras stopped")

	print("=== TEST HORNO END ===")
	quit(0 if _failures == 0 else 1)
