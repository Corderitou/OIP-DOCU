class_name CommsPanel
extends PanelContainer

signal back_pressed

const CATEGORY_ORDER: Array[String] = [
	"Conveyors", "Devices", "Actuators", "Robots", "Other"
]

const NODE_CATEGORY_MAP: Dictionary = {
	"BeltConveyorAssembly": "Conveyors", "RollerConveyorAssembly": "Conveyors",
	"CurvedBeltConveyorAssembly": "Conveyors", "CurvedRollerConveyorAssembly": "Conveyors",
	"BeltSpurConveyorAssembly": "Conveyors", "RollerSpurConveyorAssembly": "Conveyors",
	"BeltConveyor": "Conveyors", "RollerConveyor": "Conveyors",
	"CurvedBeltConveyor": "Conveyors", "CurvedRollerConveyor": "Conveyors",
	"BeltSpurConveyor": "Conveyors", "RollerSpurConveyor": "Conveyors",
	"ChainTransfer": "Conveyors",
	"DiffuseSensor": "Devices", "LaserSensor": "Devices", "ColorSensor": "Devices",
	"PushButton": "Devices", "StackLight": "Devices",
	"BladeStop": "Actuators", "Diverter": "Actuators",
	"SixAxisRobot": "Robots", "Gantry": "Robots",
}

const NODE_COMMS_FIELDS: Dictionary = {
	"BeltConveyorAssembly": ["speed_tag_name", "running_tag_name"],
	"RollerConveyorAssembly": ["speed_tag_name", "running_tag_name"],
	"CurvedBeltConveyorAssembly": ["speed_tag_name", "running_tag_name"],
	"CurvedRollerConveyorAssembly": ["speed_tag_name", "running_tag_name"],
	"BeltSpurConveyorAssembly": ["speed_tag_name", "running_tag_name"],
	"RollerSpurConveyorAssembly": ["speed_tag_name", "running_tag_name"],
	"BeltConveyor": ["speed_tag_name", "running_tag_name"],
	"RollerConveyor": ["speed_tag_name", "running_tag_name"],
	"CurvedBeltConveyor": ["speed_tag_name", "running_tag_name"],
	"CurvedRollerConveyor": ["speed_tag_name", "running_tag_name"],
	"BeltSpurConveyor": ["speed_tag_name", "running_tag_name"],
	"RollerSpurConveyor": ["speed_tag_name", "running_tag_name"],
	"ChainTransfer": ["speed_tag_name", "popup_tag_name"],
	"BladeStop": ["tag_name"],
	"Diverter": ["tag_name"],
	"DiffuseSensor": ["tag_name"],
	"LaserSensor": ["tag_name"],
	"ColorSensor": ["tag_name"],
	"PushButton": ["pushbutton_tag_name", "lamp_tag_name"],
	"StackLight": ["tag_name"],
	"SixAxisRobot": ["command_tag", "execute_tag", "done_tag", "vacuum_tag"],
	"Gantry": ["command_tag", "execute_tag", "done_tag", "vacuum_tag"],
}

const FIELD_LABELS: Dictionary = {
	"tag_name": "Tag",
	"speed_tag_name": "Speed Tag",
	"running_tag_name": "Running Tag",
	"popup_tag_name": "Popup Tag",
	"pushbutton_tag_name": "Pushbutton Tag",
	"lamp_tag_name": "Lamp Tag",
	"command_tag": "Command",
	"execute_tag": "Execute",
	"done_tag": "Done",
	"vacuum_tag": "Vacuum",
}

const SHARED_TAG_GROUP_FIELDS: Array[String] = ["command_tag", "execute_tag", "done_tag", "vacuum_tag"]

const PROTO_NAMES: Array[String] = ["Modbus TCP", "EtherNet/IP", "OPC UA", "Siemens S7"]
const PROTO_IDS: Array[String] = ["modbus_tcp", "ab_eip", "opc_ua", "s7"]
const PROTO_MODBUS := 0
const PROTO_AB_EIP := 1
const PROTO_OPC_UA := 2
const PROTO_S7 := 3

const CPU_OPTIONS: Array[String] = [
	"ControlLogix", "CompactLogix", "Micro800", "MicroLogix",
	"SLC500", "PLC5", "LogixPccc", "Omron-NJNX",
]

const DEFAULT_OPC_ENDPOINT := "opc.tcp://localhost:4840"

var _enable_checkbox: CheckBox
var _enable_logging: CheckBox
var _tag_groups_container: VBoxContainer
var _items_container: VBoxContainer
var _connection_dot: ColorRect
var _connection_label: Label
var _console: RichTextLabel

var _tag_groups: Array[Dictionary] = []
var _scene_root: Node3D = null
var _expanded_nodes: Dictionary = {}
var _console_lines: Array[String] = []
const MAX_CONSOLE_LINES := 200

## Live activity indicators per tag row: {node, field, group_prop, dot, last_ms}
var _tag_activity: Array[Dictionary] = []
const ACTIVITY_HOLD_MS := 700
const COL_ACTIVITY_IDLE := Color("#30363d")
const COL_ACTIVITY_WRITE := Color("#3fb950")
const COL_ACTIVITY_READ := Color("#58a6ff")

var _current_selection: Array[Node3D] = []


func _ready() -> void:
	_build_ui()
	_connect_comms_signals()
	_connect_simulation_signals()
	_update_connection_dot(CommsHub.is_comms_connected() if CommsHub.has_method("is_comms_connected") else false)


