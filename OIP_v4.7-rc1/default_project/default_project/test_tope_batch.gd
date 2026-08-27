extends SceneTree

## Headless validation del tope fisico del batch tejido: el producto debe detenerse
## contra TopeFisico (StaticBody3D capa 1) aunque la cinta siga empujando. Los batches
## son independientes: el segundo producto sigue avanzando mientras el primero esta
## detenido. Cuando el robot desmonta ambos cuerpos del lote (top_level), el shell
## vacio se libera y los cuerpos sobreviven bajo ReleasedBatches.

var _failures := 0


func _check(ok: bool, label: String) -> void:
	print(("PASS | " if ok else "FAIL | ") + label)
	if not ok:
		_failures += 1


func _init() -> void:
	call_deferred("_run")


func _spawn_placer(parent: Node, world_pos: Vector3) -> Node3D:
	var p := (load("res://parts/Placer.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(p)
	p.global_position = world_pos
	var body := p.get_node_or_null("RigidBody3D") as RigidBody3D
	if body:
		body.top_level = true
		body.freeze = false
	return p


func _spawn_celda(parent: Node, world_pos: Vector3) -> Node3D:
	var c := (load("res://parts/Celda.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(c)
	c.global_position = world_pos
	var body := c.get_node_or_null("RigidBody3D") as RigidBody3D
	if body:
		body.top_level = true
		body.freeze = false
	return c


func _spawn_tira(parent: Node, start: Vector3, end: Vector3) -> Node3D:
	var t := (load("res://parts/Tira.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(t)
	(t as Tira).build_chain(start, end, Vector3.ZERO)
	return t


func _spawn_stack(parent: Node, center: Vector3, belt_top: float) -> void:
	_spawn_tira(parent, Vector3(center.x - 0.12, belt_top + 0.002, center.z - 0.03), Vector3(center.x + 0.12, belt_top + 0.002, center.z - 0.03))
	_spawn_tira(parent, Vector3(center.x - 0.12, belt_top + 0.002, center.z + 0.03), Vector3(center.x + 0.12, belt_top + 0.002, center.z + 0.03))
	_spawn_celda(parent, Vector3(center.x, belt_top + 0.006, center.z))
	_spawn_placer(parent, Vector3(center.x, belt_top + 0.015, center.z))


## Alimenta stacks uno a uno hasta alcanzar el consumo objetivo.
func _feed_until(sim: Node, station: SandwichStation, target: int, center: Vector3, belt_top: float) -> void:
	_spawn_stack(sim, center, belt_top)
	var t := 0.0
	while t < 4.0:
		if station._consumed >= target:
			return
		await physics_frame
		t += 0.01666


func _run() -> void:
	print("=== TEST TOPE BATCH START ===")
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	# comms OFF en toda la escena: hermetico frente al flujo Node-RED desplegado,
	# que puede pulsar IndexingBelt3_Step y arrastrar los stacks de la zona.
	for n in sim.find_children("*", "Node", true, false):
		if "enable_comms" in n:
			n.set("enable_comms", false)
	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	await process_frame
	await physics_frame

	var station := sim.get_node_or_null("SandwichStation") as SandwichStation
	var ib = sim.get_node_or_null("Building/ETAPA 1/IndexingBeltConveyor3")
	if station == null or ib == null:
		_check(false, "SandwichStation e IndexingBeltConveyor3 presentes")
		quit(1)
		return
	var sp := station.global_position
	var belt_body := ib.get_node_or_null("BeltBody") as StaticBody3D
	var belt_top: float = belt_body.global_position.y + 0.015

	# --- TopeFisico: estatico en capa 1 con caja ---
	var tope := sim.get_node_or_null("TopeFisico") as StaticBody3D
	_check(tope != null, "TopeFisico presente en Simulation.tscn")
	var wall_face := 0.0
	if tope:
		_check(tope.collision_layer == 1, "TopeFisico collision_layer = 1 (shell mask 1 choca)")
		var cs := tope.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var box: BoxShape3D = null
		if cs:
			box = cs.shape as BoxShape3D
		_check(box != null and box.size.x > 0.0, "TopeFisico con BoxShape3D")
		if box:
			wall_face = tope.global_position.x - box.size.x * 0.5
	# Frente del shell del producto = max_x (0.078) + padding 0.005 desde el origen.
	var rest_x := wall_face - 0.083

	# --- batch 1 completo (6 stacks), cinta parada ---
	for i in 6:
		await _feed_until(sim, station, i + 1, sp, belt_top)
	_check(station._consumed >= 6, "batch 1 completo (%d unidades)" % station._consumed)
	var product := sim.get_node_or_null("SandwichProduct") as Node3D
	_check(product != null and product.get_node_or_null("ProductUnits/Batch_0/WovenBatch_0") != null, "producto 1 con WovenBatch_0")
	if product == null:
		quit(1)
		return

	# --- cinta rapida: el producto avanza y debe frenar contra el tope ---
	ib.set("step_speed", 1.0)
	for i in 40:
		ib.advance()
	var t0 := 0.0
	var prev_x: float = product.global_position.x
	while t0 < 12.0:
		await physics_frame
		t0 += 0.01666
		var nx: float = product.global_position.x
		if absf(nx - prev_x) < 0.0005 and absf(nx - rest_x) < 0.2:
			break
		prev_x = nx
	print("product rest x=%.4f (esperado %.4f)" % [product.global_position.x, rest_x])
	_check(absf(product.global_position.x - rest_x) < 0.01, "producto detenido con el frente contra el tope (%.4f vs %.4f)" % [product.global_position.x, rest_x])

	# --- la cinta sigue empujando y el tope lo retiene ---
	var held_x: float = product.global_position.x
	var t1 := 0.0
	while t1 < 1.5:
		await physics_frame
		t1 += 0.01666
	_check(absf(product.global_position.x - held_x) < 0.002, "tope retiene el batch con la cinta empujando (%.4f -> %.4f)" % [held_x, product.global_position.x])

	# --- batch 2: independiente, avanza mientras el 1 sigue detenido ---
	for i in 40:
		ib.advance()
	await _feed_until(sim, station, 7, sp, belt_top)
	var product1 := sim.get_node_or_null("SandwichProduct_1") as Node3D
	_check(product1 != null and product1.get_node_or_null("ProductUnits/Batch_0/WovenBatch_0") != null, "producto 2 con su propio Batch_0")
	if product1:
		var follower_x0: float = product1.global_position.x
		var leader_x: float = product.global_position.x
		var t2 := 0.0
		while t2 < 0.5:
			await physics_frame
			t2 += 0.01666
		_check(product1.global_position.x > follower_x0 + 0.02, "batch 2 avanza mientras el 1 esta detenido (%.3f -> %.3f)" % [follower_x0, product1.global_position.x])
		_check(absf(product.global_position.x - leader_x) < 0.002, "batch 1 sigue detenido en el tope")
	for i in 5:
		await _feed_until(sim, station, 8 + i, sp, belt_top)
	_check(station._consumed >= 12, "batch 2 completo (%d unidades)" % station._consumed)

	# --- pick del robot sobre el batch 1: shell vacio se libera, cuerpos sobreviven ---
	var woven := product.get_node_or_null("ProductUnits/Batch_0/WovenBatch_0") as RigidBody3D
	var placer := product.get_node_or_null("ProductUnits/Batch_0/PlacerBatch_0") as RigidBody3D
	if woven and placer:
		woven.top_level = true
		placer.top_level = true
		await physics_frame
		await physics_frame
		var container := sim.get_node_or_null("ReleasedBatches")
		_check(container != null and woven.get_parent() == container and placer.get_parent() == container, "cuerpos desmontados bajo ReleasedBatches")
		_check(is_instance_valid(woven) and is_instance_valid(placer), "cuerpos desmontados siguen vivos")
		_check(not product.visible and product.get_node_or_null("ProductUnits/Batch_0") == null, "shell del producto 1 liberado (oculto y vacio)")
	else:
		_check(false, "WovenBatch_0/PlacerBatch_0 presentes antes del pick")

	# --- el batch 2 continua hasta el tope y queda detenido ---
	if product1:
		for i in 40:
			ib.advance()
		var t3 := 0.0
		var prev_x1: float = product1.global_position.x
		while t3 < 12.0:
			await physics_frame
			t3 += 0.01666
			var nx1: float = product1.global_position.x
			if absf(nx1 - prev_x1) < 0.0005 and absf(nx1 - rest_x) < 0.2:
				break
			prev_x1 = nx1
		_check(absf(product1.global_position.x - rest_x) < 0.01, "batch 2 detenido contra el tope (%.4f vs %.4f)" % [product1.global_position.x, rest_x])

	s.emit_signal("stopped")
	await process_frame
	print("=== TEST TOPE BATCH END ===")
	print("ALL_OK" if _failures == 0 else "HAS_FAILURES")
	quit(0 if _failures == 0 else 1)
