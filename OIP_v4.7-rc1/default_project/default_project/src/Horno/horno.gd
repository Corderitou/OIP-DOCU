@tool
class_name Horno
extends MaquinaTermica

## Horno de la línea (tipo MaquinaTermica): un cabezal que baja sobre el
## producto tejido (SandwichProduct) que avanza por la cinta, lo "calienta"
## (modelo térmico PID) para terminar de soldar las conexiones, y sube al
## terminar el ciclo. Control por PLC via comms (CMD/EXEC). La detección
## por distancia alimenta IN_POS.

@export_category("Cabezal")
## Nodo del cabezal (MeshInstance3D) que baja/subse.
@export var head_path: NodePath = NodePath("Head")
## Posición Y local del cabezal en reposo (arriba).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var head_up_y: float = 0.1
## Posición Y local del cabezal calentando (abajo).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var head_down_y: float = -0.45
## Tiempo en bajar/subir el cabezal.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var head_move_time: float = 1.0

@export_category("Detección")
## Nodo del producto tejido (SandwichProduct). Si vacío, se busca por nombre
## "SandwichProduct" en el árbol.
@export var product_path: NodePath
## Semiancho X de la zona de detección respecto al horno.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var detect_half_width: float = 0.35
## Logs de detección y ciclo.
@export var debug := false

var _product: Node3D = null


func _on_tick(delta: float) -> void:
	var mv := 0.0
	if _comms.is_ready():
		mv = _read_float_tag(mv_tag)
	if _comms.is_ready():
		if _cycle_active:
			_cycle_elapsed += delta
			_write_float_tag(cycle_time_tag, _cycle_elapsed, true)
	# Temperatura basada en la posición del cabezal: abajo = caliente, arriba = frío.
	var head := get_node_or_null(head_path) as Node3D
	if head:
		var t := clampf(inverse_lerp(head_up_y, head_down_y, head.position.y), 0.0, 1.0)
		_temp = lerpf(ambient_temp, ambient_temp + thermal_gain, t)
	else:
		_temp = ambient_temp + thermal_gain if _cycle_active else ambient_temp
	if _comms.is_ready():
		_write_float_tag(pv_tag, _temp, true)
	_update_heater_visual()
	_animate_head(delta)


func _physics_process(delta: float) -> void:
	_update_detection()
	super._physics_process(delta)


func _on_simulation_started() -> void:
	_heater_visual = get_node_or_null("Head/HeaterVisual") as MeshInstance3D
	super._on_simulation_started()
	_product = _resolve_product()


func _on_simulation_ended() -> void:
	super._on_simulation_ended()
	_product = null


func on_cycle_started() -> void:
	print("[Horno %s] CICLO INICIADO (CMD=1)" % name)
	super.on_cycle_started()


func on_cycle_finished() -> void:
	print("[Horno %s] CICLO TERMINADO (DONE)" % name)
	super.on_cycle_finished()


func _resolve_product() -> Node3D:
	if not product_path.is_empty():
		var n := get_node_or_null(product_path)
		if is_instance_valid(n):
			return n as Node3D
	if not is_inside_tree():
		return null
	for c in get_tree().root.find_children("SandwichProduct", "Node3D", true, false):
		return c as Node3D
	return null


## Polling de distancia: detecta si el producto está bajo el horno para
## alimentar IN_POS al PLC. El ciclo lo dispara CMD/EXEC via comms.
func _update_detection() -> void:
	var present := false
	if not is_instance_valid(_product):
		_product = _resolve_product()
	if is_instance_valid(_product):
		var hx := global_position.x
		for child in _product.get_children():
			if child is Node3D:
				var gx := (child as Node3D).global_position.x
				if absf(gx - hx) <= detect_half_width:
					present = true
					break
	set_product_present(present)


func _animate_head(delta: float) -> void:
	var head := get_node_or_null(head_path) as Node3D
	if head == null:
		return
	var target := head_down_y if _cycle_active else head_up_y
	var stroke := absf(head_down_y - head_up_y)
	var speed := stroke / maxf(head_move_time, 0.001)
	head.position.y = move_toward(head.position.y, target, speed * delta)
