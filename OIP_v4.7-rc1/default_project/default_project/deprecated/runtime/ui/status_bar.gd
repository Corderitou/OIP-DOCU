class_name StatusBar
extends PanelContainer

const COL_BG      := Color("#0d1117")
const COL_BORDER  := Color("#30363d")
const COL_TEXT    := Color("#e6edf3")
const COL_DIM     := Color("#8b949e")
const COL_ACCENT  := Color("#3b82f6")
const COL_OK      := Color("#3fb950")
const COL_WARN    := Color("#f0c000")
const COL_ERR     := Color("#ff6b6b")

var _hbox: HBoxContainer
var _status_label: Label
var _parts_count_label: Label
var _comms_label: Label
var _mode_label: Label
var _axis_label: Label
var _opcua_dot: ColorRect
var _opcua_label: Label
var _rotation_label: Label


func _ready() -> void:
	_build_ui()
	_connect_comms_hub()


func _connect_comms_hub() -> void:
	if not is_instance_valid(CommsHub):
		return
	if CommsHub.has_signal("connection_status_changed"):
		CommsHub.connect("connection_status_changed", _on_opcua_connection_changed)
	_update_opcua_dot(CommsHub.is_comms_connected() if CommsHub.has_method("is_comms_connected") else false)


func _build_ui() -> void:
	# Fondo del status bar
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = COL_BORDER
	sb.border_width_top = 1
	sb.set_content_margin_all(4)
	sb.set_content_margin(SIDE_LEFT, 8)
	sb.set_content_margin(SIDE_RIGHT, 8)
	add_theme_stylebox_override("panel", sb)

	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 12)
	add_child(_hbox)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_color_override("font_color", COL_TEXT)
	_hbox.add_child(_status_label)

	_hbox.add_child(_vsep())

	_parts_count_label = Label.new()
	_parts_count_label.text = "Parts: 0"
	_parts_count_label.add_theme_color_override("font_color", COL_DIM)
	_hbox.add_child(_parts_count_label)

	_hbox.add_child(_vsep())

	_comms_label = Label.new()
	_comms_label.text = "Comms: OFF"
	_comms_label.add_theme_color_override("font_color", COL_DIM)
	_hbox.add_child(_comms_label)

	_hbox.add_child(_vsep())

	# OPC UA connection indicator
	_opcua_dot = ColorRect.new()
	_opcua_dot.custom_minimum_size = Vector2(10, 10)
	_opcua_dot.color = COL_DIM
	_hbox.add_child(_opcua_dot)

	_opcua_label = Label.new()
	_opcua_label.text = "OPC UA: Desconectado"
	_opcua_label.add_theme_color_override("font_color", COL_DIM)
	_hbox.add_child(_opcua_label)

	_hbox.add_child(_vsep())

	_mode_label = Label.new()
	_mode_label.text = "Select"
	_mode_label.add_theme_color_override("font_color", COL_ACCENT)
	_hbox.add_child(_mode_label)

	_hbox.add_child(_vsep())

	_axis_label = Label.new()
	_axis_label.text = ""
	_axis_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_hbox.add_child(_axis_label)

	_hbox.add_child(_vsep())

	_rotation_label = Label.new()
	_rotation_label.text = ""
	_rotation_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_hbox.add_child(_rotation_label)


func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep


func set_status(text: String) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", COL_TEXT)


func set_parts_count(count: int) -> void:
	_parts_count_label.text = "Parts: %d" % count


func set_comms_enabled(enabled: bool) -> void:
	_comms_label.text = "Comms: " + ("ON" if enabled else "OFF")
	_comms_label.add_theme_color_override("font_color", COL_OK if enabled else COL_DIM)


func set_mode(text: String) -> void:
	_mode_label.text = text


func set_axis(axis: String) -> void:
	if axis == "":
		_axis_label.text = ""
	else:
		_axis_label.text = "Axis: " + axis.to_upper()


func set_rotation_angle(angle_deg: float) -> void:
	if angle_deg == 0.0:
		_rotation_label.text = ""
	else:
		_rotation_label.text = "Rot: %.1f°" % angle_deg


func set_angle_input(text: String) -> void:
	if text.is_empty():
		_rotation_label.text = ""
		_rotation_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		_rotation_label.text = "Ángulo: " + text
		_rotation_label.add_theme_color_override("font_color", Color("#58a6ff"))


func _on_opcua_connection_changed(connected: bool) -> void:
	_update_opcua_dot(connected)


func _update_opcua_dot(connected: bool) -> void:
	if not is_instance_valid(_opcua_dot):
		return
	var comms_enabled := CommsHub.get_enable_comms() if is_instance_valid(CommsHub) and CommsHub.has_method("get_enable_comms") else false
	if connected:
		_opcua_dot.color = COL_OK
		_opcua_label.text = "OPC UA: Conectado"
		_opcua_label.add_theme_color_override("font_color", COL_OK)
	elif comms_enabled:
		_opcua_dot.color = COL_WARN
		_opcua_label.text = "OPC UA: Habilitado (no verificado)"
		_opcua_label.add_theme_color_override("font_color", COL_WARN)
	else:
		_opcua_dot.color = COL_ERR
		_opcua_label.text = "OPC UA: Desconectado"
		_opcua_label.add_theme_color_override("font_color", COL_ERR)
