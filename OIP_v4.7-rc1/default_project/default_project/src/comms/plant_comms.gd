@tool
class_name PlantComms
extends RefCounted

## Helper de comunicaciones multi-tag para máquinas de planta.
##
## Gestiona un conjunto de tags (especificados como un Dictionary nombre -> tipo)
## dentro de un único tag group, replicando el patrón de OIPCommsTag:
## registra en _on_simulation_started() y espera a tag_group_initialized.

var group_name: String
var _spec: Dictionary = {}
var _tags: Dictionary = {}
var _register_ok: bool = false
var _group_init: bool = false
var _cached_bit: Dictionary = {}
var _cached_float: Dictionary = {}


func setup(group: String, spec: Dictionary) -> void:
	group_name = group
	_spec = spec


func register_all() -> void:
	_tags.clear()
	_cached_bit.clear()
	_cached_float.clear()
	_group_init = false
	_register_ok = true
	for tag_name: String in _spec:
		var tag := OIPCommsTag.new()
		tag.register(group_name, tag_name, _spec[tag_name])
		if not tag.is_registered():
			_register_ok = false
		_tags[tag_name] = tag


func on_group_initialized(group: String) -> bool:
	if group != group_name:
		return false
	_group_init = true
	return _register_ok


func is_ready() -> bool:
	return _register_ok and _group_init


func matches_group(group: String) -> bool:
	return group == group_name


func has(tag_name: String) -> bool:
	return _tags.has(tag_name)


func write_bit(tag_name: String, value: bool, only_if_changed: bool = false) -> void:
	if not is_ready() or not _tags.has(tag_name):
		return
	if only_if_changed and _cached_bit.has(tag_name) and _cached_bit[tag_name] == value:
		return
	_cached_bit[tag_name] = value
	(_tags[tag_name] as OIPCommsTag).write_bit(value)


func read_bit(tag_name: String) -> bool:
	if is_ready() and _tags.has(tag_name):
		return (_tags[tag_name] as OIPCommsTag).read_bit()
	return false


func write_float(tag_name: String, value: float, only_if_changed: bool = false) -> void:
	if not is_ready() or not _tags.has(tag_name):
		return
	if only_if_changed:
		if _cached_float.has(tag_name) and absf(_cached_float[tag_name] - value) < 0.05:
			return
		_cached_float[tag_name] = value
	(_tags[tag_name] as OIPCommsTag).write_float32(value)


func read_float(tag_name: String) -> float:
	if is_ready() and _tags.has(tag_name):
		return (_tags[tag_name] as OIPCommsTag).read_float32()
	return 0.0


func write_int(tag_name: String, value: int) -> void:
	if is_ready() and _tags.has(tag_name):
		(_tags[tag_name] as OIPCommsTag).write_int32(value)


func read_int(tag_name: String) -> int:
	if is_ready() and _tags.has(tag_name):
		return (_tags[tag_name] as OIPCommsTag).read_int32()
	return 0


func write_uint8(tag_name: String, value: int) -> void:
	if is_ready() and _tags.has(tag_name):
		(_tags[tag_name] as OIPCommsTag).write_uint8(value)
