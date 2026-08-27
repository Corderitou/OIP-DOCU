extends SceneTree

var failures := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS | " + label)
	else:
		print("FAIL | " + label)
		failures += 1


func _make_product(origin_x: float) -> Dictionary:
	var product := Node3D.new()
	product.name = "SandwichProduct_test"
	root.add_child(product)
	product.position = Vector3(origin_x, 1.0, 0.0)
	var units_container := Node3D.new()
	units_container.name = "ProductUnits"
	product.add_child(units_container)
	var batch_container := Node3D.new()
	batch_container.name = "Batch_0"
	units_container.add_child(batch_container)
	var batch := RigidBody3D.new()
	batch.name = "PlacerBatch_0"
	batch.collision_layer = 10
	batch.collision_mask = 0
	batch.freeze = true
	batch.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	batch.gravity_scale = 0.0
	batch_container.add_child(batch)
	for i in 6:
		var unit := Node3D.new()
		unit.name = "PlacerUnit_%d" % i
		unit.position = Vector3((float(i) - 2.5) * 0.172, 0.0, 0.0)
		batch.add_child(unit)
		var model := Node3D.new()
		model.name = "PlacerModel_%d" % i
		unit.add_child(model)
		var shape := CollisionShape3D.new()
		shape.name = "PlacerShape_%d" % i
		shape.position = Vector3((float(i) - 2.5) * 0.172, 0.0, 0.0)
		batch.add_child(shape)
	return {"product": product, "batch": batch}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var script := load("res://src/PlacerExtractor/placer_extractor.gd") as Script
	_check(script != null, "parse script placer_extractor.gd")
	if script:
		_check(script.can_instantiate(), "can_instantiate placer_extractor.gd")
		_check(script.get_global_name() == "PlacerExtractor", "class_name PlacerExtractor")

	var packed := load("res://parts/PlacerExtractor.tscn") as PackedScene
	_check(packed != null, "load scene PlacerExtractor.tscn")
	if packed == null:
		print("HAS_FAILURES")
		quit(1)
		return
	var ext := packed.instantiate() as PlacerExtractor
	_check(ext != null, "root es PlacerExtractor")
	if ext == null:
		print("HAS_FAILURES")
		quit(1)
		return
	root.add_child(ext)

	var area := ext.get_node_or_null("DetectArea") as Area3D
	_check(area != null, "DetectArea presente")
	if area:
		_check(area.collision_layer == 0, "DetectArea collision_layer = 0")
		_check(area.collision_mask == 10, "DetectArea collision_mask = 10")
		_check(area.get_node_or_null("CollisionShape3D") != null, "DetectArea tiene CollisionShape3D")

	var made := _make_product(0.5)
	var batch: RigidBody3D = made["batch"]
	var product: Node3D = made["product"]

	ext._convert_units(batch, 0.42)
	var queued := 0
	var intact := 0
	for i in 6:
		var unit := batch.get_node_or_null("PlacerUnit_%d" % i)
		if unit == null or unit.is_queued_for_deletion():
			queued += 1
		else:
			intact += 1
	_check(queued == 1, "una unidad en la ventana marcada para borrado (%d)" % queued)
	_check(intact == 5, "cinco unidades fuera de la ventana intactas (%d)" % intact)

	var spawned: Array[Node] = []
	for child in root.get_children():
		if child is Placer:
			spawned.append(child)
	_check(spawned.size() == 1, "un Placer real emitido (%d)" % spawned.size())
	if spawned.size() == 1:
		var p := spawned[0] as Placer
		_check(p.instanced, "placer emitido con instanced = true")
		_check(absf(p.global_position.x - 0.414) < 0.01, "placer emitido en la X de la unidad (%.3f)" % p.global_position.x)

	product.position.x += 0.172
	ext._convert_units(batch, 0.42)
	var still_intact := 0
	for i in 6:
		var unit := batch.get_node_or_null("PlacerUnit_%d" % i)
		if unit != null and not unit.is_queued_for_deletion():
			still_intact += 1
	_check(still_intact == 4, "segunda pasada extrae otra unidad (intactas=%d)" % still_intact)
	var total := 0
	for child in root.get_children():
		if child is Placer:
			total += 1
	_check(total == 2, "dos placers reales emitidos en total (%d)" % total)

	var shapes_left := 0
	for child in batch.get_children():
		if child is CollisionShape3D and not child.is_queued_for_deletion():
			shapes_left += 1
	_check(shapes_left == 4, "shapes de unidades extraidas tambien retirados (%d)" % shapes_left)

	var foreign := RigidBody3D.new()
	foreign.name = "RigidBody3D"
	root.add_child(foreign)
	var before := total
	ext._convert_units(foreign, 0.42)
	var after := 0
	for child in root.get_children():
		if child is Placer:
			after += 1
	_check(after == before, "cuerpo ajeno (Placer normal) no genera extraccion")

	print(failures == 0 and "ALL_OK" or "HAS_FAILURES")
	quit(0 if failures == 0 else 1)
