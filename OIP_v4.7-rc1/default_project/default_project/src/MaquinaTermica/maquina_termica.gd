@tool
class_name MaquinaTermica
extends Maquina

## Máquina con modelo térmico de primer orden. El PID corre en PLCSIM: la
## planta integra dT/dt a partir de la salida del PID (MV, 0-100 %) y escribe
## la temperatura medida (PV). Incluye fallback analógico DINT escalado.

@export_subgroup("PID Tags")
@export var setpoint_tag: String = "_SETPOINT"
@export var mv_tag: String = "_MV"
@export var pv_tag: String = "_PV"
@export var cycle_time_tag: String = "_CYCLE_TIME"

@export_subgroup("Modelo Térmico")
@export_custom(PROPERTY_HINT_NONE, "suffix:°C") var ambient_temp: float = 25.0
## °C de sobretemperatura en estado estable con MV=100 %.
@export_custom(PROPERTY_HINT_NONE, "suffix:°C") var thermal_gain: float = 150.0
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var thermal_tau: float = 20.0
@export_custom(PROPERTY_HINT_NONE, "suffix:°C") var fault_threshold: float = 260.0
@export_custom(PROPERTY_HINT_NONE, "suffix:°C") var starting_temp: float = 25.0
@export_custom(PROPERTY_HINT_NONE, "suffix:°C") var max_temp: float = 400.0

@export_subgroup("Formato Analógico")
## Si true, PV/MV se intercambian como DINT escalado por analog_scale (fallback
## si el driver S7 no soporta REAL).
@export var analog_as_dint: bool = false
@export_custom(PROPERTY_HINT_NONE, "suffix:unid/°C") var analog_scale: float = 10.0

var _temp: float = 25.0
var _cycle_elapsed: float = 0.0

@onready var _heater_visual: MeshInstance3D = get_node_or_null("HeaterVisual") as MeshInstance3D
var _heater_mat: StandardMaterial3D


func _ready() -> void:
	_temp = starting_temp


func _build_tag_spec() -> Dictionary:
	var spec := super._build_tag_spec()
	spec[_tag(setpoint_tag)] = OIPComms.TAG_TYPE_FLOAT32
	spec[_tag(mv_tag)] = OIPComms.TAG_TYPE_FLOAT32
	spec[_tag(pv_tag)] = OIPComms.TAG_TYPE_FLOAT32
	spec[_tag(cycle_time_tag)] = OIPComms.TAG_TYPE_FLOAT32
	return spec


func _on_tick(delta: float) -> void:
	var mv := 0.0
	if _comms.is_ready():
		mv = _read_float_tag(mv_tag)

	var dt := clampf(delta, 0.0, 0.1)
	var heating := thermal_gain * clampf(mv, 0.0, 100.0) / 100.0
	var cooling := (_temp - ambient_temp) / maxf(thermal_tau, 0.1)
	_temp = clampf(_temp + dt * (heating - cooling), -50.0, max_temp)

	if _temp >= fault_threshold:
		set_fault(true)

	if _comms.is_ready():
		_write_float_tag(pv_tag, _temp, true)
		if _cycle_active:
			_cycle_elapsed += delta
			_write_float_tag(cycle_time_tag, _cycle_elapsed, true)

	_update_heater_visual()


func on_cycle_started() -> void:
	_cycle_elapsed = 0.0
	set_fault(false)
	if _comms.is_ready():
		_write_float_tag(cycle_time_tag, 0.0)


func _write_float_tag(suffix: String, value: float, only_if_changed: bool = false) -> void:
	if analog_as_dint:
		_comms.write_int(_tag(suffix), int(round(value * analog_scale)))
	else:
		_comms.write_float(_tag(suffix), value, only_if_changed)


func _read_float_tag(suffix: String) -> float:
	if analog_as_dint:
		return float(_comms.read_int(_tag(suffix))) / analog_scale
	return _comms.read_float(_tag(suffix))


func _update_heater_visual() -> void:
	if not is_instance_valid(_heater_visual):
		return
	if _heater_mat == null:
		_heater_mat = _heater_visual.get_surface_override_material(0) as StandardMaterial3D
		if _heater_mat == null:
			var base := _heater_visual.mesh.surface_get_material(0) as StandardMaterial3D
			if base == null:
				return
			_heater_mat = base.duplicate()
			_heater_visual.set_surface_override_material(0, _heater_mat)
	var t := clampf((_temp - ambient_temp) / maxf(fault_threshold - ambient_temp, 1.0), 0.0, 1.0)
	_heater_mat.emission_enabled = t > 0.01
	_heater_mat.emission = Color(1.0, lerpf(0.25, 1.0, t), lerpf(0.1, 0.4, t)) * t
	_heater_mat.emission_energy_multiplier = t * 3.0
