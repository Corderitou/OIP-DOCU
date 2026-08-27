class_name SimulationController
extends Node3D

## Saved physics state per node (instance_id -> {transform, linear_velocity, angular_velocity, velocity})
var _saved_states: Dictionary = {}
## Nodes spawned DURING simulation (by BoxSpawner, PalletSpawner, etc.) — deleted on stop.
var _spawned_nodes: Array[Node3D] = []

var scene_root: Node3D = null


func _ready() -> void:
	pass


func start_simulation() -> void:
	if RuntimeSimulationBus.is_simulation_running():
		return

	# Snapshot current editor state (positions + zero velocities).
	_save_all_states()
	_spawned_nodes.clear()
	RuntimeSimulationBus.start_simulation()


func stop_simulation() -> void:
	if not RuntimeSimulationBus.is_simulation_running():
		return

	# Just tell the bus to stop. The actual restore happens deferred after
	# the pause_toggled signal has frozen all rigid bodies.
	RuntimeSimulationBus.stop_simulation()
	call_deferred("_deferred_restore_and_cleanup")


func _deferred_restore_and_cleanup() -> void:
	_restore_all_states_physics_safe()
	_cleanup_spawned()


func toggle_simulation() -> void:
	if RuntimeSimulationBus.is_simulation_running():
		stop_simulation()
	else:
		start_simulation()


func pause_simulation() -> void:
	if not RuntimeSimulationBus.is_simulation_running() or RuntimeSimulationBus.is_simulation_paused():
		return
	RuntimeSimulationBus.pause_simulation()


func resume_simulation() -> void:
	if not RuntimeSimulationBus.is_simulation_running() or not RuntimeSimulationBus.is_simulation_paused():
		return
	RuntimeSimulationBus.resume_simulation()


## Call from editor after any undo/redo or manual transform change.
func refresh_initial_state() -> void:
	if not RuntimeSimulationBus.is_simulation_running():
		_save_all_states()


func _save_all_states() -> void:
	_saved_states.clear()
	if not scene_root:
		return
	_save_node_states(scene_root)


func _save_node_states(node: Node) -> void:
	if node is Node3D:
		var nd := node as Node3D
		var state: Dictionary = {
			"transform": nd.global_transform,
		}
		# Save current velocities (usually zero in editor, but capture anyway).
		if nd is RigidBody3D:
			var rb: RigidBody3D = nd
			state["linear_velocity"] = rb.linear_velocity
			state["angular_velocity"] = rb.angular_velocity
		elif nd is CharacterBody3D:
			var cb: CharacterBody3D = nd
			state["velocity"] = cb.velocity
		_saved_states[node.get_instance_id()] = state

	for child in node.get_children():
		_save_node_states(child)


## Restore using PhysicsServer so RigidBody3D positions "stick" immediately.
func _restore_all_states_physics_safe() -> void:
	if not scene_root:
		return
	_restore_node_states_physics_safe(scene_root)


func _restore_node_states_physics_safe(node: Node) -> void:
	if node is Node3D:
		var id := node.get_instance_id()
		if _saved_states.has(id):
			var state: Dictionary = _saved_states[id]
			var nd: Node3D = node as Node3D

			# 1) Teleport the physics body directly via PhysicsServer3D (bypasses
			#    one-frame physics correction that fights transform assignment).
			if nd is RigidBody3D:
				var rb: RigidBody3D = nd
				var rid := rb.get_rid()
				if PhysicsServer3D.body_get_mode(rid) == PhysicsServer3D.BODY_MODE_RIGID:
					PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, state["transform"])
					PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, state.get("linear_velocity", Vector3.ZERO))
					PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, state.get("angular_velocity", Vector3.ZERO))
				else:
					# Kinematic/Static — simple transform is fine.
					nd.global_transform = state["transform"]
			elif nd is CharacterBody3D:
				var cb: CharacterBody3D = nd
				cb.global_transform = state["transform"]
				cb.velocity = state.get("velocity", Vector3.ZERO)
			else:
				nd.global_transform = state["transform"]

	for child in node.get_children():
		_restore_node_states_physics_safe(child)


func _cleanup_spawned() -> void:
	for node in _spawned_nodes:
		if is_instance_valid(node) and node.is_inside_tree():
			node.queue_free()
	_spawned_nodes.clear()


## Called by spawners when they instantiate a product at runtime.
func register_spawned_node(node: Node3D) -> void:
	_spawned_nodes.append(node)
