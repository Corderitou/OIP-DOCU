extends SceneTree

var _scene: Node3D
var _elapsed: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://parts/TestRobotGrid.tscn")
	if packed == null:
		print("FAIL: could not load TestRobotGrid.tscn")
		quit(1)
		return
	_scene = packed.instantiate()
	_scene.set("auto_run", true)
	root.add_child(_scene)
	print("=== Running TestRobotGrid end-to-end ===")


func _process(delta: float) -> bool:
	if _scene == null:
		return false
	_elapsed += delta
	if str(_scene.get("_phase")) == "done":
		print("=== TestRobotGrid finished ===")
		quit(0)
	elif _elapsed > 180.0:
		print("FAIL: TestRobotGrid timeout after 180s")
		quit(1)
	return false