func _connect_simulation_signals() -> void:
	# The native backend only polls tag groups while the simulation is running.
	# Nothing else in the runtime editor forwards this state, so do it here.
	RuntimeSimulationBus.simulation_started.connect(func():
		if CommsHub.has_method("set_sim_running"):
			CommsHub.set_sim_running(true)
			_push_console("[color=#3fb950]INFO[/color] Simulation started — tag polling active")
	)
	RuntimeSimulationBus.simulation_stopped.connect(func():
		if CommsHub.has_method("set_sim_running"):
			CommsHub.set_sim_running(false)
			_push_console("[color=#8b949e]INFO[/color] Simulation stopped — tag polling paused")
	)


func _connect_comms_signals() -> void:
	if not is_instance_valid(CommsHub):
		return
	if CommsHub.has_signal("connection_status_changed"):
		CommsHub.connect("connection_status_changed", _on_connection_changed)
	if CommsHub.has_signal("log_message"):
		CommsHub.connect("log_message", _on_log_message)
	if CommsHub.has_signal("tag_read"):
		CommsHub.connect("tag_read", _on_tag_read)
	if CommsHub.has_signal("tag_written"):
		CommsHub.connect("tag_written", _on_tag_written)


func _on_connection_changed(connected: bool) -> void:
	_update_connection_dot(connected)


func _on_log_message(text: String, level: int) -> void:
	var prefix := ""
	match level:
		0: prefix = "[color=#3fb950]INFO[/color]"
		1: prefix = "[color=#f0c000]WARN[/color]"
		2: prefix = "[color=#ff6b6b]ERROR[/color]"
		3: prefix = "[color=#8b949e]DEBUG[/color]"
	_push_console("%s  %s" % [prefix, text])


func _on_tag_read(group: String, tag: String, value: Variant) -> void:
	var val_str := ""
	if value is float:
		val_str = "%.2f" % value
	else:
		val_str = str(value)
	var path_info := _get_group_path_info(group)
	_push_console("[color=#58a6ff]READ[/color] [%s] %s %s = [color=#e6edf3]%s[/color]" % [group, tag, path_info, val_str])
	_flash_tag_activity(group, tag, COL_ACTIVITY_READ)


func _on_tag_written(group: String, tag: String, value: Variant) -> void:
	var val_str := ""
	if value is float:
		val_str = "%.2f" % value
	else:
		val_str = str(value)
	var path_info := _get_group_path_info(group)
	_push_console("[color=#f97583]WRITE[/color] [%s] %s %s = [color=#e6edf3]%s[/color]" % [group, tag, path_info, val_str])
	_flash_tag_activity(group, tag, COL_ACTIVITY_WRITE)


## Light up the activity dot of every tag row bound to (group, tag).
func _flash_tag_activity(group: String, tag: String, color: Color) -> void:
	var now := Time.get_ticks_msec()
	for entry in _tag_activity:
		var node: Node3D = entry.get("node")
		var dot: ColorRect = entry.get("dot")
		if not is_instance_valid(node) or not is_instance_valid(dot):
			continue
		if str(node.get(entry.get("group_prop", ""))) != group:
			continue
		if str(node.get(entry.get("field", ""))) != tag:
			continue
		dot.color = color
		entry["last_ms"] = now
	set_process(true)


func _process(_delta: float) -> void:
	# Dim activity dots that haven't seen traffic recently; stop when all idle.
	var now := Time.get_ticks_msec()
	var any_active := false
	for entry in _tag_activity:
		var dot: ColorRect = entry.get("dot")
		if not is_instance_valid(dot):
			continue
		var last: int = int(entry.get("last_ms", 0))
		if last > 0 and now - last > ACTIVITY_HOLD_MS:
			dot.color = COL_ACTIVITY_IDLE
			entry["last_ms"] = 0
		elif last > 0:
			any_active = true
	if not any_active:
		set_process(false)


func _get_group_path_info(group_name: String) -> String:
	for g in _tag_groups:
		if g.get("name", "") == group_name:
			var path: String = g.get("path", "")
			if path.is_empty():
				return ""
			return "(%s)" % path
	return ""


func _push_console(bbcode: String) -> void:
	if not is_instance_valid(_console):
		return
	var timestamp := Time.get_time_string_from_system()
	var line := "[color=#8b949e]%s[/color] %s" % [timestamp, bbcode]
	_console_lines.append(line)
	if _console_lines.size() > MAX_CONSOLE_LINES:
		_console_lines = _console_lines.slice(-MAX_CONSOLE_LINES)
	_console.clear()
	for l in _console_lines:
		_console.append_text(l + "\n")


func _update_connection_dot(connected: bool) -> void:
	if is_instance_valid(_connection_dot):
		_connection_dot.color = Color("#3fb950") if connected else Color("#f0c000") if CommsHub.get_enable_comms() else Color("#ff6b6b")
	if is_instance_valid(_connection_label):
		if connected:
			_connection_label.text = "Verified"
			_connection_label.add_theme_color_override("font_color", Color("#3fb950"))
		elif CommsHub.get_enable_comms():
			_connection_label.text = "Enabled (unverified)"
			_connection_label.add_theme_color_override("font_color", Color("#f0c000"))
		else:
			_connection_label.text = "Disconnected"
			_connection_label.add_theme_color_override("font_color", Color("#ff6b6b"))


func set_scene_root(root: Node3D) -> void:
	_scene_root = root
	refresh()


