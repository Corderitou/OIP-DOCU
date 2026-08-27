@tool
class_name PlacerExtractor
extends Node3D

## Estacion extractora de placers. Cuando el producto tejido (SandwichProduct)
## pasa por la zona, cada placer del ensamblado (PlacerUnit_* dentro de un
## PlacerBatch_*) que cruza la ventana se retira del producto y se reemplaza
## por un Placer fisico normal (parts/Placer.tscn) en la misma posicion.
## Los Placer reales que entran en la zona no se modifican: pasan tal cual.

@export_category("Visualization")
## Logs de deteccion y extraccion.
@export var debug := false

@export_category("Entrada")
## Escena de Placer a emitir. Si vacia usa res://parts/Placer.tscn.
@export var placer_scene: PackedScene
## Semiancho de la ventana de extraccion en X (alrededor del nodo). Debe ser
## >= medio unit_spacing del producto (0.086) para no saltarse unidades.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var detect_half_width: float = 0.09

@export_category("Salida")
## Entregar al placer extraido la velocidad actual de la cinta.
@export var give_belt_velocity := true
## Nodo de la cinta (para leer su velocidad). Si vacio, busca un IndexingBelt.
@export var belt_path: NodePath
## Velocidad usada si no se encuentra [member belt_path].
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var fallback_belt_speed: float = 0.1

var _detect_area: Area3D
var _running := false
var _extracted := 0
var _belt_body: StaticBody3D = null


func _ready() -> void:
	_detect_area = get_node_or_null("DetectArea") as Area3D
	if placer_scene == null:
		placer_scene = load("res://parts/Placer.tscn") as PackedScene
	_resolve_belt()


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_stopped)


func _exit_tree() -> void:
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_stopped):
		Simulation.stopped.disconnect(_on_simulation_stopped)


func _on_simulation_started() -> void:
	_running = true
	_extracted = 0


func _on_simulation_stopped() -> void:
	_running = false


func _resolve_belt() -> void:
	if not belt_path.is_empty():
		var n := get_node_or_null(belt_path)
		_belt_body = n as StaticBody3D
		if _belt_body == null and n is Node:
			_belt_body = n.get_node_or_null("BeltBody") as StaticBody3D
		if is_instance_valid(_belt_body):
			return
	_belt_body = null
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("IndexingBelt"):
		_belt_body = node.get_node_or_null("BeltBody") as StaticBody3D
		if is_instance_valid(_belt_body):
			return
	for candidate in get_tree().root.find_children("*", "IndexingBeltConveyor", true, false):
		_belt_body = candidate.get_node_or_null("BeltBody") as StaticBody3D
		if is_instance_valid(_belt_body):
			return


func _belt_velocity_x() -> float:
	if is_instance_valid(_belt_body):
		return _belt_body.constant_linear_velocity.x
	return fallback_belt_speed if _running else 0.0


func _physics_process(_delta: float) -> void:
	if not _running or _detect_area == null:
		return
	var station_x := global_position.x
	for body in _detect_area.get_overlapping_bodies():
		var batch := body as RigidBody3D
		if batch == null or not String(batch.name).begins_with("PlacerBatch"):
			continue
		_convert_units(batch, station_x)


## Retira del lote cada PlacerUnit cuya X global caiga dentro de la ventana
## y emite un Placer real en su lugar.
func _convert_units(batch: RigidBody3D, station_x: float) -> void:
	var to_remove: Array[Node] = []
	for child in batch.get_children():
		var unit := child as Node3D
		if unit == null or not String(unit.name).begins_with("PlacerUnit"):
			continue
		var world_pos := batch.to_global(unit.position)
		if absf(world_pos.x - station_x) <= detect_half_width:
			to_remove.append(unit)
			_spawn_placer(world_pos)
	for unit in to_remove:
		_remove_unit(batch, unit)


func _remove_unit(batch: RigidBody3D, unit: Node) -> void:
	var suffix := String(unit.name).trim_prefix("PlacerUnit")
	var shape := batch.get_node_or_null("PlacerShape" + suffix)
	if shape != null:
		shape.queue_free()
	unit.queue_free()
	_extracted += 1
	if debug:
		print("PlacerExtractor: unidad %s extraida (%d total)" % [unit.name, _extracted])


func _spawn_placer(world_pos: Vector3) -> void:
	var scene := placer_scene
	if scene == null:
		scene = load("res://parts/Placer.tscn") as PackedScene
	if scene == null:
		return
	var item := scene.instantiate() as Node3D
	var placer := item as Placer
	if placer == null:
		push_warning("PlacerExtractor: la escena configurada no deriva de Placer")
		if item != null:
			item.free()
		return
	placer.instanced = true
	if give_belt_velocity:
		placer.initial_linear_velocity = Vector3(_belt_velocity_x(), 0.0, 0.0)
	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self
	parent_node.add_child(item)
	item.global_position = world_pos
