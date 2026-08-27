class_name Toolbar
extends HBoxContainer

## Toolbar with pull-down menus on the left, tool/action buttons grouped in
## logical blocks, and status read-outs on the right. Each block is separated
## by a vertical rule so the order is unambiguous and nothing overlaps.

signal new_pressed
signal open_pressed
signal save_pressed
signal play_pressed
signal pause_pressed
signal stop_pressed
signal undo_pressed
signal redo_pressed
signal select_mode
signal move_mode
signal rotate_mode
signal snap_toggled
signal copy_pressed
signal paste_pressed
signal duplicate_pressed
signal delete_pressed
signal focus_pressed
signal view_front
signal view_back
signal view_left
signal view_right
signal view_top
signal toggle_left_panel
signal toggle_right_panel
signal toggle_status_bar
signal toggle_comms_panel
signal rotation_snap_changed(angle_deg: int)

const COL_LABEL := Color("#8b949e")
const COL_ACCENT := Color("#3b82f6")

const ACTION_NEW            := 100
const ACTION_OPEN           := 101
const ACTION_SAVE           := 102
const ACTION_QUIT           := 103
const ACTION_UNDO           := 200
const ACTION_REDO           := 201
const ACTION_COPY           := 202
const ACTION_PASTE          := 203
const ACTION_DUPLICATE      := 204
const ACTION_DELETE         := 205
const ACTION_PLAY           := 400
const ACTION_PAUSE          := 401
const ACTION_STOP           := 402
const ACTION_VIEW_FRONT     := 500
const ACTION_VIEW_BACK      := 501
const ACTION_VIEW_LEFT      := 502
const ACTION_VIEW_RIGHT     := 503
const ACTION_VIEW_TOP       := 504
const ACTION_TOGGLE_LEFT    := 600
const ACTION_TOGGLE_RIGHT   := 601
const ACTION_TOGGLE_STATUS  := 602
const ACTION_TOGGLE_COMMS   := 603

var _menu_bar: MenuBar
var _mode_label: Label
var _camera_label: Label

