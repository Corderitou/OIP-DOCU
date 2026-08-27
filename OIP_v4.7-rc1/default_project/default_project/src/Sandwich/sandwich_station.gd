@tool
class_name SandwichStation
extends Node3D

## Estacion "devoradora". Las partes (Celda / Placer / Tira) que entran en la zona
## se despawnan al completarse el stack; por la salida emerge un producto tejido
## (patron TIRADECELDAS: celdas + placers espaciados + 2 tiras paralelas continuas)
## que avanza a la velocidad de la cinta. Sin cadenas fisicas ni joints: todo el
## ensamblado es kinematico/visual. Sin comms.

@export_category("Visualization")
## Logs de deteccion, despawn y unidades generadas.
@export var debug := false
## Preview en el EDITOR (sin play): genera N unidades como hijos temporales del
## nodo para inspeccionar el patron 1 -> 2 -> 2 ... en el arbol. Vista temporal:
## no se guarda con la escena; al volver a 0 o correr la simulacion se limpia.
@export_range(0, 12, 1) var preview_units: int = 0:
	set(v):
		if v == preview_units:
			return
		preview_units = v
		if Engine.is_editor_hint():
			_rebuild_preview()

@export_category("Entrada")
## Tiras minimas para considerar completo el primer stack.
@export_range(1, 4, 1) var min_tiras_first_stack := 2
## Exigir placer para considerar el stack completo.
@export var require_placer := true
## Espera minima entre consumos (evita doble-consume del mismo stack).
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var consume_cooldown := 0.25

@export_category("Producto")
## Separacion entre celdas consecutivas del producto (patron TIRADECELDAS).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var unit_spacing: float = 0.172
## Separacion lateral de las 2 tiras paralelas respecto al centro (z ± offset).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var tira_z_offset: float = 0.03
## Grosor visual de cada tira.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var tira_thickness: float = 0.002
## Ancho (alto en Z) de cada tira.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var tira_width: float = 0.02
## Largo de cada tira visual del bundle (paralelo al avance).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var tira_length: float = 0.2
## Offset en X del TiraBundle del segmento 1 (inicio) respecto a su celda.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var bundle1_offset: float = -0.101
## Offset en X del TiraBundle de los segmentos 2 (medio) respecto a su celda.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var bundle2_offset: float = -0.189
## Nodo de la cinta (para leer su velocidad). Si vacio, usa [member fallback_belt_speed].
@export var belt_path: NodePath
## Velocidad usada si no se encuentra [member belt_path].
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var fallback_belt_speed: float = 0.1
## Al parar la simulacion elimina el producto tejido.
@export var remove_on_stop := true
## Steps del indexing belt que se dejan entre contenedores de producto.
@export_range(0, 20, 1) var batch_gap_steps: int = 2

const MAX_UNITS := 60
const BATCH_SIZE := 6
const TRANSPORT_COLLISION_NAME := "TransportCollision"
const TRANSPORT_COLLISION_LAYER := 0
const TRANSPORT_COLLISION_MASK := 1

var _detect_area: Area3D
var _running := false
var _consumed := 0
var _cooldown_timer: float = 0.0
var _product: Node3D = null
var _scene_product: Node3D = null
var _products: Array[Node3D] = []
var _released: Array[Node3D] = []
var _active_batch_idx := -1
var _units: Array[Node3D] = []
var _belt_body: StaticBody3D = null

var _celda_model: PackedScene
var _placer_model: PackedScene
var _bundle1_scene: PackedScene
var _bundle2_scene: PackedScene
var _tira_scene: PackedScene


func _ready() -> void:
	_detect_area = get_node_or_null("DetectArea") as Area3D
	_celda_model = load("res://celda/Celda.glb") as PackedScene
	_placer_model = load("res://assets/glb/Placer.glb") as PackedScene
	_bundle1_scene = load("res://1TiraBundle.tscn") as PackedScene
	_bundle2_scene = load("res://2TiraBundle.tscn") as PackedScene
	_tira_scene = load("res://parts/Tira.tscn") as PackedScene
	_resolve_belt()
	_resolve_scene_product()


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_stopped)


