@tool
extends Node

# Runtime facade for the OIP Comms GDExtension. The project autoload keeps the
# API used by scene components while the actual OPC UA I/O stays in the native singleton.
signal enable_comms_changed
signal tag_group_initialized(group: String)
signal tag_group_polled(group: String)
signal tag_groups_registered
signal comms_error
signal connection_status_changed(connected: bool)
signal tag_read(group: String, tag: String, value: Variant)
signal tag_written(group: String, tag: String, value: Variant)
signal log_message(text: String, level: int)

enum LogLevel { INFO, WARN, ERROR, DEBUG }

var _backend: Object = null
var _comms_enabled := false
var _connected := false
var _logging_enabled := false
var _last_error := ""
var _tag_groups: Array[String] = []


func _ready() -> void:
	_backend = Engine.get_singleton("OIPComms")
	if _backend == null:
		_set_error("OIP Comms GDExtension is not available. OPC UA cannot be used in this runtime.")
		return
	_connect_backend_signals()
	_log("OIP Comms GDExtension ready", LogLevel.INFO)


func _connect_backend_signals() -> void:
	_connect_backend_signal("tag_group_initialized", _on_backend_group_initialized)
	_connect_backend_signal("tag_group_polled", _on_backend_group_polled)
	_connect_backend_signal("comms_error", _on_backend_error)


func _connect_backend_signal(signal_name: String, callback: Callable) -> void:
	if _backend != null and _backend.has_signal(signal_name) and not _backend.is_connected(signal_name, callback):
		_backend.connect(signal_name, callback)


func is_backend_available() -> bool:
	return _backend != null


func get_enable_comms() -> bool:
	return _comms_enabled


func set_enable_comms(enabled: bool) -> void:
	_comms_enabled = enabled
	if _backend == null:
		_connected = false
		connection_status_changed.emit(false)
		_set_error("Cannot enable communications because the OIP Comms GDExtension is unavailable.")
		return
	if not _backend.has_method("set_enable_comms"):
		_set_error("The loaded OIP Comms GDExtension does not expose set_enable_comms().")
		return
	_backend.call("set_enable_comms", enabled)
	if not enabled:
		_connected = false
		connection_status_changed.emit(false)
		_log("Comms disabled", LogLevel.INFO)
	else:
		# Enabling polling is not evidence that an external server accepted a session.
		_log("Comms enabled. Run Test OPC UA to verify the server endpoint.", LogLevel.INFO)


func is_comms_connected() -> bool:
	return _connected and _comms_enabled


func get_comms_error() -> String:
	return _last_error


func get_tag_groups() -> Array:
	return _tag_groups.duplicate()


func clear_tag_groups() -> void:
	_tag_groups.clear()
	if _backend != null:
		if _backend.has_method("clear_tag_groups"):
			_backend.call("clear_tag_groups")


func register_tag_group(name: String, poll_rate: int, protocol: String, gateway: String, path: String = "", cpu: String = "ControlLogix") -> void:
	if name.is_empty():
		_set_error("A tag group needs a name.")
		return
	if not _tag_groups.has(name):
		_tag_groups.append(name)
	if _backend == null:
		_set_error("Cannot register '%s': OIP Comms GDExtension is unavailable." % name)
		return
	if not _backend.has_method("register_tag_group"):
		_set_error("The loaded OIP Comms GDExtension does not expose register_tag_group().")
		return
	_backend.call("register_tag_group", name, poll_rate, protocol, gateway, path, cpu)


func finish_registering_tag_groups() -> void:
	tag_groups_registered.emit()


func register_tag(group: String, tag: String, count: int = 1) -> bool:
	if _backend == null or group.is_empty() or tag.is_empty():
		return false
	return _backend.call("register_tag", group, tag, count) == true


func set_enable_log(enabled: bool) -> void:
	_logging_enabled = enabled
	if _backend != null and _backend.has_method("set_enable_log"):
		_backend.call("set_enable_log", enabled)


func set_sim_running(running: bool) -> void:
	if _backend != null and _backend.has_method("set_sim_running"):
		_backend.call("set_sim_running", running)


func test_opc_ua(endpoint: String) -> Dictionary:
	var clean_endpoint := endpoint.strip_edges()
	if not clean_endpoint.begins_with("opc.tcp://"):
		return _test_result(false, "The OPC UA endpoint must start with opc.tcp://, for example opc.tcp://192.168.1.10:4840")
	if _backend == null:
		return _test_result(false, "OIP Comms GDExtension is unavailable. The native OPC UA client was not loaded.")
	if not _backend.has_method("browse_connect") or not _backend.has_method("browse_disconnect"):
		return _test_result(false, "The loaded OIP Comms GDExtension does not expose OPC UA browse_connect().")

	var ok: bool = _backend.call("browse_connect", clean_endpoint) == true
	if ok:
		_backend.call("browse_disconnect")
		_connected = true
		_last_error = ""
		connection_status_changed.emit(true)
		return _test_result(true, "Connected to %s" % clean_endpoint)

	_connected = false
	connection_status_changed.emit(false)
	var detail: String = str(_backend.call("get_comms_error")) if _backend.has_method("get_comms_error") else ""
	return _test_result(false, "Connection to %s failed%s" % [clean_endpoint, ": " + detail if not detail.is_empty() else ""])


func read_bit(group: String, tag: String) -> bool:
	return _read_value("read_bit", group, tag) == true


func write_bit(group: String, tag: String, value: bool) -> void:
	_write_value("write_bit", group, tag, value)


func read_float32(group: String, tag: String) -> float:
	return float(_read_value("read_float32", group, tag))


func write_float32(group: String, tag: String, value: float) -> void:
	_write_value("write_float32", group, tag, value)


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


func _read_value(method: String, group: String, tag: String) -> Variant:
	if _backend == null or not _comms_enabled or not _backend.has_method(method):
		return 0
	var value: Variant = _backend.call(method, group, tag)
	tag_read.emit(group, tag, value)
	return value


func _write_value(method: String, group: String, tag: String, value: Variant) -> void:
	if _backend == null or not _comms_enabled or not _backend.has_method(method):
		return
	_backend.call(method, group, tag, value)
	tag_written.emit(group, tag, value)


func _test_result(ok: bool, message: String) -> Dictionary:
	if ok:
		_log(message, LogLevel.INFO)
	else:
		_set_error(message)
	return {"ok": ok, "message": message}


func _on_backend_group_initialized(group: String) -> void:
	tag_group_initialized.emit(group)


func _on_backend_group_polled(group: String) -> void:
	tag_group_polled.emit(group)


func _on_backend_error() -> void:
	_last_error = str(_backend.call("get_comms_error")) if _backend != null and _backend.has_method("get_comms_error") else "OIP Comms reported an error."
	_connected = false
	connection_status_changed.emit(false)
	comms_error.emit()
	_log(_last_error, LogLevel.ERROR)


func _set_error(message: String) -> void:
	_last_error = message
	_log(message, LogLevel.ERROR)


func _log(message: String, level: int) -> void:
	if _logging_enabled or level != LogLevel.DEBUG:
		log_message.emit(message, level)