var _select_btn: Button
var _move_btn: Button
var _rotate_btn: Button
var _snap_btn: CheckButton
var _rotation_snap_option: OptionButton
var _play_btn: Button
var _pause_btn: Button
var _stop_btn: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 40)
	add_theme_constant_override("separation", 8)
	clip_contents = true

	# Left margin for the whole toolbar
	var left_spacer := Control.new()
	left_spacer.custom_minimum_size.x = 8
	add_child(left_spacer)

	# ── Block 1: Pull-down menus ─────────────────────────────
	_menu_bar = MenuBar.new()
	_menu_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	_menu_bar.flat = false
	add_child(_menu_bar)
	_build_file_menu()
	_build_edit_menu()
	_build_view_menu()

	add_child(_vsep())

	# ── Block 2: Transform tools (Select/Move/Rotate) ──────────
	var tools_box := HBoxContainer.new()
	tools_box.add_theme_constant_override("separation", 2)
	tools_box.size_flags_vertical = SIZE_SHRINK_CENTER
	add_child(tools_box)

	_select_btn = _make_icon_btn("res://src/runtime/ui/icons/cursor-arrow.svg", "Select (Q)", "Select")
	_select_btn.button_pressed = true
	_select_btn.pressed.connect(func(): select_mode.emit())
	tools_box.add_child(_select_btn)

	_move_btn = _make_icon_btn("res://src/runtime/ui/icons/move.svg", "Move (W)", "Move")
	_move_btn.pressed.connect(func(): move_mode.emit())
	tools_box.add_child(_move_btn)

	_rotate_btn = _make_icon_btn("res://src/runtime/ui/icons/rotate-cw.svg", "Rotate (R)", "Rotate")
	_rotate_btn.pressed.connect(func(): rotate_mode.emit())
	tools_box.add_child(_rotate_btn)

	add_child(_vsep())

	# ── Block 3: Editor settings ──────────────────────────────
	_snap_btn = CheckButton.new()
	_snap_btn.text = "Snap"
	_snap_btn.button_pressed = true
	_snap_btn.tooltip_text = "Toggle grid snapping (G)"
	_snap_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	_snap_btn.toggled.connect(func(_v): snap_toggled.emit())
	add_child(_snap_btn)

	# Rotation snap dropdown
	_rotation_snap_option = OptionButton.new()
	_rotation_snap_option.add_item("Snap: 15°", 15)
	_rotation_snap_option.add_item("Snap: 30°", 30)
	_rotation_snap_option.add_item("Snap: 45°", 45)
	_rotation_snap_option.add_item("Snap: 90°", 90)
	_rotation_snap_option.add_item("Snap: Off", 0)
	_rotation_snap_option.select(0)
	_rotation_snap_option.size_flags_vertical = SIZE_SHRINK_CENTER
	_rotation_snap_option.item_selected.connect(func(idx: int): rotation_snap_changed.emit(_rotation_snap_option.get_item_id(idx)))
	_rotation_snap_option.tooltip_text = "Rotation snap angle"
	add_child(_rotation_snap_option)

	add_child(_vsep())

	# ── Block 4: Simulation controls ──────────────────────────
	var sim_box := HBoxContainer.new()
	sim_box.add_theme_constant_override("separation", 2)
	sim_box.size_flags_vertical = SIZE_SHRINK_CENTER
	add_child(sim_box)

	_play_btn = _make_icon_btn("res://src/runtime/ui/icons/play.svg", "Play (F5)", "Play")
	_play_btn.pressed.connect(func(): play_pressed.emit())
	sim_box.add_child(_play_btn)

	_pause_btn = _make_icon_btn("res://src/runtime/ui/icons/pause.svg", "Pause", "Pause")
	_pause_btn.disabled = true
	_pause_btn.pressed.connect(func(): pause_pressed.emit())
	sim_box.add_child(_pause_btn)

	_stop_btn = _make_icon_btn("res://src/runtime/ui/icons/stop.svg", "Stop", "Stop")
	_stop_btn.disabled = true
	_stop_btn.pressed.connect(func(): stop_pressed.emit())
	sim_box.add_child(_stop_btn)

	# Spacer pushes the status labels to the far edge
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(spacer)

	# ── Block 5: Status read-outs (right-aligned) ─────────────
	_mode_label = Label.new()
	_mode_label.text = "Mode: Select"
	_mode_label.add_theme_color_override("font_color", COL_LABEL)
	_mode_label.size_flags_vertical = SIZE_SHRINK_CENTER
	_mode_label.custom_minimum_size.x = 130
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_mode_label)

	add_child(_vsep())

	_camera_label = Label.new()
	_camera_label.text = "Camera: Walk"
	_camera_label.add_theme_color_override("font_color", COL_LABEL)
	_camera_label.size_flags_vertical = SIZE_SHRINK_CENTER
	_camera_label.custom_minimum_size.x = 130
	_camera_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_camera_label)

	# Right margin
	var right_spacer := Control.new()
	right_spacer.custom_minimum_size.x = 8
	add_child(right_spacer)


# ── File Menu ───────────────────────────────────────────
func _build_file_menu() -> void:
	var mb := PopupMenu.new()
	_set_item(mb, "New Scene", ACTION_NEW)
	_set_item(mb, "Open Scene\u2026", ACTION_OPEN)
	_set_item(mb, "Save Scene", ACTION_SAVE)
	mb.add_separator()
	_set_item(mb, "Quit", ACTION_QUIT)
	mb.id_pressed.connect(_on_menu_id)
	_menu_bar.add_child(mb)
	_menu_bar.set_menu_title(0, "File")


# ── Edit Menu ───────────────────────────────────────────
func _build_edit_menu() -> void:
	var mb := PopupMenu.new()
	_set_item(mb, "Undo", ACTION_UNDO)
	_set_item(mb, "Redo", ACTION_REDO)
	mb.add_separator()
	_set_item(mb, "Copy", ACTION_COPY)
	_set_item(mb, "Paste", ACTION_PASTE)
	_set_item(mb, "Duplicate", ACTION_DUPLICATE)
	_set_item(mb, "Delete", ACTION_DELETE)
	_set_item(mb, "Focus Selection", 0)
	mb.id_pressed.connect(_on_menu_id)
	_menu_bar.add_child(mb)
	_menu_bar.set_menu_title(1, "Edit")


