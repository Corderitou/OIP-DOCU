extends SceneTree

## Validates TiraBundleExample: after Simulation.stopped the bundle AND its 2
## tira children persist (unlike the normal TiraBundle which removes itself).
## Reproduces the real case: a bundle copied from the Dispenser into a scene
## with 2 Tira children, script changed to tira_bundle_example.gd.

var _failures := 0


func _check(ok: bool, label: String) -> void:
	print(("PASS | " if ok else "FAIL | ") + label)
	if not ok:
		_failures += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST TIRABUNDLE EXAMPLE START ===")
	# Simula el caso real: un TiraBundleExample con 2 Tira hijas (como el bundle
	# que el usuario copio del Dispenser en Simulation.tscn y le cambio el script).
	var bundle := TiraBundleExample.new()
	var tira_scene: PackedScene = load("res://parts/Tira.tscn")
	for i in 2:
		var t := tira_scene.instantiate() as Node3D
		bundle.add_child(t)
		bundle.add_tira(t as Tira)
		t.position = Vector3(0.0, 0.0, 0.03 if i == 0 else -0.03)
	root.add_child(bundle)
	await process_frame

	_check(bundle.get_script() != null and bundle.get_script().resource_path.begins_with("res://src/Tira/tira_bundle_example"),
			"script es tira_bundle_example.gd")
	var tiras := bundle.find_children("*", "Tira", true, false)
	_check(tiras.size() == 2, "bundle tiene 2 tiras hijas (%d)" % tiras.size())
	if tiras.size() == 2:
		_check(not (tiras[0] as Tira).remove_on_stop, "tira hija remove_on_stop=false tras _ready")

	var s: Object = Engine.get_singleton("Simulation")
	s.emit_signal("started")
	await process_frame
	s.emit_signal("stopped")
	await process_frame

	_check(is_instance_valid(bundle), "TiraBundleExample persiste tras stop")
	var alive := 0
	for t in bundle.find_children("*", "Tira", true, false):
		if is_instance_valid(t):
			alive += 1
	_check(alive == 2, "2 tiras hijas persisten tras stop (alive=%d)" % alive)

	bundle.queue_free()
	print("=== TEST TIRABUNDLE EXAMPLE END ===")
	quit(0 if _failures == 0 else 1)
