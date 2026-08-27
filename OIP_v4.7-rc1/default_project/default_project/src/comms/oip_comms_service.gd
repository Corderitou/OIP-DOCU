@tool
extends Node

const TAG_GROUPS_FILE: String = "res://oip_data/tag_groups.cfg"
const SETTINGS_FILE: String = "res://oip_data/comms_settings.cfg"

var _comms: Object
var _sim: Object


func _ready() -> void:
	_comms = Engine.get_singleton("OIPComms")
	_sim = Engine.get_singleton("Simulation")
	if not Engine.is_editor_hint():
		bootstrap()


func _exit_tree() -> void:
	if _sim != null and _sim.started.is_connected(_on_simulation_started):
		_sim.started.disconnect(_on_simulation_started)
	if _sim != null and _sim.stopped.is_connected(_on_simulation_ended):
		_sim.stopped.disconnect(_on_simulation_ended)
	if _comms != null and _comms.comms_error.is_connected(_on_comms_error):
		_comms.comms_error.disconnect(_on_comms_error)


func bootstrap() -> void:
	_apply_settings()
	register_tag_groups()

	if _sim != null:
		if not _sim.started.is_connected(_on_simulation_started):
			_sim.started.connect(_on_simulation_started)
		if not _sim.stopped.is_connected(_on_simulation_ended):
			_sim.stopped.connect(_on_simulation_ended, CONNECT_DEFERRED)
	if _comms != null:
		if not _comms.comms_error.is_connected(_on_comms_error):
			_comms.comms_error.connect(_on_comms_error)


func register_tag_groups() -> void:
	if _comms == null:
		return
	_comms.clear_tag_groups()
	for group: Dictionary in _load_tag_groups():
		var group_name: String = group.name
		var polling_rate: String = group.polling_rate

		var pt_num: String = group.protocol
		var pt: String = ""
		if pt_num == "0": pt = "ab_eip"
		elif pt_num == "1": pt = "modbus_tcp"
		elif pt_num == "2": pt = "opc_ua"
		elif pt_num == "3": pt = "s7"
		elif pt_num == "4": pt = "ads"
		elif pt_num == "5": pt = "rtde"
		elif pt_num == "6": pt = "mqtt"
		elif pt_num == "7": pt = "soft_plc"

		var gateway: String = group.gateway
		var path: String = group.path
		var cpu: String = group.cpu
		_comms.register_tag_group(group_name, int(polling_rate), pt, gateway, path, cpu)
	_comms.tag_groups_registered.emit()


func _load_tag_groups() -> Array:
	var groups: Array = []
	var config: ConfigFile = ConfigFile.new()
	if config.load(TAG_GROUPS_FILE) != OK:
		return groups

	var group_count: int = config.get_value("info", "group_count", 0)
	for i: int in range(group_count):
		var section: String = "group_" + str(i)
		groups.append({
			"name": config.get_value(section, "name", "TagGroup" + str(i)),
			"polling_rate": config.get_value(section, "polling_rate", "100"),
			"protocol": config.get_value(section, "protocol", "0"),
			"gateway": config.get_value(section, "gateway", "localhost"),
			"path": config.get_value(section, "path", "1,0"),
			"cpu": config.get_value(section, "cpu", "ControlLogix"),
		})
	return groups


func _apply_settings() -> void:
	if _comms == null:
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return
	_comms.set_enable_comms(config.get_value("settings", "enable_comms", false))


func _on_simulation_started() -> void:
	if _comms != null:
		_comms.set_sim_running(true)


func _on_simulation_ended() -> void:
	if _comms != null:
		_comms.set_sim_running(false)


func _on_comms_error() -> void:
	if _sim != null:
		_sim.stop()
