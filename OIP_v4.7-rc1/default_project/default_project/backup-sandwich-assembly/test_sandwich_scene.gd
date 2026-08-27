extends SceneTree

## Reproduces the sandwich assembly inside the REAL Simulation.tscn scene with
## faithful geometry: the tira chains are released (cut_chain) so they drop
## onto the indexing belt, celda + placer fall on top, the SandwichStation
## auto-assembles, then the indexing belt is stepped while we log the sled vs
## the parts, plus a second stack placed behind to observe interference.

var _failures := 0
var _t := 0.0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS | " + label)
	else:
		print("FAIL | " + label)
		_failures += 1


func _init() -> void:
	call_deferred("_run")


func _spawn_placer(parent: Node, world_pos: Vector3) -> Node3D:
	var p := (load("res://parts/Placer.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(p)
	p.global_position = world_pos
	var body := p.get_node_or_null("RigidBody3D") as RigidBody3D
	if body:
		body.freeze = false
	return p


func _spawn_celda(parent: Node, world_pos: Vector3) -> Node3D:
	var c := (load("res://parts/Celda.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(c)
	c.global_position = world_pos
	var body := c.get_node_or_null("RigidBody3D") as RigidBody3D
	if body:
		body.freeze = false
	return c


func _spawn_tira(parent: Node, start: Vector3, end: Vector3) -> Node3D:
	var t := (load("res://parts/Tira.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(t)
	(t as Tira).build_chain(start, end, Vector3.ZERO)
	(t as Tira).cut_chain()
	return t


func _first_body(node) -> RigidBody3D:
	if node is Array:
		node = node[0] if node.size() > 0 else null
	if node == null:
		return null
	for c in node.find_children("*", "RigidBody3D", true, false):
		return c as RigidBody3D
	return null


func _bbox(sim: Node, parts: Array, out: Array) -> void:
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	for p in parts:
		if p == null or not is_instance_valid(p):
			continue
		for c in p.find_children("*", "RigidBody3D", true, false):
			var b := c as RigidBody3D
			var pos := b.global_position
			minx = minf(minx, pos.x)
			maxx = maxf(maxx, pos.x)
			minz = minf(minz, pos.z)
			maxz = maxf(maxz, pos.z)
	out.clear()
	out.append(Vector3(minx, 0, minz))
	out.append(Vector3(maxx, 0, maxz))


func _run() -> void:
	print("=== TEST SANDWICH SCENE START ===")
	var packed: PackedScene = load("res://Simulation.tscn")
	var sim := packed.instantiate()
	root.add_child(sim)
	await process_frame
	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	await process_frame
	await physics_frame

	var station := sim.get_node_or_null("SandwichStation") as Node3D
	var ib := sim.get_node_or_null("Building/ETAPA 1/IndexingBeltConveyor3") as IndexingBeltConveyor
	var da := station.get_node_or_null("DetectArea") as Area3D
	var sp := station.global_position
	var belt_z := ib.global_position.z
	print("station=", sp, " detectArea=", da.global_position, " belt_z=", belt_z)

	# --- full clean stack centered on the station: 2 bottom tiras + celda + 2 top tiras + placer ---
	var t_b1 := _spawn_tira(sim, Vector3(sp.x - 0.13, 1.05, belt_z - 0.02), Vector3(sp.x + 0.13, 1.05, belt_z - 0.02))
	var t_b2 := _spawn_tira(sim, Vector3(sp.x - 0.13, 1.05, belt_z + 0.02), Vector3(sp.x + 0.13, 1.05, belt_z + 0.02))
	var celda := _spawn_celda(sim, Vector3(sp.x, 1.10, belt_z))
	var t_t1 := _spawn_tira(sim, Vector3(sp.x - 0.13, 1.16, belt_z - 0.02), Vector3(sp.x + 0.13, 1.16, belt_z - 0.02))
	var t_t2 := _spawn_tira(sim, Vector3(sp.x - 0.13, 1.16, belt_z + 0.02), Vector3(sp.x + 0.13, 1.16, belt_z + 0.02))
	var placer := _spawn_placer(sim, Vector3(sp.x, 1.22, belt_z))

	# --- second stack well behind the zone ---
	var t2 := _spawn_tira(sim, Vector3(sp.x - 0.62, 1.05, belt_z), Vector3(sp.x - 0.38, 1.05, belt_z))
	var celda2 := _spawn_celda(sim, Vector3(sp.x - 0.50, 1.10, belt_z))

	print("--- dejando caer/asentar 1.5s ---")
	for i in range(90):
		await physics_frame
		_t += 0.01666

	var found: Sandwich = null
	var t := 0.0
	while t < 4.0 and found == null:
		var sand := sim.find_children("*", "Sandwich", true, false)
		if sand.size() > 0:
			found = sand[0] as Sandwich
			break
		await physics_frame
		t += 0.01666
	_check(found != null, "SandwichStation assemblo sandwich en escena real")
	if found == null:
		print("DETECTADOS en zona: ", da.get_overlapping_bodies())
		Engine.get_singleton("Simulation").stop()
		quit(1)

	var bottom = found.get_part("tira_bottom")
	var top = found.get_part("tira_top")
	_check(bottom is Array and (bottom as Array).size() == 2, "sandwich tiene 2 tiras bottom")
	_check(top is Array and (top as Array).size() == 2, "sandwich tiene 2 tiras top")

	var sled := found.get_sled()
	sled.freeze = false
	var belt_body := ib.get_node_or_null("BeltBody") as StaticBody3D
	print("belt body layer=", belt_body.collision_layer, " mask=", belt_body.collision_mask)
	_check(sled.global_position.y < 1.01, "sled apoyado en la cinta (y=%.3f, cinta~0.982)" % sled.global_position.y)
	print("--- sled vs partes ---")
	var bb: Array = []
	_bbox(sim, [t_b1, t_b2, t2, celda, celda2, t_t1, t_t2, placer], bb)
	print("bbox stack (x/z): ", bb)
	print("sled pos=", sled.global_position, " shape=", sled.get_node_or_null("CollisionShape3D").shape.size if sled.get_node_or_null("CollisionShape3D") else "?")
	sled.collision_mask = 1
	print("sled mask ahora = 1 (solo cinta/static)")

	print("--- 3s avanzando IndexingBelt cada 0.5s ---")
	var step_t := 0.0
	for i in range(180):
		await physics_frame
		_t += 0.01666
		step_t += 0.01666
		if step_t >= 0.5:
			step_t = 0.0
			ib.advance()
			print("  >> advance")
		if i % 18 == 0:
			var line := "t=%.2f sled=(%.3f,%.3f,%.3f)" % [_t, sled.global_position.x, sled.global_position.y, sled.global_position.z]
			for key in ["placer", "celda", "tira_bottom", "tira_top"]:
				var part = found.get_part(key)
				var b := _first_body(part)
				if b:
					line += " | %s=(%.3f,%.3f,%.3f)" % [key, b.global_position.x, b.global_position.y, b.global_position.z]
			print(line)
			if is_instance_valid(t2):
				var b2 := _first_body(t2)
				if b2:
					print("  nextstack tira=(%.3f,%.3f) celda2=(%.3f,%.3f)" % [b2.global_position.x, b2.global_position.z, _first_body(celda2).global_position.x if is_instance_valid(celda2) else 0.0, _first_body(celda2).global_position.z if is_instance_valid(celda2) else 0.0])

	print("--- sled final: ", sled.global_position, " vel=", sled.linear_velocity)
	Engine.get_singleton("Simulation").stop()
	print("=== TEST SANDWICH SCENE END ===")
	quit(0)
