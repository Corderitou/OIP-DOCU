extends SceneTree

var failures := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS | " + label)
	else:
		print("FAIL | " + label)
		failures += 1


func _init() -> void:
	var script := load("res://src/PlacerSpawner/placer_spawner.gd") as Script
	_check(script != null, "parse script placer_spawner.gd")
	if script:
		_check(script.can_instantiate(), "can_instantiate placer_spawner.gd")
		_check(script.get_global_name() == "PlacerSpawner", "class_name PlacerSpawner")

	var packed := load("res://parts/PlacerSpawner.tscn") as PackedScene
	_check(packed != null, "load scene PlacerSpawner.tscn")
	if packed:
		var inst := packed.instantiate()
		_check(inst != null, "instantiate PlacerSpawner.tscn")
		if inst:
			var spawner := inst as PlacerSpawner
			_check(spawner != null, "root es PlacerSpawner")
			if spawner:
				_check(spawner.scene != null, "scene asignada (Placer.tscn)")
				_check(spawner.station_prefix == "S1", "station_prefix S1")
			inst.free()

	var placer := load("res://parts/Placer.tscn") as PackedScene
	_check(placer != null, "load scene Placer.tscn")
	var placer_inst := placer.instantiate() as Node3D
	_check(placer_inst != null, "instantiate Placer.tscn")
	if placer_inst:
		_check(placer_inst is Placer, "Placer.tscn deriva de Placer")
		placer_inst.free()

	print(failures == 0 and "ALL_OK" or "HAS_FAILURES")
	quit(0 if failures == 0 else 1)