func set_selection(selected: Array[Node3D]) -> void:
	_current_selection = selected
	if selected.size() == 1:
		var node: Node3D = selected[0]
		var key := str(node.get_instance_id())
		if not _expanded_nodes.has(key):
			_expanded_nodes[key] = true
			_rebuild_items()
		_scroll_to_node(node)


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#161b22")
	sb.border_color = Color("#30363d")
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)

	# Main split: top content (scrollable) + bottom console
	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.name = "MainVBox"
	add_child(main_vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 3.0
	scroll.clip_contents = false
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.name = "ContentVBox"
	vbox.clip_contents = false
	scroll.add_child(vbox)

	# Header with back button, title, and connection dot
	var header_hbox := HBoxContainer.new()
	header_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_hbox)

	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.pressed.connect(func(): back_pressed.emit())
	header_hbox.add_child(back_btn)

	var header := Label.new()
	header.text = "COMMS"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color("#e6edf3"))
	header_hbox.add_child(header)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_connection_label = Label.new()
	_connection_label.text = "Disconnected"
	_connection_label.add_theme_font_size_override("font_size", 12)
	_connection_label.add_theme_color_override("font_color", Color("#ff6b6b"))
	header_hbox.add_child(_connection_label)

	_connection_dot = ColorRect.new()
	_connection_dot.custom_minimum_size = Vector2(10, 10)
	_connection_dot.color = Color("#ff6b6b")
	header_hbox.add_child(_connection_dot)

	vbox.add_child(_hsep())

	# Global options
	var opt_hbox := HBoxContainer.new()
	vbox.add_child(opt_hbox)

	_enable_checkbox = CheckBox.new()
	_enable_checkbox.text = "Enable Comms"
	_enable_checkbox.tooltip_text = "Enables tag polling against the configured tag groups.\nNote: this alone does not verify the server — use Test OPC UA."
	_enable_checkbox.button_pressed = CommsHub.get_enable_comms()
	_enable_checkbox.toggled.connect(func(on: bool):
		if on:
			# Make sure the backend has the current group list before it starts polling.
			_register_tag_groups()
		CommsHub.set_enable_comms(on)
		CommsHub.enable_comms_changed.emit()
		_update_connection_dot(CommsHub.is_comms_connected() if CommsHub.has_method("is_comms_connected") else false)
	)
	opt_hbox.add_child(_enable_checkbox)

	var test_opc_btn := Button.new()
	test_opc_btn.text = "Test OPC UA"
	test_opc_btn.tooltip_text = "Connects to every OPC UA endpoint configured below. This does not change tags or values."
	test_opc_btn.custom_minimum_size = Vector2(100, 26)
	test_opc_btn.pressed.connect(_on_test_opc_ua)
	opt_hbox.add_child(test_opc_btn)

	_enable_logging = CheckBox.new()
	_enable_logging.text = "Logging"
	_enable_logging.button_pressed = false
	_enable_logging.toggled.connect(func(on: bool):
		CommsHub.set_enable_log(on) if CommsHub.has_method("set_enable_log") else null
	)
	opt_hbox.add_child(_enable_logging)

	vbox.add_child(_hsep())

	# Tag Groups section
	var tg_header := HBoxContainer.new()
	vbox.add_child(tg_header)

	var tg_label := Label.new()
	tg_label.text = "Tag Groups"
	tg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tg_label.add_theme_color_override("font_color", Color("#8b949e"))
	tg_header.add_child(tg_label)

	var tg_add_btn := Button.new()
	tg_add_btn.text = "+ Add"
	tg_add_btn.custom_minimum_size = Vector2(60, 26)
	tg_add_btn.pressed.connect(_on_add_group)
	tg_header.add_child(tg_add_btn)

	_tag_groups_container = VBoxContainer.new()
	_tag_groups_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tag_groups_container)

	vbox.add_child(_hsep())

	# Items header
	var items_label := Label.new()
	items_label.text = "Scene Items"
	items_label.add_theme_color_override("font_color", Color("#8b949e"))
	vbox.add_child(items_label)

	_items_container = VBoxContainer.new()
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_container.name = "ItemsContainer"
	vbox.add_child(_items_container)

	vbox.add_child(_hsep())

	# Save/Load
	var btn_hbox := HBoxContainer.new()
	vbox.add_child(btn_hbox)

	var save_btn := Button.new()
	save_btn.text = "Save Config"
	save_btn.custom_minimum_size = Vector2(100, 28)
	save_btn.pressed.connect(_on_save)
	btn_hbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Config"
	load_btn.custom_minimum_size = Vector2(100, 28)
	load_btn.pressed.connect(_on_load)
	btn_hbox.add_child(load_btn)

	var node_red_btn := Button.new()
	node_red_btn.text = "Cargar a Node-RED"
	node_red_btn.tooltip_text = "Agrega los tags OPC UA configurados al servidor OPC UA de un flujo de Node-RED (node-red-simple-opcua)"
	node_red_btn.custom_minimum_size = Vector2(140, 28)
	node_red_btn.pressed.connect(_on_export_node_red)
	btn_hbox.add_child(node_red_btn)

	_load_config()
	_rebuild_tag_groups()
	_register_tag_groups()

	# ── Console ─────────────────────────────────────────────
	var console_sep := HSeparator.new()
	console_sep.custom_minimum_size.y = 6
	main_vbox.add_child(console_sep)

	var console_header := HBoxContainer.new()
	main_vbox.add_child(console_header)

	var console_title := Label.new()
	console_title.text = "Console"
	console_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_title.add_theme_font_size_override("font_size", 12)
	console_title.add_theme_color_override("font_color", Color("#8b949e"))
	console_header.add_child(console_title)

	var console_clear_btn := Button.new()
	console_clear_btn.text = "Clear"
	console_clear_btn.custom_minimum_size = Vector2(50, 22)
	console_clear_btn.add_theme_font_size_override("font_size", 11)
	console_clear_btn.pressed.connect(func():
		_console_lines.clear()
		if is_instance_valid(_console):
			_console.clear()
	)
	console_header.add_child(console_clear_btn)

	_console = RichTextLabel.new()
	_console.bbcode_enabled = true
	_console.fit_content = false
	_console.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console.size_flags_stretch_ratio = 1.0
	_console.custom_minimum_size.y = 120
	_console.scroll_following = true
	_console.scroll_active = true
	_console.add_theme_font_size_override("normal_font_size", 11)
	_console.add_theme_color_override("default_color", Color("#e6edf3"))
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#0d1117")
	csb.border_color = Color("#30363d")
	csb.set_border_width_all(1)
	csb.corner_radius_top_left = 3
	csb.corner_radius_top_right = 3
	csb.corner_radius_bottom_left = 3
	csb.corner_radius_bottom_right = 3
	csb.set_content_margin_all(6)
	_console.add_theme_stylebox_override("panel", csb)
	main_vbox.add_child(_console)

	_push_console("[color=#3fb950]Console ready[/color]")


