@tool
extends Node

## Simulated OIPComms singleton for Godot 4.7 editor use when the real GDExtension is unavailable.
## Register in project.godot:  OIPComms="*res://src/comms/oip_comms_sim.gd"
## Remove this line when the GDExtension .gdextension file is re-enabled.

signal comms_error
signal enable_comms_changed
signal tag_group_initialized(group: String)
signal tag_group_polled(group: String)
signal tag_groups_registered
signal connection_status_changed(connected: bool)
signal tag_read(group: String, tag: String, value: Variant)
signal tag_written(group: String, tag: String, value: Variant)
signal log_message(text: String, level: int)

enum LogLevel { INFO, WARN, ERROR, DEBUG }

const TAG_TYPE_BOOL := 0
const TAG_TYPE_INT16 := 1
const TAG_TYPE_INT32 := 2
const TAG_TYPE_UINT8 := 3
const TAG_TYPE_UINT16 := 4
const TAG_TYPE_FLOAT32 := 5
const TAG_TYPE_FLOAT64 := 6

var _comms_enabled := false
var _logging_enabled := false
var _sim_running := false
var _tag_groups: Array[String] = []
var _tags: Dictionary = {}
var _tag_values: Dictionary = {}
var _soft_plc_programs: Dictionary = {}
var _soft_plc_watches: Dictionary = {}
var _last_error := ""


func get_enable_comms() -> bool:
	return _comms_enabled


func set_enable_comms(enabled: bool) -> void:
	_comms_enabled = enabled
	enable_comms_changed.emit()
	if enabled:
		push_warning("OIPCommsSim: comms enabled — no real backend available")
		_last_error = "OIP Comms GDExtension is not loaded. Enable the .gdextension file and fix native DLLs for real OPC UA."
		comms_error.emit()


func get_comms_error() -> String:
	return _last_error


func get_tag_groups() -> Array:
	return _tag_groups.duplicate()


func clear_tag_groups() -> void:
	_tag_groups.clear()
	_tags.clear()
	_tag_values.clear()


func register_tag_group(name: String, poll_rate: int, protocol: String, gateway: String, path: String = "", cpu: String = "ControlLogix") -> void:
	if name.is_empty():
		return
	if not _tag_groups.has(name):
		_tag_groups.append(name)
	tag_groups_registered.emit()


func register_tag(group: String, tag: String, count: int = 1) -> bool:
	if group.is_empty() or tag.is_empty():
		return false
	var key := group + "/" + tag
	_tags[key] = {"group": group, "tag": tag, "count": count}
	_tag_values[key] = 0
	return true


func read_bit(group: String, tag: String) -> bool:
	return _read_value("read_bit", group, tag) == true


func write_bit(group: String, tag: String, value: bool) -> void:
	_write_value("write_bit", group, tag, value)


func read_float32(group: String, tag: String) -> float:
	return float(_read_value("read_float32", group, tag))


func write_float32(group: String, tag: String, value: float) -> void:
	_write_value("write_float32", group, tag, value)


func read_float64(group: String, tag: String) -> float:
	return float(_read_value("read_float64", group, tag))


func write_float64(group: String, tag: String, value: float) -> void:
	_write_value("write_float64", group, tag, value)


func read_int16(group: String, tag: String) -> int:
	return int(_read_value("read_int16", group, tag))


func write_int16(group: String, tag: String, value: int) -> void:
	_write_value("write_int16", group, tag, value)


func read_int32(group: String, tag: String) -> int:
	return int(_read_value("read_int32", group, tag))


func write_int32(group: String, tag: String, value: int) -> void:
	_write_value("write_int32", group, tag, value)


func read_uint8(group: String, tag: String) -> int:
	return int(_read_value("read_uint8", group, tag))


func write_uint8(group: String, tag: String, value: int) -> void:
	_write_value("write_uint8", group, tag, value)


func set_sim_running(running: bool) -> void:
	_sim_running = running


func set_soft_plc_program(group: String, src: String) -> void:
	_soft_plc_programs[group] = src


func compile_soft_plc(group: String, src: String) -> String:
	_soft_plc_programs[group] = src
	return ""


func set_soft_plc_watch_enabled(group: String, enabled: bool) -> void:
	_soft_plc_watches[group] = enabled


func get_soft_plc_watch(group: String) -> Array:
	return []


func _read_value(method: String, group: String, tag: String) -> Variant:
	if not _comms_enabled:
		return 0
	var key := group + "/" + tag
	var val = _tag_values.get(key, 0)
	tag_read.emit(group, tag, val)
	return val


func _write_value(method: String, group: String, tag: String, value: Variant) -> void:
	if not _comms_enabled:
		return
	var key := group + "/" + tag
	_tag_values[key] = value
	tag_written.emit(group, tag, value)
