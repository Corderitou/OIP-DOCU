class_name NotificationBar
extends PanelContainer

## Toast notifications with severity-colored backgrounds.

const COL_BG_INFO  := Color("#1a2332")
const COL_BG_WARN  := Color("#2a2010")
const COL_BG_ERR   := Color("#2a1215")
const COL_BORDER_INFO := Color("#3b82f6")
const COL_BORDER_WARN := Color("#f0c000")
const COL_BORDER_ERR  := Color("#ff6b6b")
const COL_TEXT_INFO := Color("#e6edf3")
const COL_TEXT_WARN := Color("#f0c000")
const COL_TEXT_ERR  := Color("#ff6b6b")

var _label: Label
var _timer: Timer
var _tween: Tween


func _ready() -> void:
	# Background style (initially hidden)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG_INFO
	sb.border_color = COL_BORDER_INFO
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.set_content_margin_all(6)
	sb.set_content_margin(SIDE_LEFT, 12)
	sb.set_content_margin(SIDE_RIGHT, 12)
	add_theme_stylebox_override("panel", sb)

	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", COL_TEXT_INFO)
	add_child(_label)

	_timer = Timer.new()
	_timer.wait_time = 3.0
	_timer.one_shot = true
	_timer.timeout.connect(_hide_notification)
	add_child(_timer)

	visible = false
	modulate.a = 0.0


func show_toast(message: String, severity: int) -> void:
	_label.text = message

	var sb := get_theme_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
	var text_color: Color

	match severity:
		0:
			sb.bg_color = COL_BG_INFO
			sb.border_color = COL_BORDER_INFO
			text_color = COL_TEXT_INFO
		1:
			sb.bg_color = COL_BG_WARN
			sb.border_color = COL_BORDER_WARN
			text_color = COL_TEXT_WARN
		2:
			sb.bg_color = COL_BG_ERR
			sb.border_color = COL_BORDER_ERR
			text_color = COL_TEXT_ERR
		_:
			sb.bg_color = COL_BG_INFO
			sb.border_color = COL_BORDER_INFO
			text_color = COL_TEXT_INFO

	add_theme_stylebox_override("panel", sb)
	_label.add_theme_color_override("font_color", text_color)

	visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)

	_timer.start()


func _hide_notification() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(func(): visible = false)
