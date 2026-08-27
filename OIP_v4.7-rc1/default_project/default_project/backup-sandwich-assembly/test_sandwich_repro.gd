extends SceneTree

## Headless test for the Sandwich composite + SandwichStation.
## Phase A: assemble a stack manually (2 bottom tiras + celda + 2 top tiras +
##          placer), confirm the sled carries the parts and a moving belt drags
##          the whole composite cleanly (parts ride the sled).
## Phase B: place a full stack in a SandwichStation zone and confirm auto-detect
##          assembles a Sandwich after the settle window.
## Phase C: first-stack case (0 bottom tiras) must still assemble without
##          hovering.
## Phase D: incomplete stack (single tira) must NOT be assembled.

var _failures := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS | " + label)
	else:
		print("FAIL | " + label)
		_failures += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST SANDWICH START ===")
	await _test_composite()
	await _test_station()
	await _test_first_stack()
	await _test_incomplete()
	print("=== TEST SANDWICH END ===")
	print("ALL_OK" if _failures == 0 else "HAS_FAILURES")
	quit(0 if _failures == 0 else 1)


func _spawn_placer(parent: Node, world_pos: Vector3) -> Node3D:
	var p := (load("res://parts/Placer.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(p)
	p.global_position = world_pos
	var body := p.get_node_or_null("RigidBody3D") as RigidBody3D
	if body:
		body.freeze = true
	return p


func _spawn_celda(parent: Node, world_pos: Vector3) -> Node3D:
	var c := (load("res://parts/Celda.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(c)
	c.global_position = world_pos
	var body := c.get_node_or_null("RigidBody3D") as RigidBody3D
	if body:
		body.freeze = true
	return c


func _spawn_tira(parent: Node, start: Vector3, end: Vector3) -> Node3D:
	var t := (load("res://parts/Tira.tscn") as PackedScene).instantiate() as Node3D
	parent.add_child(t)
	(t as Tira).build_chain(start, end, Vector3.ZERO)
	return t


func _make_belt(parent: Node, vel: float) -> StaticBody3D:
	var belt := StaticBody3D.new()
	belt.name = "Belt"
	belt.collision_layer = 1
	belt.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	belt.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.02, 0.6)
	cs.shape = box
	belt.add_child(cs)
	belt.position = Vector3(0, -0.01, 0)
	belt.constant_linear_velocity = Vector3(vel, 0, 0)
	parent.add_child(belt)
	return belt


func _test_composite() -> void:
	var holder := Node3D.new()
	holder.name = "CompositeHolder"
	root.add_child(holder)

	_make_belt(holder, 0.5)

	var sandwich := (load("res://parts/Sandwich.tscn") as PackedScene).instantiate() as Sandwich
	holder.add_child(sandwich)

	var placer := _spawn_placer(holder, Vector3(0, 0.052, 0))
	var celda := _spawn_celda(holder, Vector3(0, 0.018, 0))
	var tira_bottom_1 := _spawn_tira(holder, Vector3(0, 0.001, -0.02), Vector3(0.156, 0.001, -0.02))
	var tira_bottom_2 := _spawn_tira(holder, Vector3(0, 0.001, 0.02), Vector3(0.156, 0.001, 0.02))
	var tira_top_1 := _spawn_tira(holder, Vector3(0, 0.020, -0.02), Vector3(0.156, 0.020, -0.02))
	var tira_top_2 := _spawn_tira(holder, Vector3(0, 0.020, 0.02), Vector3(0.156, 0.020, 0.02))

	await physics_frame
	await physics_frame

	var parts := {
		"placer": placer,
		"celda": celda,
		"tira_bottom": [tira_bottom_1, tira_bottom_2],
		"tira_top": [tira_top_1, tira_top_2],
	}
	var ok := sandwich.assemble(parts)
	_check(ok, "assemble returned true")
	_check(sandwich.assembled, "Sandwich.assembled flag set")
	var sled := sandwich.get_sled()
	_check(sled != null, "sled exists")
	if sled == null:
		holder.free()
		await physics_frame
		return
	_check(sled.mass > 0.05, "sled mass aggregated: %.4f" % sled.mass)
	_check(placer.get_parent() == sled, "placer reparented under sled")
	_check(celda.get_parent() == sled, "celda reparented under sled")
	_check(tira_bottom_1.get_parent() == sled and tira_bottom_2.get_parent() == sled, "bottom tiras reparented under sled")
	_check(tira_top_1.get_parent() == sled and tira_top_2.get_parent() == sled, "top tiras reparented under sled")
	_check(sandwich.get_part("tira_bottom") is Array and (sandwich.get_part("tira_bottom") as Array).size() == 2, "tira_bottom is an array of 2")
	_check(sandwich.get_part("tira_top") is Array and (sandwich.get_part("tira_top") as Array).size() == 2, "tira_top is an array of 2")
	var pbody := placer.get_node_or_null("RigidBody3D") as RigidBody3D
	_check(pbody != null and pbody.freeze, "placer body frozen in composite")
	_check(pbody != null and pbody.collision_layer == 0, "placer collision disabled in composite")

	var sled_x0 := sled.global_position.x
	var rel_p := placer.global_position.x - sled_x0
	var rel_c := celda.global_position.x - sled_x0
	var rel_t := tira_bottom_1.global_position.x - sled_x0

	# Unfreeze the sled so the moving belt drags it via friction.
	sled.freeze = false

	var t := 0.0
	while t < 2.5:
		await physics_frame
		t += 0.01666

	var dx := sled.global_position.x - sled_x0
	_check(dx > 0.3, "sled advanced on belt: %.3f m" % dx)
	_check(absf(placer.global_position.x - sled.global_position.x - rel_p) < 0.01, "placer rode sled (rel x preserved)")
	_check(absf(celda.global_position.x - sled.global_position.x - rel_c) < 0.01, "celda rode sled")
	_check(absf(tira_bottom_1.global_position.x - sled.global_position.x - rel_t) < 0.01, "tira_bottom rode sled")

	var freed := sandwich.detach_placer()
	_check(freed != null, "detach_placer returned node")
	_check(freed != null and freed.get_parent() == holder, "placer reparented back to holder after detach")
	var pbody2 := (freed.get_node_or_null("RigidBody3D") if freed else null) as RigidBody3D
	_check(pbody2 != null and pbody2.collision_layer == 10, "placer collision restored after detach")

	holder.queue_free()
	await physics_frame


func _test_station() -> void:
	var holder := Node3D.new()
	holder.name = "StationHolder"
	root.add_child(holder)

	_make_belt(holder, 0.0)

	var station := (load("res://parts/SandwichStation.tscn") as PackedScene).instantiate() as Node3D
	station.position = Vector3(0, 0.3, 0)
	holder.add_child(station)

	# Full stack on the belt, inside the DetectArea zone (box 0.6^3 centered at station).
	_spawn_placer(holder, Vector3(0, 0.08, 0))
	_spawn_celda(holder, Vector3(0, 0.02, 0))
	_spawn_tira(holder, Vector3(0, 0.001, -0.02), Vector3(0.156, 0.001, -0.02))
	_spawn_tira(holder, Vector3(0, 0.001, 0.02), Vector3(0.156, 0.001, 0.02))
	_spawn_tira(holder, Vector3(0, 0.035, -0.02), Vector3(0.156, 0.035, -0.02))
	_spawn_tira(holder, Vector3(0, 0.035, 0.02), Vector3(0.156, 0.035, 0.02))

	await physics_frame
	await physics_frame

	var found: Sandwich = null
	var t := 0.0
	while t < 3.0:
		var sand := holder.find_children("*", "Sandwich", true, false)
		if sand.size() > 0:
			found = sand[0] as Sandwich
			break
		await physics_frame
		t += 0.01666

	_check(found != null, "SandwichStation auto-detected and assembled a sandwich")
	if found:
		_check(found.assembled, "station-created Sandwich is assembled")
		_check(found.has_part("tira_bottom"), "assembled sandwich has bottom tira")
		_check(found.has_part("tira_top"), "assembled sandwich has top tira")
		_check(found.has_part("celda"), "assembled sandwich has celda")
		_check((found.get_part("tira_bottom") as Array).size() == 2, "assembled sandwich has 2 bottom tiras")
		_check((found.get_part("tira_top") as Array).size() == 2, "assembled sandwich has 2 top tiras")

	holder.free()
	await physics_frame


func _test_first_stack() -> void:
	# The first sandwich of the line arrives without bottom tiras: 2 top tiras +
	# celda + placer. The station must assemble it (bottom optional) and the sled
	# must rest on the belt (not hover).
	var holder := Node3D.new()
	holder.name = "FirstStackHolder"
	root.add_child(holder)
	_make_belt(holder, 0.0)
	var station := (load("res://parts/SandwichStation.tscn") as PackedScene).instantiate() as Node3D
	station.position = Vector3(0, 0.3, 0)
	holder.add_child(station)

	_spawn_placer(holder, Vector3(0, 0.08, 0))
	_spawn_celda(holder, Vector3(0, 0.02, 0))
	_spawn_tira(holder, Vector3(0, 0.035, -0.02), Vector3(0.156, 0.035, -0.02))
	_spawn_tira(holder, Vector3(0, 0.035, 0.02), Vector3(0.156, 0.035, 0.02))

	await physics_frame
	await physics_frame

	var found: Sandwich = null
	var t := 0.0
	while t < 3.0:
		var sand := holder.find_children("*", "Sandwich", true, false)
		if sand.size() > 0:
			found = sand[0] as Sandwich
			break
		await physics_frame
		t += 0.01666

	_check(found != null, "first stack (0 bottom tiras) assembled")
	if found:
		var b = found.get_part("tira_bottom")
		var top = found.get_part("tira_top")
		_check(b is Array and (b as Array).size() == 0, "first stack has 0 bottom tiras")
		_check(top is Array and (top as Array).size() == 2, "first stack has 2 top tiras")
		var sled := found.get_sled()
		if sled:
			_check(sled.global_position.y < 0.05, "first-stack sled rests on belt: y=%.3f" % sled.global_position.y)

	holder.free()
	await physics_frame


func _test_incomplete() -> void:
	# A stack with a single tira (no top pair) must NOT be assembled.
	var holder := Node3D.new()
	holder.name = "IncompleteHolder"
	root.add_child(holder)
	_make_belt(holder, 0.0)
	var station := (load("res://parts/SandwichStation.tscn") as PackedScene).instantiate() as Node3D
	station.position = Vector3(0, 0.3, 0)
	holder.add_child(station)

	_spawn_placer(holder, Vector3(0, 0.08, 0))
	_spawn_celda(holder, Vector3(0, 0.02, 0))
	_spawn_tira(holder, Vector3(0, 0.001, 0), Vector3(0.156, 0.001, 0))

	await physics_frame
	await physics_frame

	var found := false
	var t := 0.0
	while t < 2.0:
		if holder.find_children("*", "Sandwich", true, false).size() > 0:
			found = true
			break
		await physics_frame
		t += 0.01666

	_check(not found, "incomplete stack (1 tira) NOT assembled")
	holder.free()
	await physics_frame