func _hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


# ── Tag Groups ──────────────────────────────────────────

func _on_add_group() -> void:
	var idx := _tag_groups.size()
	var group: Dictionary = {
		"name": "Group" + str(idx + 1),
		"protocol": PROTO_OPC_UA,
		"gateway": DEFAULT_OPC_ENDPOINT,
		"path": "",
		"cpu": 0,
		"polling_rate": 100,
	}
	_tag_groups.append(group)
	_rebuild_tag_groups()
	_register_tag_groups()


func _default_gateway_for_protocol(proto: int) -> String:
	match proto:
		PROTO_OPC_UA: return DEFAULT_OPC_ENDPOINT
		PROTO_MODBUS: return "localhost"
		PROTO_AB_EIP: return "localhost"
		PROTO_S7: return ""
	return ""


func _default_path_for_protocol(proto: int) -> String:
	match proto:
		PROTO_MODBUS: return "1"
		PROTO_AB_EIP: return "1,0"
	return ""


func _rebuild_tag_groups() -> void:
	for child in _tag_groups_container.get_children():
		child.queue_free()

	if _tag_groups.is_empty():
		var hint := Label.new()
		hint.text = "No tag groups. Click + Add to create one (e.g. an OPC UA server)."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color("#8b949e"))
		_tag_groups_container.add_child(hint)
		return

	for i in range(_tag_groups.size()):
		var group: Dictionary = _tag_groups[i]
		var vbox_row := VBoxContainer.new()
		vbox_row.add_theme_constant_override("separation", 2)
		_tag_groups_container.add_child(vbox_row)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		vbox_row.add_child(hbox)

		var idx := i
		var proto_idx: int = group.get("protocol", 0)

		var name_edit := LineEdit.new()
		name_edit.text = group.get("name", "")
		name_edit.placeholder_text = "Name"
		name_edit.tooltip_text = "Tag group name. Scene items reference this name to know where their tags live."
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.custom_minimum_size.x = 80
		name_edit.text_changed.connect(func(t: String): _tag_groups[idx]["name"] = t)
		name_edit.focus_exited.connect(_register_tag_groups)
		hbox.add_child(name_edit)

		var proto_option := OptionButton.new()
		for p in PROTO_NAMES:
			proto_option.add_item(p)
		proto_option.selected = proto_idx if proto_idx < PROTO_NAMES.size() else 0
		proto_option.custom_minimum_size = Vector2(110, 24)
		proto_option.item_selected.connect(func(sel: int):
			_tag_groups[idx]["protocol"] = sel
			_tag_groups[idx]["gateway"] = _default_gateway_for_protocol(sel)
			_tag_groups[idx]["path"] = _default_path_for_protocol(sel)
			_rebuild_tag_groups()
			_register_tag_groups()
		)
		hbox.add_child(proto_option)

		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.tooltip_text = "Remove this tag group"
		del_btn.custom_minimum_size = Vector2(24, 24)
		del_btn.pressed.connect(func(): _on_remove_group(idx))
		hbox.add_child(del_btn)

		# Second row: protocol-specific connection fields
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 4)
		vbox_row.add_child(row2)

		var gw_label := Label.new()
		match proto_idx:
			PROTO_OPC_UA: gw_label.text = "  Endpoint"
			PROTO_S7: gw_label.text = "  PLC IP"
			_: gw_label.text = "  Gateway"
		gw_label.custom_minimum_size.x = 62
		gw_label.add_theme_font_size_override("font_size", 11)
		gw_label.add_theme_color_override("font_color", Color("#8b949e"))
		row2.add_child(gw_label)

		var gw_edit := LineEdit.new()
		gw_edit.text = group.get("gateway", "")
		match proto_idx:
			PROTO_OPC_UA:
				gw_edit.placeholder_text = DEFAULT_OPC_ENDPOINT
				gw_edit.tooltip_text = "OPC UA server endpoint URL.\nExample: opc.tcp://192.168.1.10:4840"
			PROTO_S7:
				gw_edit.placeholder_text = "192.168.0.1"
				gw_edit.tooltip_text = "IP address of the Siemens PLC"
			_:
				gw_edit.placeholder_text = "IP or hostname"
				gw_edit.tooltip_text = "IP address or hostname of the PLC/gateway"
		gw_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gw_edit.custom_minimum_size.x = 140
		gw_edit.text_changed.connect(func(t: String): _tag_groups[idx]["gateway"] = t)
		gw_edit.focus_exited.connect(_register_tag_groups)
		row2.add_child(gw_edit)

		# Path / Unit ID (Modbus + EtherNet/IP only — OPC UA and S7 don't use it)
		if proto_idx == PROTO_MODBUS or proto_idx == PROTO_AB_EIP:
			var path_label := Label.new()
			path_label.text = "Unit ID" if proto_idx == PROTO_MODBUS else "Path"
			path_label.add_theme_font_size_override("font_size", 11)
			path_label.add_theme_color_override("font_color", Color("#8b949e"))
			row2.add_child(path_label)

			var path_edit := LineEdit.new()
			path_edit.text = str(group.get("path", ""))
			path_edit.placeholder_text = "1" if proto_idx == PROTO_MODBUS else "1,0"
			path_edit.custom_minimum_size.x = 50
			path_edit.text_changed.connect(func(t: String): _tag_groups[idx]["path"] = t)
			path_edit.focus_exited.connect(_register_tag_groups)
			row2.add_child(path_edit)

		# CPU type (EtherNet/IP only)
		if proto_idx == PROTO_AB_EIP:
			var cpu_label := Label.new()
			cpu_label.text = "CPU"
			cpu_label.add_theme_font_size_override("font_size", 11)
			cpu_label.add_theme_color_override("font_color", Color("#8b949e"))
			row2.add_child(cpu_label)

			var cpu_option := OptionButton.new()
			for c in CPU_OPTIONS:
				cpu_option.add_item(c)
			var cur_cpu: int = int(group.get("cpu", 0))
			cpu_option.selected = cur_cpu if cur_cpu < CPU_OPTIONS.size() else 0
			cpu_option.custom_minimum_size = Vector2(110, 24)
			cpu_option.item_selected.connect(func(sel: int):
				_tag_groups[idx]["cpu"] = sel
				_register_tag_groups()
			)
			row2.add_child(cpu_option)

		var poll_label := Label.new()
		poll_label.text = "Poll ms"
		poll_label.add_theme_font_size_override("font_size", 11)
		poll_label.add_theme_color_override("font_color", Color("#8b949e"))
		row2.add_child(poll_label)

		var poll_edit := LineEdit.new()
		poll_edit.text = str(group.get("polling_rate", 100))
		poll_edit.placeholder_text = "100"
		poll_edit.tooltip_text = "How often tags in this group are read/written (milliseconds)"
		poll_edit.custom_minimum_size.x = 50
		poll_edit.text_changed.connect(func(t: String): _tag_groups[idx]["polling_rate"] = int(t) if t.is_valid_int() else 100)
		poll_edit.focus_exited.connect(_register_tag_groups)
		row2.add_child(poll_edit)

		# Per-group connection test (OPC UA)
		if proto_idx == PROTO_OPC_UA:
			var test_btn := Button.new()
			test_btn.text = "Test"
			test_btn.tooltip_text = "Try to open a session against this endpoint"
			test_btn.custom_minimum_size = Vector2(48, 24)
			test_btn.pressed.connect(func(): _test_single_group(idx))
			row2.add_child(test_btn)


