extends SceneTree

## Headless validation of TiraBundle: the Dispenser releases 2 parallel tiras that
## must end up grouped under a single TiraBundle parent AND physically joined by
## cross-joints, so homologous segments keep the tira_spacing separation (the pair
## does not separate) after cut+release with physics running.

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
	print("=== TEST TIRA BUNDLE START ===")
	var packed := load("res://parts/Maquina1.tscn") as PackedScene
	_check(packed != null, "load parts/Maquina1.tscn")
	if packed == null:
		quit(1)
		return
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	await process_frame

	var stringer := inst.get_node_or_null("Stringer") as Stringer
	var dispenser := inst.get_node_or_null("Dispenser") as Dispenser
	_check(stringer != null, "Stringer child found")
	_check(dispenser != null, "Dispenser child found")
	if stringer == null or dispenser == null:
		inst.free()
		quit(1)
		return

	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	await process_frame

	var grabbed := stringer.grab(dispenser)
	_check(grabbed, "Stringer.grab() true (2 tiras spawned)")

	var bundles: Array = dispenser.find_children("*", "TiraBundle", true, false)
	_check(bundles.size() == 1, "Dispenser tiene 1 TiraBundle tras spawn")
	if bundles.size() != 1:
		inst.free()
		quit(1)
		return
	var bundle := bundles[0] as TiraBundle
	var tiras := bundle.get_tiras()
	_check(tiras.size() == 2, "bundle agrupa 2 tiras (got %d)" % tiras.size())
	_check(tiras[0].get_parent() == bundle and tiras[1].get_parent() == bundle,
			"ambas tiras son hijas del bundle (un solo objeto)")
	_check(dispenser.is_ancestor_of(bundle), "bundle dentro del subarbol del dispenser antes del cut")

	stringer.release()
	dispenser.cut()
	await process_frame

	_check(bundle.get_parent() == root or bundle.get_parent().get_parent() == root,
			"bundle reparenteado fuera del dispenser tras cut")

	var bound := false
	var t := 0.0
	while t < 3.0 and not bound:
		bound = bundle.is_bound()
		await physics_frame
		t += 0.01666
	_check(bound, "bundle bind() activo tras cut+release (t=%.1f)" % t)

	var cross_count := 0
	for child in bundle.get_children():
		if child is Generic6DOFJoint3D:
			cross_count += 1
	_check(cross_count >= 4, "cross-joints creados entre cadenas (%d)" % cross_count)

	var a := tiras[0]
	var b := tiras[1]
	var n := mini(a.get_segment_count(), b.get_segment_count())
	var step := maxi(1, ceili(n / 4.0))
	var separation_ok := true
	var first_dist: float = -1.0
	for i in range(0, n, step):
		if a.get_segment(i) == null or b.get_segment(i) == null:
			continue
		if not is_instance_valid(a.get_segment(i)) or not is_instance_valid(b.get_segment(i)):
			continue
		var d := a.get_segment(i).global_position.distance_to(b.get_segment(i).global_position)
		if first_dist < 0.0:
			first_dist = d
		if d > 0.1 or d < 0.02:
			separation_ok = false
	_check(separation_ok, "segmentos homologos mantienen separacion (spacing 0.06, d=%.3f)" % first_dist)

	var finite := true
	for i in n:
		var pa := a.get_segment(i).global_position
		var pb := b.get_segment(i).global_position
		if not pa.is_finite() or not pb.is_finite():
			finite = false
	_check(finite, "sin NaN en posiciones de segmentos")

	s.emit_signal("stopped")
	await process_frame
	_check(not is_instance_valid(bundle), "bundle eliminado al parar (remove_on_stop)")

	inst.free()
	print("=== TEST TIRA BUNDLE END ===")
	quit(0 if _failures == 0 else 1)