# ── View Menu ───────────────────────────────────────────
func _build_view_menu() -> void:
	var mb := PopupMenu.new()
	_set_item(mb, "Front", ACTION_VIEW_FRONT)
	_set_item(mb, "Back", ACTION_VIEW_BACK)
	_set_item(mb, "Left", ACTION_VIEW_LEFT)
	_set_item(mb, "Right", ACTION_VIEW_RIGHT)
	_set_item(mb, "Top", ACTION_VIEW_TOP)
	mb.add_separator()
	_set_item(mb, "Toggle Parts Library", ACTION_TOGGLE_LEFT)
	_set_item(mb, "Toggle Inspector", ACTION_TOGGLE_RIGHT)
	_set_item(mb, "Toggle COMMS", ACTION_TOGGLE_COMMS)
	mb.add_separator()
	_set_item(mb, "Toggle Status Bar", ACTION_TOGGLE_STATUS)
	mb.id_pressed.connect(_on_menu_id)
	_menu_bar.add_child(mb)
	_menu_bar.set_menu_title(2, "View")


# ── Menu Handlers ───────────────────────────────────────
func _set_item(mb: PopupMenu, label: String, id: int) -> void:
	mb.add_item(label, id)


func _on_menu_id(id: int) -> void:
	match id:
		ACTION_NEW:            new_pressed.emit()
		ACTION_OPEN:           open_pressed.emit()
		ACTION_SAVE:           save_pressed.emit()
		ACTION_QUIT:           get_tree().quit()
		ACTION_UNDO:           undo_pressed.emit()
		ACTION_REDO:           redo_pressed.emit()
		ACTION_COPY:           copy_pressed.emit()
		ACTION_PASTE:          paste_pressed.emit()
		ACTION_DUPLICATE:      duplicate_pressed.emit()
		ACTION_DELETE:         delete_pressed.emit()
		ACTION_PLAY:           play_pressed.emit()
		ACTION_PAUSE:          pause_pressed.emit()
		ACTION_STOP:           stop_pressed.emit()
		ACTION_VIEW_FRONT:     view_front.emit()
		ACTION_VIEW_BACK:      view_back.emit()
		ACTION_VIEW_LEFT:      view_left.emit()
		ACTION_VIEW_RIGHT:     view_right.emit()
		ACTION_VIEW_TOP:       view_top.emit()
		ACTION_TOGGLE_LEFT:    toggle_left_panel.emit()
		ACTION_TOGGLE_RIGHT:   toggle_right_panel.emit()
		ACTION_TOGGLE_COMMS:   toggle_comms_panel.emit()
		ACTION_TOGGLE_STATUS:  toggle_status_bar.emit()


# ── Public API ──────────────────────────────────────────
func set_simulation_running(running: bool) -> void:
	if running:
		_play_btn.disabled = true
		_pause_btn.disabled = false
		_pause_btn.button_pressed = false
		_stop_btn.disabled = false
	else:
		_play_btn.disabled = false
		_pause_btn.disabled = true
		_pause_btn.button_pressed = false
		_stop_btn.disabled = true


func set_simulation_paused(paused: bool) -> void:
	_play_btn.disabled = false
	_pause_btn.disabled = false
	_pause_btn.button_pressed = paused
	_stop_btn.disabled = false


func set_mode_label(mode_name: String) -> void:
	_mode_label.text = "Mode: " + mode_name


func set_camera_mode(mode_name: String) -> void:
	_camera_label.text = "Camera: " + mode_name


func set_active_tool(tool_idx: int) -> void:
	if _select_btn:
		_select_btn.button_pressed = tool_idx == 0
	if _move_btn:
		_move_btn.button_pressed = tool_idx == 1
	if _rotate_btn:
		_rotate_btn.button_pressed = tool_idx == 2


func set_left_panel_visible(visible: bool) -> void:
	# Only used internally for syncing
	pass


func set_right_panel_visible(visible: bool) -> void:
	# Only used internally for syncing
	pass


# ── Helpers ─────────────────────────────────────────────
func _make_icon_btn(icon_path: String, tooltip: String, text: String) -> Button:
	var btn := Button.new()
	var icon_tex := load(icon_path)
	if icon_tex:
		btn.icon = icon_tex
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(36, 28)
	btn.toggle_mode = true
	return btn


func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size.x = 8
	return sep