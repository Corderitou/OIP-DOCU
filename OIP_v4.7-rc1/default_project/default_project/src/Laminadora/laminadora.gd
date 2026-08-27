@tool
class_name Laminadora
extends MaquinaTermica

## Estación de laminación (etapa 5): PID de temperatura en PLCSIM + modelo de
## vacío de primer orden. Expone S5_SETPOINT/S5_MV/S5_PV y S5_VACUUM_MV/PV.

@export_subgroup("Vacío Tags")
@export var vacuum_mv_tag: String = "_VACUUM_MV"
@export var vacuum_pv_tag: String = "_VACUUM_PV"

@export_subgroup("Modelo de Vacío")
@export_custom(PROPERTY_HINT_NONE, "suffix:mbar") var vacuum_max: float = -980.0
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var vacuum_tau: float = 3.0

var _vacuum: float = 0.0


func _build_tag_spec() -> Dictionary:
	var spec := super._build_tag_spec()
	spec[_tag(vacuum_mv_tag)] = OIPComms.TAG_TYPE_FLOAT32
	spec[_tag(vacuum_pv_tag)] = OIPComms.TAG_TYPE_FLOAT32
	return spec


func _on_tick(delta: float) -> void:
	super._on_tick(delta)
	var vmv := 0.0
	if _comms.is_ready():
		vmv = _read_float_tag(vacuum_mv_tag)
	var target := vacuum_max * clampf(vmv, 0.0, 100.0) / 100.0
	_vacuum = lerpf(_vacuum, target, clampf(delta / maxf(vacuum_tau, 0.1), 0.0, 1.0))
	if _comms.is_ready():
		_write_float_tag(vacuum_pv_tag, _vacuum)