func _on_remove_group(idx: int) -> void:
	if idx >= 0 and idx < _tag_groups.size():
		_tag_groups.remove_at(idx)
		_rebuild_tag_groups()
		_register_tag_groups()


func _cpu_string_of_group(g: Dictionary) -> String:
	# Config stores the CPU as index into CPU_OPTIONS; old configs may hold the name itself.
	var cpu_val: Variant = g.get("cpu", 0)
	if cpu_val is String and not str(cpu_val).is_valid_int():
		return str(cpu_val)
	var cpu_idx := int(cpu_val)
	return CPU_OPTIONS[cpu_idx] if cpu_idx >= 0 and cpu_idx < CPU_OPTIONS.size() else CPU_OPTIONS[0]


func _register_tag_groups() -> void:
	CommsHub.clear_tag_groups() if CommsHub.has_method("clear_tag_groups") else null
	for g in _tag_groups:
		var proto: int = g.get("protocol", 0)
		var proto_str: String = PROTO_IDS[proto] if proto < PROTO_IDS.size() else "modbus_tcp"
		var gateway: String = str(g.get("gateway", "")).strip_edges()
		if proto == PROTO_OPC_UA and not gateway.is_empty() and not gateway.begins_with("opc.tcp://"):
			_push_console("[color=#f0c000]WARN[/color] [%s] OPC UA endpoint should start with opc.tcp:// — got \"%s\"" % [g.get("name", ""), gateway])
		CommsHub.register_tag_group(
			g.get("name", ""),
			g.get("polling_rate", 100),
			proto_str,
			gateway,
			str(g.get("path", "")),
			_cpu_string_of_group(g)
		) if CommsHub.has_method("register_tag_group") else null
	CommsHub.finish_registering_tag_groups() if CommsHub.has_method("finish_registering_tag_groups") else null