func _exit_tree() -> void:
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_stopped):
		Simulation.stopped.disconnect(_on_simulation_stopped)
	_cleanup()


func _on_simulation_started() -> void:
	_running = true
	_consumed = 0
	_cooldown_timer = 0.0
	_clear_preview()
	_resolve_scene_product()
	_clear_all_products()
	_clear_released()
	if is_instance_valid(_scene_product):
		_scene_product.top_level = false
		_scene_product.transform = Transform3D.IDENTITY
		_scene_product.hide()


func _on_simulation_stopped() -> void:
	_running = false
	if remove_on_stop:
		_cleanup()


func _cleanup() -> void:
	for product in _products:
		if not is_instance_valid(product):
			continue
		if product == _scene_product:
			_clear_product(product)
			product.hide()
		else:
			product.queue_free()
	if is_instance_valid(_scene_product) and _scene_product not in _products:
		_clear_product(_scene_product)
		_scene_product.hide()
	_products.clear()
	_product = null
	_active_batch_idx = -1
	_units.clear()
	_consumed = 0
	_clear_released()


func _resolve_scene_product() -> void:
	if is_instance_valid(_scene_product):
		return
	var product_parent := get_parent()
	if product_parent == null:
		return
	var candidate := product_parent.get_node_or_null("SandwichProduct") as Node3D
	if candidate == null:
		return
	_scene_product = candidate
	_scene_product.hide()


func _clear_all_products() -> void:
	for product in _products:
		if not is_instance_valid(product):
			continue
		if product == _scene_product:
			_clear_product(product)
			product.hide()
		else:
			product.free()
	_products.clear()
	_product = null
	_active_batch_idx = -1


func _clear_product(product: Node3D) -> void:
	if not is_instance_valid(product):
		return
	for child in product.get_children():
		if child.name == "ProductUnits":
			for part in child.get_children():
				for piece in part.get_children():
					piece.free()
				part.free()
		else:
			child.free()


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


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	_try_consume()
	_advance_product(delta)
	_release_empty_products()


func _try_consume() -> void:
	if not _detect_area or _cooldown_timer > 0.0:
		return
	var seen := {}
	var owners: Array[Node3D] = []
	for body in _detect_area.get_overlapping_bodies():
		var owner := _find_part_owner(body as Node)
		if owner == null:
			continue
		seen[owner] = true
		owners.append(owner)
	if owners.is_empty():
		return
	if not _has_complete_stack(owners):
		return
	_despawn(seen)
	_append_unit()
	_cooldown_timer = consume_cooldown


func _find_part_owner(node: Node) -> Node:
	var n := node
	while n and not (n is Viewport):
		if n is Celda or n is Placer or n is Tira:
			return n
		n = n.get_parent()
	return null


func _has_complete_stack(parts: Array[Node3D]) -> bool:
	var has_celda := false
	var has_placer := false
	var tiras := 0
	for p in parts:
		if p is Celda:
			has_celda = true
		elif p is Placer:
			has_placer = true
		elif p is Tira:
			tiras += 1
	return has_celda and (has_placer or not require_placer) and tiras >= min_tiras_first_stack


func _despawn(seen: Dictionary) -> void:
	for part in seen:
		if part != null and is_instance_valid(part):
			part.queue_free()


func _append_unit() -> void:
	if _consumed >= MAX_UNITS:
		return
	_consumed += 1
	var batch_idx := floori(float(_consumed - 1) / float(BATCH_SIZE))
	if _product == null or not is_instance_valid(_product) or _active_batch_idx != batch_idx:
		_create_product(batch_idx)
	_add_segment(_product, _consumed - batch_idx * BATCH_SIZE)


