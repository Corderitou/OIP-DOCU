class_name OIPCommsTag
extends RefCounted

var tag_group_name: String
var tag_name: String
var _register_ok: bool = false
var _group_init: bool = false
var _cached: Variant = null
var _cached_set: bool = false


func register(group: String, tag: String, data_type: int = OIPComms.TAG_TYPE_BOOL) -> void:
	tag_group_name = group
	tag_name = tag
	_group_init = false
	_cached_set = false
	_register_ok = OIPComms.register_tag(tag_group_name, tag_name, data_type)


func is_registered() -> bool:
	return _register_ok


func on_group_initialized(group: String) -> bool:
	if group == tag_group_name:
		_group_init = true
		_cached_set = false
		return _register_ok
	return false


func is_ready() -> bool:
	return _register_ok and _group_init


func matches_group(group: String) -> bool:
	return group == tag_group_name


func _should_write(value: Variant) -> bool:
	if _cached_set and _cached == value:
		return false
	_cached = value
	_cached_set = true
	return true


func read_bit() -> bool:
	return OIPComms.read_bit(tag_group_name, tag_name)


func write_bit(value: bool) -> void:
	if not _should_write(value):
		return
	OIPComms.write_bit(tag_group_name, tag_name, value)


func read_float32() -> float:
	return OIPComms.read_float32(tag_group_name, tag_name)


func write_float32(value: float) -> void:
	if not _should_write(value):
		return
	OIPComms.write_float32(tag_group_name, tag_name, value)


func read_float64() -> float:
	return OIPComms.read_float64(tag_group_name, tag_name)


func write_float64(value: float) -> void:
	if not _should_write(value):
		return
	OIPComms.write_float64(tag_group_name, tag_name, value)


func read_int16() -> int:
	return OIPComms.read_int16(tag_group_name, tag_name)


func write_int16(value: int) -> void:
	if not _should_write(value):
		return
	OIPComms.write_int16(tag_group_name, tag_name, value)


func read_int32() -> int:
	return OIPComms.read_int32(tag_group_name, tag_name)


func write_int32(value: int) -> void:
	if not _should_write(value):
		return
	OIPComms.write_int32(tag_group_name, tag_name, value)


func read_uint8() -> int:
	return OIPComms.read_uint8(tag_group_name, tag_name)


func write_uint8(value: int) -> void:
	if not _should_write(value):
		return
	OIPComms.write_uint8(tag_group_name, tag_name, value)