func _test_single_group(idx: int) -> void:
	if idx < 0 or idx >= _tag_groups.size():
		return
	_register_tag_groups()
	var group: Dictionary = _tag_groups[idx]
	var name: String = str(group.get("name", "OPC UA"))
	var endpoint: String = str(group.get("gateway", "")).strip_edges()
	if not CommsHub.has_method("test_opc_ua"):
		_push_console("[color=#ff6b6b]ERROR[/color] OPC UA test is unavailable because OIP Comms is not loaded.")
		RuntimeEditorToaster.push_toast("OIP Comms GDExtension unavailable", RuntimeEditorToaster.SEVERITY_ERROR)
		return
	_push_console("[color=#8b949e]INFO[/color] Testing [%s] %s ..." % [name, endpoint])
	var result: Dictionary = CommsHub.test_opc_ua(endpoint)
	var message: String = str(result.get("message", "Unknown OPC UA test result"))
	if result.get("ok", false):
		_push_console("[color=#3fb950]TEST OK[/color] [%s] %s" % [name, message])
		RuntimeEditorToaster.push_toast("[%s] Connected" % name, RuntimeEditorToaster.SEVERITY_INFO)
	else:
		_push_console("[color=#ff6b6b]TEST FAILED[/color] [%s] %s" % [name, message])
		RuntimeEditorToaster.push_toast("[%s] Connection failed" % name, RuntimeEditorToaster.SEVERITY_ERROR)


func _on_test_opc_ua() -> void:
	_register_tag_groups()
	var opc_groups: Array[Dictionary] = []
	for group in _tag_groups:
		if int(group.get("protocol", 0)) == PROTO_OPC_UA:
			opc_groups.append(group)
	if opc_groups.is_empty():
		_push_console("[color=#f0c000]WARN[/color] Add an OPC UA tag group before testing.")
		RuntimeEditorToaster.push_toast("Add an OPC UA tag group first", RuntimeEditorToaster.SEVERITY_ERROR)
		return
	if not CommsHub.has_method("test_opc_ua"):
		_push_console("[color=#ff6b6b]ERROR[/color] OPC UA test is unavailable because OIP Comms is not loaded.")
		RuntimeEditorToaster.push_toast("OIP Comms GDExtension unavailable", RuntimeEditorToaster.SEVERITY_ERROR)
		return

	var failures := 0
	for group in opc_groups:
		var name: String = str(group.get("name", "OPC UA"))
		var endpoint: String = str(group.get("gateway", "")).strip_edges()
		var result: Dictionary = CommsHub.test_opc_ua(endpoint)
		var message: String = str(result.get("message", "Unknown OPC UA test result"))
		if result.get("ok", false):
			_push_console("[color=#3fb950]TEST OK[/color] [%s] %s" % [name, message])
		else:
			failures += 1
			_push_console("[color=#ff6b6b]TEST FAILED[/color] [%s] %s" % [name, message])

	_update_connection_dot(failures == 0)
	var summary := "OPC UA test passed for %d endpoint(s)" % opc_groups.size() if failures == 0 else "OPC UA test failed for %d of %d endpoint(s)" % [failures, opc_groups.size()]
	RuntimeEditorToaster.push_toast(summary, RuntimeEditorToaster.SEVERITY_INFO if failures == 0 else RuntimeEditorToaster.SEVERITY_ERROR)


func get_tag_group_names() -> Array[String]:
	var names: Array[String] = []
	for g in _tag_groups:
		names.append(g.get("name", ""))
	return names


# ── Scene Items ─────────────────────────────────────────

func refresh() -> void:
	_rebuild_items()


func _rebuild_items() -> void:
	_tag_activity.clear()
	set_process(false)
	for child in _items_container.get_children():
		child.queue_free()

	if not _scene_root:
		var placeholder := Label.new()
		placeholder.text = "No scene loaded"
		placeholder.add_theme_color_override("font_color", Color("#8b949e"))
		_items_container.add_child(placeholder)
		return

	var categories: Dictionary = {}
	for child in _scene_root.get_children():
		if not child is Node3D:
			continue
		if child.owner != _scene_root:
			continue
		var type_name := SceneRegistry.get_type_for_node(child)
		if type_name.is_empty() or not NODE_COMMS_FIELDS.has(type_name):
			continue
		var cat: String = NODE_CATEGORY_MAP.get(type_name, "Other")
		if not categories.has(cat):
			categories[cat] = []
		categories[cat].append(child)

	var total := 0
	for cat in CATEGORY_ORDER:
		if not categories.has(cat):
			continue
		var nodes: Array = categories[cat]
		total += nodes.size()

		var cat_header := Button.new()
		cat_header.text = "%s (%d)" % [cat, nodes.size()]
		cat_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cat_header.toggle_mode = true
		cat_header.button_pressed = true
		cat_header.add_theme_font_size_override("font_size", 13)
		cat_header.add_theme_color_override("font_color", Color("#58a6ff"))
		cat_header.add_theme_color_override("font_hover_color", Color("#79b8ff"))
		var cat_key := "_cat_" + cat
		cat_header.toggled.connect(func(on: bool):
			_expanded_nodes[cat_key] = on
			_set_cat_visible(cat, on)
		)
		_items_container.add_child(cat_header)

		var cat_container := VBoxContainer.new()
		cat_container.name = "Cat_" + cat
		_items_container.add_child(cat_container)

		for node in nodes:
			cat_container.add_child(_build_node_section(node))

	# Summary
	if total == 0:
		var empty := Label.new()
		empty.text = "No comms-enabled items in scene"
		empty.add_theme_color_override("font_color", Color("#8b949e"))
		_items_container.add_child(empty)


func _set_cat_visible(cat: String, visible: bool) -> void:
	var container := _items_container.get_node_or_null("Cat_" + cat)
	if container:
		container.visible = visible