func _add_segment(parent: Node3D, consumed: int) -> void:
	var idx := consumed - 1
	var celda_x := -float(idx) * unit_spacing
	var is_first := consumed == 1
	var product_units := _get_product_group(parent, "ProductUnits")
	var batch_idx := floori(float(idx) / float(BATCH_SIZE))
	var batch := _get_product_group(product_units, "Batch_%d" % batch_idx)
	var batch_origin_x := -float(batch_idx * BATCH_SIZE + (BATCH_SIZE - 1) * 0.5) * unit_spacing
	var placer_batch := _create_placer_batch(batch, batch_idx, batch_origin_x)
	var woven_batch := _create_woven_batch(batch, batch_idx)
	_add_celda_placer(woven_batch, placer_batch, celda_x, idx, batch_origin_x)
	_add_bundle(woven_batch, celda_x, idx, consumed, is_first)
	_update_transport_collision(parent, consumed)


func _get_product_group(parent: Node3D, group_name: String) -> Node3D:
	var group := parent.get_node_or_null(group_name) as Node3D
	if group != null:
		return group
	group = Node3D.new()
	group.name = group_name
	group.top_level = false
	parent.add_child(group)
	return group


func _add_bundle(parent: Node3D, celda_x: float, idx: int, consumed: int, is_first: bool) -> void:
	var scene := _bundle1_scene if is_first else _bundle2_scene
	var offset := bundle1_offset if is_first else bundle2_offset
	if scene == null:
		return
	var bundle := scene.instantiate() as Node3D
	if bundle == null:
		return
	bundle.name = "Bundle%d" % consumed
	bundle.top_level = false
	bundle.show()
	parent.add_child(bundle)
	bundle.position = Vector3(celda_x + offset, 0.0185, 0.011)
	_add_tira_visuals(bundle)
	var bundle_shape := BoxShape3D.new()
	bundle_shape.size = Vector3(tira_length, tira_thickness, tira_width + tira_z_offset * 2.0)
	var bundle_collision := CollisionShape3D.new()
	bundle_collision.name = "BundleShape_%d" % idx
	bundle_collision.position = Vector3(celda_x + offset, 0.0185, 0.011)
	bundle_collision.shape = bundle_shape
	parent.add_child(bundle_collision)


func _add_tira_visuals(bundle: Node3D) -> void:
	if _tira_scene == null:
		return
	for i in 2:
		var tira := _tira_scene.instantiate() as Node3D
		if tira == null:
			continue
		tira.name = "Tira%d" % (i + 1)
		tira.top_level = false
		tira.show()
		tira.position = Vector3(0.0, 0.0, tira_z_offset if i == 1 else -tira_z_offset)
		bundle.add_child(tira)
		var placeholder := tira.get_node_or_null("Placeholder") as Node3D
		if placeholder:
			placeholder.show()


func _create_product(batch_idx: int) -> void:
	_resolve_scene_product()
	var product: Node3D
	if _products.is_empty() and is_instance_valid(_scene_product):
		product = _scene_product
	else:
		product = CharacterBody3D.new()
		product.name = "SandwichProduct_%d" % batch_idx
		var product_parent := get_parent()
		if product_parent == null:
			product_parent = self
		product_parent.add_child(product)
	product.top_level = true
	_configure_transport_body(product)
	product.show()
	var spawn_position := Vector3(global_position.x, _surface_y(), global_position.z)
	if not _products.is_empty():
		var previous: Node3D = _products.back()
		if is_instance_valid(previous):
			spawn_position.x = previous.global_position.x - _batch_span() - _batch_gap_distance()
	product.global_position = spawn_position
	_products.append(product)
	_product = product
	_active_batch_idx = batch_idx


func _batch_gap_distance() -> float:
	var step_distance := 0.165
	var belt: Node = null
	if is_instance_valid(_belt_body):
		belt = _belt_body.get_parent()
	if belt != null and "step_distance" in belt:
		step_distance = float(belt.step_distance)
	return float(batch_gap_steps) * step_distance


func _batch_span() -> float:
	return float(BATCH_SIZE - 1) * unit_spacing - bundle2_offset


