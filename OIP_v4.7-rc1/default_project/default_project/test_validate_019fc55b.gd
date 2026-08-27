extends SceneTree

var failures := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS | " + label)
	else:
		print("FAIL | " + label)
		failures += 1


func _init() -> void:
	var scripts := [
		"res://src/Stringer/stringer.gd",
		"res://src/Tira/tira.gd",
		"res://src/Dispenser/dispenser.gd",
	]
	for s in scripts:
		var res := load(s) as Script
		_check(res != null, "parse script " + s)
		if res:
			_check(res.can_instantiate(), "can_instantiate " + s)

	var scenes := [
		"res://src/Stringer/Stringer.tscn",
		"res://src/Dispenser/Dispenser.tscn",
		"res://src/Tira/Tira.tscn",
		"res://parts/Maquina1.tscn",
	]
	for sc in scenes:
		var packed := load(sc) as PackedScene
		_check(packed != null, "load scene " + sc)
		if packed:
			var inst := packed.instantiate()
			_check(inst != null, "instantiate " + sc)
			inst.free()

	var tira := (load("res://src/Tira/Tira.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(tira)
	var start := Vector3.ZERO
	var end := Vector3(0.4, 0.0, 0.0)
	var lateral := Tira.lateral_axis(start, end)
	_check(lateral.is_equal_approx(Vector3(0.0, 0.0, 1.0)) or lateral.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "lateral_axis horizontal for X-run chain: " + str(lateral))
	var lateral_vert := Tira.lateral_axis(Vector3.ZERO, Vector3(0.0, 0.4, 0.0))
	_check(absf(lateral_vert.y) < 0.01, "lateral_axis stays horizontal for vertical chain: " + str(lateral_vert))
	var tira_script := tira as Tira
	tira_script.build_chain(start, end, lateral * 0.01)
	_check(tira_script.has_chain(), "build_chain produced chain")
	var segs := tira_script._segments
	_check(segs.size() >= 20, "segment count for 0.4m: " + str(segs.size()))
	if segs.size() > 0:
		var last := segs[segs.size() - 1]
		var pin_pos := tira_script._head_joint.global_position
		_check(pin_pos.distance_to(end + lateral * 0.01) < 0.005, "PinHead at end+offset: " + str(pin_pos))
		var gap := absf(segs.size() * 0.02 - 0.4)
		_check(gap < 0.01, "total material length ~= span (no overstretch): " + str(gap))
	tira_script.place_chain(start, end * 0.5, lateral * 0.01)
	_check(tira_script.has_chain(), "place_chain kept chain after retract")
	tira_script.clear_chain()
	_check(tira_script._segments.is_empty() and tira_script.get_child_count() == 0, "clear_chain freed all children")
	tira.free()

	var st := (load("res://src/Stringer/Stringer.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(st)
	var st_script: Resource = st.get_script()
	_check(st_script != null, "stringer script attached")

	print(failures == 0 and "ALL_OK" or "HAS_FAILURES")
	quit(0 if failures == 0 else 1)