func _build_node_section(node: Node3D) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2128")
	sb.border_color = Color("#30363d")
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Node header (toggle expand)
	var type_name := SceneRegistry.get_type_for_node(node)
	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	var expand_btn := Button.new()
	expand_btn.text = "> " + node.name
	expand_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	expand_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expand_btn.add_theme_font_size_override("font_size", 13)
	expand_btn.add_theme_color_override("font_color", Color("#e6edf3"))
	header_hbox.add_child(expand_btn)

	# Node type label
	var type_label := Label.new()
	type_label.text = type_name
	type_label.add_theme_font_size_override("font_size", 11)
	type_label.add_theme_color_override("font_color", Color("#8b949e"))
	header_hbox.add_child(type_label)

	# Content (hidden by default)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.visible = false
	content.add_theme_constant_override("separation", 3)
	vbox.add_child(content)

	var node_id := str(node.get_instance_id())
	var node_name := node.name
	var is_expanded: bool = _expanded_nodes.get(node_id, false)
	content.visible = is_expanded
	expand_btn.text = ("v " if is_expanded else "> ") + node_name

	expand_btn.pressed.connect(func():
		var now_visible := not content.visible
		content.visible = now_visible
		expand_btn.text = ("v " if now_visible else "> ") + node_name
		_expanded_nodes[node_id] = now_visible
	)

	# Enable comms checkbox
	if node.get("enable_comms") != null:
		var enable_row := HBoxContainer.new()
		content.add_child(enable_row)
		var cb := CheckBox.new()
		cb.text = "Enable Comms"
		cb.button_pressed = node.get("enable_comms") == true
		cb.toggled.connect(func(on: bool):
			if not is_instance_valid(node): return
			node.set("enable_comms", on)
			node.notify_property_list_changed() if node.has_method("notify_property_list_changed") else null
		)
		enable_row.add_child(cb)

	# Tag fields
	var type_fields: Array = NODE_COMMS_FIELDS.get(type_name, [])
	for field_name in type_fields:
		var field_row := _build_tag_field(node, str(field_name))
		content.add_child(field_row)

	return panel


func _protocol_of_group(group_name: String) -> int:
	for g in _tag_groups:
		if g.get("name", "") == group_name:
			return int(g.get("protocol", 0))
	return -1


func _tag_placeholder_for_group(group_name: String) -> String:
	match _protocol_of_group(group_name):
		PROTO_OPC_UA: return "ns=2;s=MyVariable"
		PROTO_MODBUS: return "hr0 / co0"
		PROTO_AB_EIP: return "MyTag"
		PROTO_S7: return "DB1.DBX0.0"
	return "tag name"