func _surface_y() -> float:
	if is_instance_valid(_belt_body):
		var cs := _belt_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size.y * 0.5
			return _belt_body.global_position.y + h
	return global_position.y


func _configure_transport_body(product: Node3D) -> void:
	var body := product as CharacterBody3D
	if body == null:
		return
	body.collision_layer = TRANSPORT_COLLISION_LAYER
	body.collision_mask = TRANSPORT_COLLISION_MASK
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := body.get_node_or_null(TRANSPORT_COLLISION_NAME) as CollisionShape3D
	if shape != null:
		return
	shape = CollisionShape3D.new()
	shape.name = TRANSPORT_COLLISION_NAME
	body.add_child(shape)


func _update_transport_collision(product: Node3D, consumed: int) -> void:
	var body := product as CharacterBody3D
	if body == null:
		return
	_configure_transport_body(body)
	var shape := body.get_node_or_null(TRANSPORT_COLLISION_NAME) as CollisionShape3D
	if shape == null:
		return

	# The shell covers the cells, placers and the two visual strips in this batch.
	var min_x := 0.0
	var max_x := 0.078
	for i in range(maxi(consumed, 1)):
		var celda_x := -float(i) * unit_spacing
		var bundle_offset := bundle1_offset if i == 0 else bundle2_offset
		min_x = minf(min_x, celda_x + bundle_offset - tira_length * 0.5)
		max_x = maxf(max_x, celda_x + 0.078)
		min_x = minf(min_x, celda_x - 0.0547)
		max_x = maxf(max_x, celda_x + 0.0547)

	var box := shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		shape.shape = box
	box.size = Vector3(max_x - min_x + 0.01, 0.04, 0.20)
	shape.position = Vector3((min_x + max_x) * 0.5, 0.02, 0.0)


func _add_celda_placer(woven_parent: RigidBody3D, placer_parent: RigidBody3D, celda_x: float, idx: int, batch_origin_x: float) -> void:
	var celda := _make_model(woven_parent, _celda_model, "CeldaUnit_%d" % idx)
	var placer := Node3D.new()
	placer.name = "PlacerUnit_%d" % idx
	placer.top_level = false
	placer.position = Vector3(celda_x - batch_origin_x, 0.0, 0.0)
	placer_parent.add_child(placer)
	_make_model(placer, _placer_model, "PlacerModel_%d" % idx)
	var local_x := celda_x - batch_origin_x
	var placer_shape := BoxShape3D.new()
	placer_shape.size = Vector3(0.1094, 0.03, 0.189)
	var placer_collision := CollisionShape3D.new()
	placer_collision.name = "PlacerShape_%d" % idx
	placer_collision.position = Vector3(local_x, 0.0, 0.0)
	placer_collision.shape = placer_shape
	placer_parent.add_child(placer_collision)
	var celda_shape := BoxShape3D.new()
	celda_shape.size = Vector3(0.156, 0.01, 0.156)
	var celda_collision := CollisionShape3D.new()
	celda_collision.name = "CeldaShape_%d" % idx
	celda_collision.position = Vector3(celda_x, 0.0, 0.0)
	celda_collision.shape = celda_shape
	woven_parent.add_child(celda_collision)
	celda.position = Vector3(celda_x, 0.0, 0.0)


func _create_woven_batch(parent: Node3D, batch_idx: int) -> RigidBody3D:
	var body_name := "WovenBatch_%d" % batch_idx
	var existing := parent.get_node_or_null(body_name)
	if existing is RigidBody3D:
		return existing as RigidBody3D
	var body := RigidBody3D.new()
	body.name = body_name
	body.collision_layer = 10
	body.collision_mask = 0
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.set_meta("oip_vacuum_detach", true)
	parent.add_child(body)
	return body


