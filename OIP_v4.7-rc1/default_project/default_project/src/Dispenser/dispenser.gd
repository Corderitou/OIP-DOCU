@tool
class_name Dispenser
extends Node3D

@export var scene: PackedScene
@export var initial_linear_velocity: Vector3 = Vector3.ZERO
@export var tira_spacing: float = 0.02
## Cantidad de tiras por ciclo. Si es >= 2, se agrupan bajo un TiraBundle
## (caen/viajan como un solo objeto "escalera" con cross-joints).
@export_range(1, 2, 1) var tiras_por_ciclo: int = 2

@export var cut_trigger: bool = false:
	set(v):
		if v:
			cut()
		cut_trigger = false

@onready var _spawn_point: Node3D = $SpawnPoint
@onready var _dispenser_head: Node3D = $dispenserhead

var _highlight_mat: StandardMaterial3D = null
var _spawned_tiras: Array[Node3D] = []
var _bundle: TiraBundle = null


func get_spawn_origin() -> Node3D:
	if _dispenser_head and is_instance_valid(_dispenser_head):
		return _dispenser_head
	if _spawn_point and is_instance_valid(_spawn_point):
		return _spawn_point
	return self


func set_detected(detected: bool) -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh:
		return
	if detected:
		if not _highlight_mat:
			_highlight_mat = StandardMaterial3D.new()
			_highlight_mat.albedo_color = Color(0.0, 1.0, 0.0, 1.0)
		mesh.material_override = _highlight_mat
	else:
		mesh.material_override = null


func spawn_tira(end_pos: Vector3 = Vector3.INF) -> Array[Node3D]:
	_spawned_tiras.clear()
	_bundle = null
	if not scene:
		push_warning("Dispenser: No scene assigned in " + name)
		return _spawned_tiras

	var origin := get_spawn_origin()
	var lateral := Vector3.RIGHT
	if end_pos.is_finite():
		lateral = Tira.lateral_axis(origin.global_position, end_pos)

	var cantidad := maxi(tiras_por_ciclo, 1)
	if cantidad >= 2:
		_bundle = TiraBundle.new()
		_bundle.name = "TiraBundle"
		origin.add_child(_bundle, true)
		_bundle.owner = Tira.get_common_container(self)

	for i in cantidad:
		var tira := scene.instantiate() as Node3D
		if not tira:
			continue

		if _bundle:
			_bundle.add_child(tira, true)
			(_bundle as TiraBundle).add_tira(tira as Tira)
		else:
			origin.add_child(tira, true)

		if origin and is_inside_tree():
			var offset := lateral * (float(i) - 0.5) * tira_spacing
			tira.global_position = origin.global_position + offset
			tira.global_rotation = origin.global_rotation

		if "initial_linear_velocity" in tira:
			tira.set("initial_linear_velocity", initial_linear_velocity)

		if "instanced" in tira:
			tira.set("instanced", true)

		var tree := get_tree()
		if tree and is_inside_tree():
			tira.owner = Tira.get_common_container(self)

		_spawned_tiras.append(tira)

	return _spawned_tiras


func has_active_tira() -> bool:
	for c in find_children("*", "Tira", true, false):
		var t := c as Tira
		if t and (t.has_chain() or t.anchored_dispenser or t.anchored_picker or t.held):
			return true
	return false


func cut() -> void:
	var root := Tira.get_common_container(self) if get_tree() else null
	if not root:
		return

	var tiras: Array[Node] = []
	for c in find_children("*", "Tira", true, false):
		var t := c as Tira
		if t and t.has_chain():
			tiras.append(t)
	if tiras.is_empty():
		return

	# Si las tiras viven en un TiraBundle, se reparentea el bundle COMPLETO a la
	# raiz (conservando la agrupacion y los cross-joints). Si no, cada tira.
	if _bundle and is_instance_valid(_bundle):
		for tira_node in tiras:
			var tira := tira_node as Tira
			if tira:
				tira.cut_chain()
		if _bundle.get_parent() != root:
			var gt := _bundle.global_transform
			_bundle.get_parent().remove_child(_bundle)
			root.add_child(_bundle, true)
			_bundle.global_transform = gt
			_bundle.owner = root
		for tira_node in tiras:
			var tira := tira_node as Tira
			if tira:
				tira.detach_after_reparent()
	else:
		for tira_node in tiras:
			var tira := tira_node as Tira
			if not tira:
				continue
			tira.cut_chain()
			if tira.get_parent() != root:
				var gt := tira.global_transform
				tira.get_parent().remove_child(tira)
				root.add_child(tira, true)
				tira.global_transform = gt
				tira.owner = root
			tira.detach_after_reparent()

	if not _spawned_tiras.is_empty():
		_spawned_tiras.clear()