func _build_tag_field(node: Node3D, field_name: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	# Activity dot: lights up blue on READ, green on WRITE for this tag.
	var activity_dot := ColorRect.new()
	activity_dot.custom_minimum_size = Vector2(8, 8)
	activity_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	activity_dot.color = COL_ACTIVITY_IDLE
	activity_dot.tooltip_text = "Lights up when this tag exchanges data:\nblue = read from server, green = written to server"
	hbox.add_child(activity_dot)

	var label := Label.new()
	label.text = FIELD_LABELS.get(field_name, field_name)
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#8b949e"))
	hbox.add_child(label)

	# Tag group dropdown
	var group_name_prop := "tag_group_name" if field_name in SHARED_TAG_GROUP_FIELDS else field_name.replace("_tag_name", "_tag_group_name")
	var groups_prop := field_name.replace("_tag_name", "_tag_groups")
	var group_names := get_tag_group_names()

	var group_option := OptionButton.new()
	group_option.custom_minimum_size.x = 90
	group_option.add_item("(none)", 0)
	for gi in range(group_names.size()):
		group_option.add_item(group_names[gi], gi + 1)

	var current_group: String = node.get(group_name_prop) if node.get(group_name_prop) != null else ""
	var selected_idx := 0
	for gi in range(group_names.size()):
		if group_names[gi] == current_group:
			selected_idx = gi + 1
			break
	group_option.selected = selected_idx
	hbox.add_child(group_option)

	var sep := VSeparator.new()
	sep.custom_minimum_size.x = 2
	hbox.add_child(sep)

	# Tag name input
	var tag_value: String = node.get(field_name) if node.get(field_name) != null else ""
	var tag_edit := LineEdit.new()
	tag_edit.text = tag_value
	tag_edit.placeholder_text = _tag_placeholder_for_group(current_group)
	tag_edit.tooltip_text = "Tag address in the selected group.\nOPC UA: full NodeId (ns=2;s=MyVariable)\nModbus: hr0, co0, ...\nEtherNet/IP: CIP tag name\nS7: DB address"
	tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_edit.custom_minimum_size.x = 100
	tag_edit.text_changed.connect(func(t: String):
		if not is_instance_valid(node): return
		node.set(field_name, t)
	)
	hbox.add_child(tag_edit)

	group_option.item_selected.connect(func(idx: int):
		if not is_instance_valid(node): return
		if idx == 0:
			node.set(group_name_prop, "")
			tag_edit.placeholder_text = "tag name"
		else:
			node.set(group_name_prop, group_names[idx - 1])
			tag_edit.placeholder_text = _tag_placeholder_for_group(group_names[idx - 1])
	)

	_tag_activity.append({
		"node": node,
		"field": field_name,
		"group_prop": group_name_prop,
		"dot": activity_dot,
		"last_ms": 0,
	})

	return hbox


func _scroll_to_node(_node: Node3D) -> void:
	pass


# ── Save / Load ─────────────────────────────────────────

func _on_save() -> void:
	var node_configs := {}
	if _scene_root:
		for child in _scene_root.get_children():
			if not child is Node3D:
				continue
			if child.owner != _scene_root:
				continue
			var type_name := SceneRegistry.get_type_for_node(child)
			if type_name.is_empty():
				continue
			var fields: Array = NODE_COMMS_FIELDS.get(type_name, [])
			if fields.is_empty():
				continue
			var node_data := {}
			for field_name in fields:
				var fn: String = str(field_name)
				var val = child.get(fn)
				if val != null:
					node_data[fn] = val
				var group_prop: String = "tag_group_name" if fn in SHARED_TAG_GROUP_FIELDS else fn.replace("_tag_name", "_tag_group_name")
				var gval = child.get(group_prop)
				if gval != null:
					node_data[group_prop] = gval
			if child.get("enable_comms") != null:
				node_data["enable_comms"] = child.get("enable_comms")
			if not node_data.is_empty():
				node_configs[child.name] = node_data

	var config := {
		"tag_groups": _tag_groups.duplicate(true),
		"node_configs": node_configs,
		"version": 1,
	}
	var path := "user://comms_config.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(config, "\t"))
		file.close()
		var abs_path := ProjectSettings.globalize_path(path)
		_push_console("[color=#3fb950]SAVED[/color] %d tag group(s), %d item(s) → %s" % [_tag_groups.size(), node_configs.size(), abs_path])
		RuntimeEditorToaster.push_toast("Comms config saved", RuntimeEditorToaster.SEVERITY_INFO)
	else:
		_push_console("[color=#ff6b6b]ERROR[/color] Could not write %s" % ProjectSettings.globalize_path(path))
		RuntimeEditorToaster.push_toast("Failed to save comms config", RuntimeEditorToaster.SEVERITY_ERROR)


func _on_load() -> void:
	var path := "user://comms_config.json"
	if not FileAccess.file_exists(path):
		_push_console("[color=#f0c000]WARN[/color] No saved config found at %s" % ProjectSettings.globalize_path(path))
		RuntimeEditorToaster.push_toast("No saved comms config found", RuntimeEditorToaster.SEVERITY_WARNING)
		return
	var applied := _load_config()
	_rebuild_tag_groups()
	_register_tag_groups()
	_rebuild_items()
	refresh()
	_push_console("[color=#3fb950]LOADED[/color] %d tag group(s), applied to %d item(s)" % [_tag_groups.size(), applied])
	RuntimeEditorToaster.push_toast("Comms config loaded", RuntimeEditorToaster.SEVERITY_INFO)


func _load_config() -> int:
	var applied := 0
	var path := "user://comms_config.json"
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return 0
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_push_console("[color=#ff6b6b]ERROR[/color] comms_config.json is not valid JSON: %s" % json.get_error_message())
		return 0
	var data: Variant = json.data
	if not data is Dictionary:
		return 0

	if data.has("tag_groups"):
		_tag_groups.clear()
		for item in data["tag_groups"]:
			if item is Dictionary:
				_tag_groups.append(item.duplicate())

	if data.has("node_configs") and _scene_root:
		var node_configs: Dictionary = data["node_configs"]
		for child in _scene_root.get_children():
			if not child is Node3D:
				continue
			if not node_configs.has(child.name):
				continue
			var node_data: Dictionary = node_configs[child.name]
			for key in node_data:
				child.set(key, node_data[key])
			applied += 1
	return applied


# ── Node-RED export ─────────────────────────────────────

func _on_export_node_red() -> void:
	var tags := NodeRedExporter.collect_tags(_scene_root, _tag_groups)
	if tags.is_empty():
		_push_console("[color=#f0c000]WARN[/color] No hay tags OPC UA configurados en la escena")
		RuntimeEditorToaster.push_toast("No hay tags OPC UA configurados", RuntimeEditorToaster.SEVERITY_WARNING)
		return

	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json;Node-RED Flow"])
	dialog.title = "Seleccionar flujo de Node-RED (flows.json)"
	var node_red_dir := OS.get_environment("USERPROFILE").replace("\\", "/") + "/.node-red"
	if DirAccess.dir_exists_absolute(node_red_dir):
		dialog.current_dir = node_red_dir
	dialog.file_selected.connect(func(path: String): _export_node_red_to(path, tags))
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.file_selected.connect(func(_p: String): dialog.queue_free())
	get_tree().root.add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


func _export_node_red_to(path: String, tags: Array[Dictionary]) -> void:
	if not NodeRedExporter.check_package_installed(path):
		_push_console("[color=#ff6b6b]ERROR[/color] node-red-simple-opcua no está instalado en %s" % path.get_base_dir())
		_push_console("        Instálalo con: npm install %s" % NodeRedExporter.PACKAGE_NAME)
		RuntimeEditorToaster.push_toast("node-red-simple-opcua no está instalado", RuntimeEditorToaster.SEVERITY_ERROR)
		return

	var result := NodeRedExporter.export_to_flow(path, tags)
	if not result["ok"]:
		_push_console("[color=#ff6b6b]ERROR[/color] Node-RED: %s" % result["error"])
		RuntimeEditorToaster.push_toast("Error al exportar a Node-RED", RuntimeEditorToaster.SEVERITY_ERROR)
		return

	_push_console("[color=#3fb950]NODE-RED[/color] %d variable(s) agregadas, %d ya existían → %s" % [result["added"], result["skipped"], path])
	_push_console("        Backup: %s.bak — Reinicia Node-RED o haz deploy para aplicar" % path)
	RuntimeEditorToaster.push_toast("Node-RED: %d tags agregados, %d ya existían" % [result["added"], result["skipped"]], RuntimeEditorToaster.SEVERITY_INFO)
