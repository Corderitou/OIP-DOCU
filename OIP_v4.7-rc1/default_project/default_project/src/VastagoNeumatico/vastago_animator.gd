@tool
class_name VastagoNeumaticoAnimator
extends Node3D

const RADIAL: int = 24

## Push plate thickness factor relative to cylinder diameter.
const PLATE_THICKNESS_FACTOR: float = 0.25
## Push plate width/height factor relative to cylinder diameter.
const PLATE_FACE_FACTOR: float = 1.6
## Mount plate thickness factor relative to cylinder diameter.
const MOUNT_THICKNESS_FACTOR: float = 0.22
## Mount plate width factor relative to cylinder diameter.
const MOUNT_WIDTH_FACTOR: float = 2.4

var _cylinder_length: float = 0.6
var _cylinder_diameter: float = 0.1
var _rod_diameter: float = 0.02
var _stroke_length: float = 0.4

var _progress: float = 0.0
var _target: float = 0.0
var _time: float = 0.5

var _barrel: MeshInstance3D
var _cap_rear: MeshInstance3D
var _cap_front: MeshInstance3D
var _mount: MeshInstance3D
var _rod: MeshInstance3D
var _piston: MeshInstance3D
var _plate: MeshInstance3D

var _barrel_material: StandardMaterial3D
var _cap_material: StandardMaterial3D
var _mount_material: StandardMaterial3D
var _rod_material: StandardMaterial3D
var _plate_material: StandardMaterial3D

var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _part_end: RigidBody3D

var _rod_base_z: float = 0.0
var _piston_z: float = 0.0
var _plate_z: float = 0.0


func set_measurements(cylinder_length: float, cylinder_diameter: float, rod_diameter: float, stroke_length: float) -> void:
	_cylinder_length = maxf(cylinder_length, 0.05)
	_cylinder_diameter = maxf(cylinder_diameter, 0.02)
	_rod_diameter = clampf(rod_diameter, 0.004, _cylinder_diameter * 0.5)
	_stroke_length = maxf(stroke_length, 0.0)
	if is_inside_tree():
		_rebuild()


func set_target(extended: bool, time: float) -> void:
	_target = 1.0 if extended else 0.0
	_time = maxf(time, 0.01)


func reset() -> void:
	_progress = 0.0
	_target = 0.0
	_apply_progress()


func _ready() -> void:
	_rebuild()


func _physics_process(delta: float) -> void:
	if _progress == _target:
		return
	var step := delta / maxf(_time, 0.01)
	if _progress < _target:
		_progress = minf(_target, _progress + step)
	else:
		_progress = maxf(_target, _progress - step)
	_apply_progress()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_create_nodes_if_needed()
	_build_geometry()
	_apply_progress()


func _create_nodes_if_needed() -> void:
	if _barrel:
		return

	_barrel = MeshInstance3D.new()
	_barrel.rotation = Vector3(PI / 2.0, 0, 0)
	add_child(_barrel)

	_cap_rear = MeshInstance3D.new()
	_cap_rear.rotation = Vector3(PI / 2.0, 0, 0)
	add_child(_cap_rear)

	_cap_front = MeshInstance3D.new()
	_cap_front.rotation = Vector3(PI / 2.0, 0, 0)
	add_child(_cap_front)

	_rod = MeshInstance3D.new()
	_rod.rotation = Vector3(PI / 2.0, 0, 0)
	add_child(_rod)

	_piston = MeshInstance3D.new()
	_piston.rotation = Vector3(PI / 2.0, 0, 0)
	add_child(_piston)

	_mount = MeshInstance3D.new()
	add_child(_mount)

	_static_body = StaticBody3D.new()
	_static_body.collision_layer = 3
	_static_body.collision_mask = 0
	add_child(_static_body)
	_collision_shape = CollisionShape3D.new()
	_static_body.add_child(_collision_shape)

	_part_end = RigidBody3D.new()
	_part_end.collision_layer = 2
	_part_end.collision_mask = 8
	_part_end.freeze = true
	_part_end.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_part_end.lock_rotation = true
	_part_end.mass = 10.0
	_part_end.continuous_cd = true
	add_child(_part_end)
	_plate = MeshInstance3D.new()
	_part_end.add_child(_plate)


