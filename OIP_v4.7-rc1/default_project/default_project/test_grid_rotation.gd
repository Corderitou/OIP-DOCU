extends SceneTree

const SCENE_PATH := "res://parts/TestRobotGrid.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== WovenBatch ROTATION VERIFICATION ===")
	print("Target: Euler (0, 90, 0) at every deposit point")
	print("")

	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Cannot load scene"); quit(1); return

	var scene: Node3D = packed.instantiate()
	root.add_child(scene)

	var robot: Node3D = scene.get_node("Robot") as Node3D
	var vac: Node3D = robot._vacuum_area as Node3D

	robot.robot_scale = 0.7
	robot.show_gizmos = false

	# Read pickup waypoint (Point1)
	var wp_keys: Array = robot.waypoints.keys()
	wp_keys.sort_custom(func(a: String, b: String) -> bool:
		return int(a.get_slice(": ", 0)) < int(b.get_slice(": ", 0)))

	var pickup_angles: Array = robot.waypoints[wp_keys[0]]
	print("Pickup: %s = %s" % [wp_keys[0], str(pickup_angles)])
	print("")

	# Get cup basis at pickup
	robot.set_joint_angles(pickup_angles)
	var pickup_cup_basis: Basis = vac.global_transform.basis.orthonormalized()
	print("Cup basis at pickup:")
	print("  X=(%.6f, %.6f, %.6f)" % [pickup_cup_basis.x.x, pickup_cup_basis.x.y, pickup_cup_basis.x.z])
	print("  Y=(%.6f, %.6f, %.6f)" % [pickup_cup_basis.y.x, pickup_cup_basis.y.y, pickup_cup_basis.y.z])
	print("  Z=(%.6f, %.6f, %.6f)" % [pickup_cup_basis.z.x, pickup_cup_basis.z.y, pickup_cup_basis.z.z])
	var pickup_euler := pickup_cup_basis.get_euler()
	print("  Euler (deg): X=%.4f Y=%.4f Z=%.4f" % [
		rad_to_deg(pickup_euler.x),
		rad_to_deg(pickup_euler.y),
		rad_to_deg(pickup_euler.z)])
	print("")

	# For each grid waypoint (cmd4-11), compute deposited WovenBatch rotation
	print("=== GRID DEPOSIT ROTATION CHECK ===")
	print("")

	for i in range(1, wp_keys.size()):
		var wp_name: String = wp_keys[i]
		var angles: Array = robot.waypoints[wp_name]
		robot.set_joint_angles(angles)

		var deposit_cup_basis: Basis = vac.global_transform.basis.orthonormalized()
		var tip: Vector3 = robot.get_tool_tip_position()

		# WovenBatch final = deposit_cup * pickup_cup⁻¹ * obj_basis_at_pickup
		# obj_basis = Identity (WovenBatch starts with no rotation)
		var final_basis: Basis = deposit_cup_basis * pickup_cup_basis.inverse()
		var final_euler_rad: Vector3 = final_basis.get_euler()
		var final_euler := Vector3(rad_to_deg(final_euler_rad.x), rad_to_deg(final_euler_rad.y), rad_to_deg(final_euler_rad.z))

		# Check each axis deviation from target (0, 90, 0)
		var x_err: float = absf(final_euler.x - 0.0)
		var y_err: float = absf(final_euler.y - 90.0)
		var z_err: float = absf(final_euler.z - 0.0)
		var status: String = "OK" if (x_err < 2.0 and y_err < 2.0 and z_err < 2.0) else "BAD"

		print("--- %s (%s) ---" % [wp_name, status])
		print("  tip=(%.3f, %.3f, %.3f)" % [tip.x, tip.y, tip.z])
		print("  deposit cup X=(%.4f, %.4f, %.4f)" % [deposit_cup_basis.x.x, deposit_cup_basis.x.y, deposit_cup_basis.x.z])
		print("  deposit cup Y=(%.4f, %.4f, %.4f)" % [deposit_cup_basis.y.x, deposit_cup_basis.y.y, deposit_cup_basis.y.z])
		print("  deposit cup Z=(%.4f, %.4f, %.4f)" % [deposit_cup_basis.z.x, deposit_cup_basis.z.y, deposit_cup_basis.z.z])
		print("  WovenBatch final X=(%.4f, %.4f, %.4f)" % [final_basis.x.x, final_basis.x.y, final_basis.x.z])
		print("  WovenBatch final Y=(%.4f, %.4f, %.4f)" % [final_basis.y.x, final_basis.y.y, final_basis.y.z])
		print("  WovenBatch final Z=(%.4f, %.4f, %.4f)" % [final_basis.z.x, final_basis.z.y, final_basis.z.z])
		print("  WovenBatch Euler: X=%.2f° Y=%.2f° Z=%.2f°" % [final_euler.x, final_euler.y, final_euler.z])
		print("  Error vs (0,90,0): dX=%.2f° dY=%.2f° dZ=%.2f°" % [x_err, y_err, z_err])
		print("")

	print("=== DONE ===")
	quit(0)
