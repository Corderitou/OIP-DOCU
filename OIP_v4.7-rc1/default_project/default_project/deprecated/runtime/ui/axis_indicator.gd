class_name AxisIndicator
extends Node3D

const ARROW_LENGTH := 1.2
const SHAFT_RADIUS := 0.018
const TIP_RADIUS := 0.05
const TIP_HEIGHT := 0.14
const RING_RADIUS := 0.8

var _axis_nodes: Dictionary = {}
var _rotation_ring: MeshInstance3D = null
var _track_node: Node3D = null


func _ready() -> void:
	_build_arrows()
	_build_rotation_ring()
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	# Follow tracked node
	if _track_node and is_instance_valid(_track_node):
		global_position = _track_node.global_position
	for key in _axis_nodes:
		var label: Label3D = _axis_nodes[key].get_node_or_null("Label")
		if label:
			var cam := get_viewport().get_camera_3d()
			if cam:
				label.global_transform = cam.global_transform
				label.global_position = _axis_nodes[key].global_position
	if _rotation_ring and _rotation_ring.visible:
		var label: Label3D = _rotation_ring.get_node_or_null("Label")
		if label:
			var cam := get_viewport().get_camera_3d()
			if cam:
				label.global_transform = cam.global_transform
				label.global_position = _rotation_ring.global_position + Vector3(0, 0.2, 0)


func _build_arrows() -> void:
	_build_arrow("x", Color(1.0, 0.25, 0.25), "x")
	_build_arrow("y", Color(0.3, 1.0, 0.3), "y")
	_build_arrow("z", Color(0.3, 0.5, 1.0), "z")


func _build_arrow(axis_name: String, color: Color, _dir: String) -> void:
	var arrow := Node3D.new()
	arrow.name = axis_name.to_upper() + "Axis"
	add_child(arrow)

	# Shaft
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = SHAFT_RADIUS
	shaft_mesh.bottom_radius = SHAFT_RADIUS
	shaft_mesh.height = ARROW_LENGTH
	shaft.mesh = shaft_mesh
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = color
	shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft_mat.no_depth_test = true
	shaft_mat.render_priority = 10
	shaft.material_override = shaft_mat
	arrow.add_child(shaft)

	# Tip
	var tip := MeshInstance3D.new()
	var tip_mesh := PrismMesh.new()
	tip_mesh.size = Vector3(TIP_RADIUS * 2, TIP_HEIGHT, TIP_RADIUS * 2)
	tip.mesh = tip_mesh
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = color
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mat.no_depth_test = true
	tip_mat.render_priority = 10
	tip.material_override = tip_mat
	arrow.add_child(tip)

	# Label
	var label := Label3D.new()
	label.name = "Label"
	label.pixel_size = 0.005
	label.font_size = 14
	label.outline_size = 8
	label.modulate = color
	label.no_depth_test = true
	label.render_priority = 11
	arrow.add_child(label)

	match axis_name:
		"x":
			shaft.position = Vector3(ARROW_LENGTH / 2.0, 0, 0)
			shaft.rotation.z = -PI / 2.0
			tip.position = Vector3(ARROW_LENGTH + TIP_HEIGHT / 2.0, 0, 0)
			tip.rotation.z = -PI / 2.0
			label.position = Vector3(ARROW_LENGTH + TIP_HEIGHT + 0.12, 0, 0)
			label.text = "X"
		"y":
			shaft.position = Vector3(0, ARROW_LENGTH / 2.0, 0)
			tip.position = Vector3(0, ARROW_LENGTH + TIP_HEIGHT / 2.0, 0)
			label.position = Vector3(0, ARROW_LENGTH + TIP_HEIGHT + 0.12, 0)
			label.text = "Y"
		"z":
			shaft.position = Vector3(0, 0, ARROW_LENGTH / 2.0)
			shaft.rotation.x = PI / 2.0
			tip.position = Vector3(0, 0, ARROW_LENGTH + TIP_HEIGHT / 2.0)
			tip.rotation.x = PI / 2.0
			label.position = Vector3(0, 0, ARROW_LENGTH + TIP_HEIGHT + 0.12)
			label.text = "Z"

	_axis_nodes[axis_name] = arrow


func _build_rotation_ring() -> void:
	_rotation_ring = MeshInstance3D.new()
	_rotation_ring.name = "RotationRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = RING_RADIUS - 0.01
	ring_mesh.outer_radius = RING_RADIUS + 0.01
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 8
	_rotation_ring.mesh = ring_mesh
	_rotation_ring.rotation.x = PI / 2.0

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.7)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.no_depth_test = true
	ring_mat.render_priority = 10
	_rotation_ring.material_override = ring_mat
	add_child(_rotation_ring)

	# Rotation arrow indicator
	var arrow_tip := MeshInstance3D.new()
	arrow_tip.name = "ArrowTip"
	var arrow_mesh := PrismMesh.new()
	arrow_mesh.size = Vector3(0.06, 0.12, 0.06)
	arrow_tip.mesh = arrow_mesh
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 0.85, 0.2)
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.no_depth_test = true
	arrow_mat.render_priority = 10
	arrow_tip.material_override = arrow_mat
	arrow_tip.position = Vector3(RING_RADIUS, 0, 0)
	arrow_tip.rotation.z = -PI / 2.0
	_rotation_ring.add_child(arrow_tip)

	# Label
	var label := Label3D.new()
	label.name = "Label"
	label.pixel_size = 0.005
	label.font_size = 14
	label.outline_size = 8
	label.modulate = Color(1.0, 0.85, 0.2)
	label.no_depth_test = true
	label.render_priority = 11
	label.position = Vector3(0, 0.2, 0)
	label.text = "ROTATE"
	_rotation_ring.add_child(label)


func show_axis(axis_name: String) -> void:
	visible = true
	_rotation_ring.visible = false
	for key in _axis_nodes:
		_axis_nodes[key].visible = (key == axis_name)


func show_rotate(axis: String = "") -> void:
	visible = true
	_rotation_ring.visible = true
	# Update ring label to show axis
	var label: Label3D = _rotation_ring.get_node_or_null("Label")
	if label:
		label.text = "ROTATE" if axis == "" else "ROTATE " + axis.to_upper()
	# Update ring color based on axis
	var ring_mat: StandardMaterial3D = _rotation_ring.material_override
	if ring_mat:
		match axis:
			"x": ring_mat.albedo_color = Color(1.0, 0.35, 0.35, 0.7)
			"y": ring_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
			"z": ring_mat.albedo_color = Color(0.4, 0.55, 1.0, 0.7)
			_: ring_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.7)
	# Show axis arrow if locked
	for key in _axis_nodes:
		_axis_nodes[key].visible = (key == axis) if axis != "" else false


func set_rotation_angle(angle_deg: float) -> void:
	var label: Label3D = _rotation_ring.get_node_or_null("Label")
	if label:
		label.text = "%.1f°" % angle_deg


func set_track_node(node: Node3D) -> void:
	_track_node = node


func hide_all() -> void:
	visible = false
	_rotation_ring.visible = false
	_track_node = null