func _create_placer_batch(parent: Node3D, batch_idx: int, batch_origin_x: float) -> RigidBody3D:
	var body_name := "PlacerBatch_%d" % batch_idx
	var existing := parent.get_node_or_null(body_name)
	if existing is RigidBody3D:
		return existing as RigidBody3D
	var body := RigidBody3D.new()
	body.name = body_name
	body.position = Vector3(batch_origin_x, 0.012, 0.0)
	body.collision_layer = 10
	body.collision_mask = 0
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.set_meta("oip_vacuum_detach", true)
	parent.add_child(body)
	return body


func _make_model(parent: Node3D, model: PackedScene, node_name: String) -> Node3D:
	var inst: Node3D = null
	if model:
		inst = model.instantiate() as Node3D
	if inst == null:
		inst = Node3D.new()
	inst.name = node_name
	inst.top_level = false
	inst.show()
	inst.scale = Vector3(0.03, 0.03, 0.03)
	parent.add_child(inst)
	return inst


## Preview en el editor: recrea los hijos temporales segun [member preview_units].
func _rebuild_preview() -> void:
	_clear_preview()
	if preview_units <= 0 or not is_inside_tree():
		return
	var pv := Node3D.new()
	pv.name = "PreviewSandwichProduct"
	pv.top_level = true
	add_child(pv)
	pv.global_position = Vector3(global_position.x, _surface_y(), global_position.z)
	for n in range(1, preview_units + 1):
		_add_segment(pv, n)


func _clear_preview() -> void:
	var pv := get_node_or_null("PreviewSandwichProduct")
	if is_instance_valid(pv):
		pv.free()


## El producto se desliza hacia adelante (frente = +X) a la velocidad de la cinta.
func _advance_product(delta: float) -> void:
	var vx := _belt_velocity_x()
	if absf(vx) < 1e-5:
		return
	for product in _products:
		if is_instance_valid(product):
			var body := product as CharacterBody3D
			if body != null:
				body.move_and_collide(Vector3(vx * delta, 0.0, 0.0))
			else:
				product.position.x += vx * delta


## El vacuum del robot desmonta los cuerpos del lote dejandolos top_level. Cuando ya
## tomo todos, el shell del producto queda vacio detenido contra el tope: se retira para
## que no se acumule. Los cuerpos desmontados pasan a un contenedor ReleasedBatches
## ( conservando su transform global; el robot puede seguir cargandolos porque escribe
## su transform global cada frame).
func _release_empty_products() -> void:
	for product in _products.duplicate():
		if not is_instance_valid(product):
			_products.erase(product)
			continue
		var batches := _collect_batch_bodies(product)
		if batches.is_empty():
			continue
		var all_detached := true
		for body in batches:
			if not body.top_level:
				all_detached = false
				break
		if not all_detached:
			continue
		var container := _released_container()
		for body in batches:
			body.reparent(container)
			_released.append(body)
		if product == _scene_product:
			_clear_product(product)
			product.hide()
		else:
			product.queue_free()
		_products.erase(product)
		if _product == product:
			_product = null
			_active_batch_idx = -1
		if debug:
			print("SandwichStation: shell vacio liberado (%d cuerpos en ReleasedBatches)" % batches.size())


## Cuerpos de pickup (WovenBatch_* / PlacerBatch_*) del producto, iterando cada contenedor
## Batch_* propio. Nunca buscarlos por nombre global: cada producto tiene su Batch_0.
func _collect_batch_bodies(product: Node3D) -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	var units := product.get_node_or_null("ProductUnits")
	if units == null:
		return bodies
	for batch_group in units.get_children():
		for child in batch_group.get_children():
			if child is RigidBody3D:
				bodies.append(child)
	return bodies


func _released_container() -> Node3D:
	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self
	var container := parent_node.get_node_or_null("ReleasedBatches") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "ReleasedBatches"
		parent_node.add_child(container)
	return container


func _clear_released() -> void:
	_released.clear()
	var parent_node := get_parent()
	if parent_node == null:
		return
	var container := parent_node.get_node_or_null("ReleasedBatches")
	if container != null:
		container.queue_free()