func _build_geometry() -> void:
	var d := _cylinder_diameter
	var l := _cylinder_length
	var stroke := _stroke_length

	_make_materials()

	var cap_radius := d * 0.55
	var cap_height := d * 0.22
	_barrel.mesh = _cylinder(d * 0.5, d * 0.5, l)
	_barrel.material_override = _barrel_material
	_cap_rear.mesh = _cylinder(cap_radius, cap_radius, cap_height)
	_cap_rear.material_override = _cap_material
	_cap_rear.position = Vector3(0, 0, -l * 0.5)
	_cap_front.mesh = _cylinder(cap_radius, cap_radius, cap_height)
	_cap_front.material_override = _cap_material
	_cap_front.position = Vector3(0, 0, l * 0.5)

	# Rod is hidden inside the barrel when retracted; the exposed length is the stroke.
	var rod_length := stroke + d * 0.7
	_rod.mesh = _cylinder(_rod_diameter * 0.5, _rod_diameter * 0.5, rod_length)
	_rod.material_override = _rod_material

	var piston_diameter := d * 0.8
	_piston.mesh = _cylinder(piston_diameter * 0.5, piston_diameter * 0.5, d * 0.18)
	_piston.material_override = _cap_material

	var mount_height := d * MOUNT_THICKNESS_FACTOR
	var mount_depth := l + stroke * 0.6
	var mount_mesh := BoxMesh.new()
	mount_mesh.size = Vector3(d * MOUNT_WIDTH_FACTOR, mount_height, mount_depth)
	_mount.mesh = mount_mesh
	_mount.material_override = _mount_material
	_mount.position = Vector3(0, -d * 0.5 - mount_height * 0.5, 0)

	# Static collision box covers the barrel + caps.
	var static_box := BoxShape3D.new()
	static_box.size = Vector3(d * 1.2, d * 1.2, l)
	_collision_shape.shape = static_box

	# Push plate at the rod tip; its collision pushes cargo (layer 4, mask 8).
	var plate_w := d * PLATE_FACE_FACTOR
	var plate_h := d * PLATE_FACE_FACTOR
	var plate_d := d * PLATE_THICKNESS_FACTOR
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(plate_w, plate_h, plate_d)
	_plate.mesh = plate_mesh
	_plate.material_override = _plate_material

	var plate_box := BoxShape3D.new()
	plate_box.size = Vector3(plate_w, plate_h, plate_d)
	if _part_end.get_node_or_null("CollisionShape3D"):
		_part_end.get_node("CollisionShape3D").queue_free()
	var plate_collision := CollisionShape3D.new()
	plate_collision.name = "CollisionShape3D"
	plate_collision.shape = plate_box
	_part_end.add_child(plate_collision)

	# Home positions along Z (cylinder axis): rod tip flush with front cap,
	# piston rides the rod's rear end inside the barrel, plate at the tip.
	_rod_base_z = l * 0.5 - rod_length * 0.5
	_piston_z = _rod_base_z - rod_length * 0.5 + d * 0.09
	_plate_z = l * 0.5 + d * 0.15


func _apply_progress() -> void:
	var home := is_zero_approx(_progress)
	_part_end.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC if home else RigidBody3D.FREEZE_MODE_KINEMATIC
	var offset_z := _stroke_length * _progress
	_rod.position = Vector3(0, 0, _rod_base_z + offset_z)
	_piston.position = Vector3(0, 0, _piston_z + offset_z)
	_part_end.position = Vector3(0, 0, _plate_z + offset_z)


func _make_materials() -> void:
	if _barrel_material:
		return
	_barrel_material = StandardMaterial3D.new()
	_barrel_material.albedo_color = Color8(120, 130, 140)
	_barrel_material.metallic = 0.7
	_barrel_material.roughness = 0.35

	_cap_material = StandardMaterial3D.new()
	_cap_material.albedo_color = Color8(60, 66, 74)
	_cap_material.metallic = 0.6
	_cap_material.roughness = 0.4

	_mount_material = StandardMaterial3D.new()
	_mount_material.albedo_color = Color8(45, 48, 52)
	_mount_material.metallic = 0.4
	_mount_material.roughness = 0.5

	_rod_material = StandardMaterial3D.new()
	_rod_material.albedo_color = Color8(200, 205, 210)
	_rod_material.metallic = 1.0
	_rod_material.roughness = 0.2

	_plate_material = StandardMaterial3D.new()
	_plate_material.albedo_color = Color8(220, 160, 30)
	_plate_material.metallic = 0.0
	_plate_material.roughness = 0.5


func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = RADIAL
	mesh.rings = 1
	return mesh
