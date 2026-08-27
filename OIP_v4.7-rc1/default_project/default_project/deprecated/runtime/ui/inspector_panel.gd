class_name InspectorPanel
extends PanelContainer

var _scroll: ScrollContainer
var _content: VBoxContainer
var _node_name_label: Label
var _type_label: Label
var _no_selection_label: Label
var _current_node: Node = null
var _properties_container: VBoxContainer

var _scene_manager: SceneManager = null


func setup(scene_manager: SceneManager) -> void:
	_scene_manager = scene_manager


func _ready() -> void:
	_setup_ui()
	RuntimeSelection.selection_changed.connect(_on_selection_changed)


func _setup_ui() -> void:
	# Apply dark stylebox
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

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Inspector"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color("#e6edf3"))
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	vbox.add_child(_hsep())

	_no_selection_label = Label.new()
	_no_selection_label.text = "No selection"
	_no_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_selection_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_no_selection_label.add_theme_color_override("font_color", Color("#8b949e"))
	vbox.add_child(_no_selection_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.visible = false
	vbox.add_child(_scroll)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_vbox.add_theme_constant_override("separation", 6)
	_scroll.add_child(inner_vbox)

	_node_name_label = Label.new()
	_node_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_node_name_label.add_theme_font_size_override("font_size", 16)
	_node_name_label.add_theme_color_override("font_color", Color("#3b82f6"))
	inner_vbox.add_child(_node_name_label)

	_type_label = Label.new()
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.add_theme_font_size_override("font_size", 12)
	_type_label.add_theme_color_override("font_color", Color("#8b949e"))
	inner_vbox.add_child(_type_label)

	inner_vbox.add_child(_hsep())

	_properties_container = VBoxContainer.new()
	_properties_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_properties_container.add_theme_constant_override("separation", 6)
	inner_vbox.add_child(_properties_container)


func _hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _on_selection_changed(selected: Array) -> void:
	if selected.is_empty():
		_show_no_selection()
		return

	_show_node(selected[0])


func _show_no_selection() -> void:
	_current_node = null
	_scroll.visible = false
	_no_selection_label.visible = true


func _show_node(node: Node) -> void:
	_current_node = node
	_no_selection_label.visible = false
	_scroll.visible = true

	_node_name_label.text = node.name
	var type := SceneRegistry.get_type_for_node(node)
	_type_label.text = type if type else ""

	_rebuild_properties()


func _rebuild_properties() -> void:
	for child in _properties_container.get_children():
		child.queue_free()

	if not _current_node:
		return

	# --- Transform section (Node3D built-in properties) ---
	if _current_node is Node3D:
		var header := Label.new()
		header.text = "Transform"
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color("#e6edf3"))
		_properties_container.add_child(header)

		_add_vector3_row("position", "Position", _current_node.position)
		_add_vector3_row("rotation_degrees", "Rotation", _current_node.rotation_degrees)

		_properties_container.add_child(_hsep())

	# --- Script properties ---
	var script: Script = _current_node.get_script()
	if not script:
		return

	# Only render script-declared properties (built-in Node3D/Node ones have
	# their own Transform section above and are skipped here).
	var script_prop_names := {}
	for script_prop in script.get_script_property_list():
		script_prop_names[script_prop["name"]] = true

	# Use the instance property list so _validate_property() applies (mirrored
	# right_* funnel props stay hidden while mirror_guards is enabled, etc.).
	var prop_list := _current_node.get_property_list()
	for prop in prop_list:
		var prop_name: String = prop["name"]
		if prop_name not in script_prop_names:
			continue
		var usage: int = prop["usage"]
		var hint: int = prop["hint"]
		var hint_string: String = prop["hint_string"]

		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if prop_name.begins_with("_"):
			continue
		if prop_name in ["size", "original_size", "transform_in_progress", "hijack_scale"]:
			continue
		if prop_name.begins_with("metadata/"):
			continue
		# Comms/tag fields are managed by the COMMS panel, not the inspector.
		if _is_comms_property(prop_name):
			continue

		var current_value: Variant = _current_node.get(prop_name)
		if current_value == null:
			continue

		var prop_type: int = prop["type"]
		_add_property_widget(prop_name, current_value, prop_type, hint, hint_string)


func _is_comms_property(prop_name: String) -> bool:
	if prop_name == "enable_comms":
		return true
	if prop_name == "tag_name" or prop_name.ends_with("_tag_name"):
		return true
	if prop_name == "tag_group_name" or prop_name.ends_with("_tag_group_name"):
		return true
	if prop_name == "tag_groups" or prop_name == "tag_group":
		return true
	# Robot/gantry style fields: command_tag, execute_tag, done_tag, vacuum_tag
	if prop_name.ends_with("_tag"):
		return true
	return false


func _add_property_widget(prop_name: String, value: Variant, prop_type: int, hint: int, hint_string: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = prop_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 120
	hbox.add_child(label)

	match prop_type:
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(func(pressed: bool): _set_property(prop_name, pressed))
			hbox.add_child(check)

		TYPE_INT:
			var spin := SpinBox.new()
			spin.value = value
			spin.min_value = -9999
			spin.max_value = 9999
			spin.value_changed.connect(func(v: float): _set_property(prop_name, int(v)))
			hbox.add_child(spin)

		TYPE_FLOAT:
			var spin := SpinBox.new()
			spin.value = value
			spin.min_value = -9999.0
			spin.max_value = 9999.0
			spin.step = 0.01
			spin.value_changed.connect(func(v: float): _set_property(prop_name, v))
			hbox.add_child(spin)

		TYPE_STRING:
			var line_edit := LineEdit.new()
			line_edit.text = value
			line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line_edit.text_submitted.connect(func(text: String): _set_property(prop_name, text))
			hbox.add_child(line_edit)

		TYPE_VECTOR3:
			var vec: Vector3 = value
			for axis in ["X", "Y", "Z"]:
				var spin := SpinBox.new()
				spin.value = vec[axis.to_lower()]
				spin.min_value = -9999.0
				spin.max_value = 9999.0
				spin.step = 0.1
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var axis_name: String = axis.to_lower()
				spin.value_changed.connect(func(v: float):
					var current: Vector3 = _current_node.get(prop_name)
					current[axis_name] = v
					_set_property(prop_name, current)
				)
				hbox.add_child(spin)

		TYPE_COLOR:
			var color_picker := ColorPickerButton.new()
			color_picker.color = value
			color_picker.color_changed.connect(func(c: Color): _set_property(prop_name, c))
			hbox.add_child(color_picker)

		_:
			var line_edit := LineEdit.new()
			line_edit.text = str(value)
			line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(line_edit)

	_properties_container.add_child(hbox)


func _add_vector3_row(prop_name: String, label_text: String, value: Vector3) -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 120
	hbox.add_child(label)

	for axis in ["x", "y", "z"]:
		var spin := SpinBox.new()
		spin.value = value[axis]
		spin.min_value = -9999.0
		spin.max_value = 9999.0
		spin.step = 0.1
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var axis_name: String = axis
		spin.value_changed.connect(func(v: float):
			var current: Vector3 = _current_node.get(prop_name)
			current[axis_name] = v
			_set_property(prop_name, current)
		)
		hbox.add_child(spin)

	_properties_container.add_child(hbox)


func _set_property(prop_name: String, value: Variant) -> void:
	if not _current_node:
		return

	if _scene_manager:
		_scene_manager.mark_modified()

	_current_node.set(prop_name, value)
