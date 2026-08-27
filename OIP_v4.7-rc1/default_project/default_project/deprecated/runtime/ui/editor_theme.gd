class_name EditorTheme
extends RefCounted

# ── Paleta ────────────────────────────────────────────────
const COL_BG_DARKEST  := Color("#0d1117")
const COL_BG_DARK     := Color("#161b22")
const COL_BG_PANEL    := Color("#1c2128")
const COL_BG_HOVER    := Color("#262d36")
const COL_BG_PRESSED  := Color("#2f363d")
const COL_ACCENT      := Color("#3b82f6")
const COL_ACCENT_DIM  := Color("#1e40af")
const COL_TEXT        := Color("#e6edf3")
const COL_TEXT_DIM    := Color("#8b949e")
const COL_TEXT_WARN   := Color("#f0c000")
const COL_TEXT_ERR    := Color("#ff6b6b")
const COL_TEXT_OK     := Color("#3fb950")
const COL_BORDER      := Color("#30363d")
const COL_BORDER_DIM  := Color("#21262d")


static func build() -> Theme:
	var t := Theme.new()
	_fills(t)
	_fonts(t)
	return t


static func _fills(t: Theme) -> void:
	# ── PanelContainer ──────────────────────────────────────
	t.set_stylebox("panel", "PanelContainer", _sb_flat(COL_BG_DARK, 6, COL_BORDER, 1))

	# ── Panel ───────────────────────────────────────────────
	t.set_stylebox("panel", "Panel", _sb_flat(COL_BG_DARK, 0, COL_BORDER, 1))

	# ── Button ──────────────────────────────────────────────
	t.set_stylebox("normal", "Button", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_stylebox("hover", "Button", _sb_flat(COL_BG_HOVER, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("pressed", "Button", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))
	t.set_stylebox("disabled", "Button", _sb_flat(COL_BG_DARKEST, 4, COL_BORDER_DIM, 1))
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", COL_ACCENT)
	t.set_color("font_pressed_color", "Button", COL_ACCENT)
	t.set_color("font_disabled_color", "Button", COL_TEXT_DIM)
	t.set_color("icon_normal_color", "Button", COL_TEXT)
	t.set_color("icon_hover_color", "Button", COL_ACCENT)
	t.set_color("icon_pressed_color", "Button", COL_ACCENT)
	t.set_color("icon_disabled_color", "Button", COL_TEXT_DIM)

	# ── CheckButton ─────────────────────────────────────────
	t.set_stylebox("normal", "CheckButton", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_stylebox("hover", "CheckButton", _sb_flat(COL_BG_HOVER, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("pressed", "CheckButton", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))
	t.set_color("font_color", "CheckButton", COL_TEXT)
	t.set_color("icon_normal_color", "CheckButton", COL_TEXT)
	t.set_color("icon_hover_color", "CheckButton", COL_ACCENT)
	t.set_color("icon_pressed_color", "CheckButton", COL_ACCENT)

	# ── ToggleButton (Button with toggle_mode) ──────────────
	t.set_stylebox("hover_pressed", "Button", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))
	t.set_color("icon_normal_color", "Button", COL_TEXT)
	t.set_color("icon_hover_color", "Button", COL_ACCENT)
	t.set_color("icon_pressed_color", "Button", COL_ACCENT)
	t.set_color("icon_disabled_color", "Button", COL_TEXT_DIM)

	# ── CheckBox ────────────────────────────────────────────
	t.set_stylebox("normal", "CheckBox", _sb_empty(4))
	t.set_stylebox("hover", "CheckBox", _sb_empty(4))
	t.set_stylebox("pressed", "CheckBox", _sb_empty(4))
	t.set_stylebox("disabled", "CheckBox", _sb_empty(4))
	t.set_stylebox("focus", "CheckBox", _sb_empty(4))

	# ── LineEdit ───────────────────────────────────────────
	var sb_le := _sb_flat(COL_BG_DARKEST, 4, COL_BORDER, 1)
	var sb_le_focus := _sb_flat(COL_BG_DARKEST, 4, COL_ACCENT, 1)
	t.set_stylebox("normal", "LineEdit", sb_le)
	t.set_stylebox("hover", "LineEdit", _sb_flat(COL_BG_DARK, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("focus", "LineEdit", _sb_flat(COL_BG_DARKEST, 4, COL_ACCENT, 1))
	t.set_stylebox("read_only", "LineEdit", _sb_flat(COL_BG_DARKEST, 4, COL_BORDER_DIM, 1))

	# ── SpinBox ────────────────────────────────────────────
	t.set_stylebox("up", "SpinBox", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_stylebox("down", "SpinBox", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_stylebox("up_hover", "SpinBox", _sb_flat(COL_BG_HOVER, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("down_hover", "SpinBox", _sb_flat(COL_BG_HOVER, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("up_pressed", "SpinBox", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))
	t.set_stylebox("down_pressed", "SpinBox", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))

	# ── ScrollContainer ─────────────────────────────────────
	t.set_stylebox("panel", "ScrollContainer", _sb_empty(0))

	# ── ScrollBar ───────────────────────────────────────────
	var sb_scroll := _sb_flat(COL_BG_DARKEST, 0, Color(0, 0, 0, 0), 0)
	var sb_grabber := _sb_flat(COL_BORDER, 4, Color(0, 0, 0, 0), 0)
	var sb_grabber_h := _sb_flat(COL_ACCENT, 4, Color(0, 0, 0, 0), 0)
	t.set_stylebox("scroll", "ScrollBar", sb_scroll)
	t.set_stylebox("grabber", "ScrollBar", sb_grabber)
	t.set_stylebox("grabber_highlight", "ScrollBar", sb_grabber_h)
	t.set_stylebox("grabber_pressed", "ScrollBar", sb_grabber_h)

	# ── MenuBar ─────────────────────────────────────────────
	t.set_stylebox("normal", "MenuBar", _sb_flat(COL_BG_DARKEST, 0, Color(0, 0, 0, 0), 0))

	# ── MenuBarButton ──────────────────────────────────────
	t.set_stylebox("normal", "MenuBarButton", _sb_flat(COL_BG_DARKEST, 4, Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "MenuBarButton", _sb_flat(COL_BG_HOVER, 4, Color(0, 0, 0, 0), 0))
	t.set_stylebox("pressed", "MenuBarButton", _sb_flat(COL_ACCENT_DIM, 4, Color(0, 0, 0, 0), 0))

	# ── PopupMenu ───────────────────────────────────────────
	var sb_popup := _sb_flat(COL_BG_DARK, 6, COL_BORDER, 1)
	t.set_stylebox("panel", "PopupMenu", sb_popup)
	t.set_color("font_color", "PopupMenu", COL_TEXT)
	t.set_color("font_hover_color", "PopupMenu", COL_ACCENT)
	t.set_color("icon_normal_color", "PopupMenu", COL_TEXT)
	t.set_color("icon_hover_color", "PopupMenu", COL_ACCENT)

	# ── ItemList ────────────────────────────────────────────
	t.set_stylebox("panel", "ItemList", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_color("font_color", "ItemList", COL_TEXT)
	t.set_color("font_hover_color", "ItemList", COL_ACCENT)
	t.set_color("font_selected_color", "ItemList", COL_TEXT)
	t.set_color("icon_normal_color", "ItemList", COL_TEXT)
	t.set_color("icon_hover_color", "ItemList", COL_ACCENT)
	t.set_color("icon_selected_color", "ItemList", COL_ACCENT)

	# ── OptionButton ────────────────────────────────────────
	t.set_stylebox("normal", "OptionButton", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_stylebox("hover", "OptionButton", _sb_flat(COL_BG_HOVER, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("pressed", "OptionButton", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))
	t.set_color("font_color", "OptionButton", COL_TEXT)
	t.set_color("icon_normal_color", "OptionButton", COL_TEXT)
	t.set_color("icon_hover_color", "OptionButton", COL_ACCENT)

	# ── TabContainer / TabBar ───────────────────────────────
	t.set_stylebox("panel", "TabContainer", _sb_flat(COL_BG_DARK, 0, COL_BORDER, 1))
	t.set_stylebox("tab_normal", "TabBar", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_stylebox("tab_hover", "TabBar", _sb_flat(COL_BG_HOVER, 4, COL_ACCENT_DIM, 1))
	t.set_stylebox("tab_pressed", "TabBar", _sb_flat(COL_BG_PRESSED, 4, COL_ACCENT, 1))
	t.set_color("font_color", "TabBar", COL_TEXT_DIM)
	t.set_color("font_hover_color", "TabBar", COL_TEXT)
	t.set_color("font_selected_color", "TabBar", COL_ACCENT)

	# ── Tree ────────────────────────────────────────────────
	t.set_stylebox("panel", "Tree", _sb_flat(COL_BG_DARK, 4, COL_BORDER, 1))
	t.set_color("font_color", "Tree", COL_TEXT)
	t.set_color("font_hover_color", "Tree", COL_ACCENT)
	t.set_color("icon_normal_color", "Tree", COL_TEXT)
	t.set_color("icon_hover_color", "Tree", COL_ACCENT)


static func _fonts(t: Theme) -> void:
	# No custom fonts, use system defaults with good sizes
	t.set_font_size("font_size", "Button", 13)
	t.set_font_size("font_size", "CheckButton", 13)
	t.set_font_size("font_size", "LineEdit", 13)
	t.set_font_size("font_size", "Label", 13)
	t.set_font_size("font_size", "MenuBar", 13)
	t.set_font_size("font_size", "PopupMenu", 13)
	t.set_font_size("font_size", "ItemList", 13)
	t.set_font_size("font_size", "OptionButton", 13)
	t.set_font_size("font_size", "TabBar", 13)
	t.set_font_size("font_size", "Tree", 13)

	# Constantes
	t.set_constant("h_separation", "Button", 6)
	t.set_constant("h_separation", "CheckButton", 6)
	t.set_constant("h_separation", "CheckBox", 6)
	t.set_constant("h_separation", "MenuBarButton", 8)
	t.set_constant("h_separation", "PopupMenu", 12)
	t.set_constant("item_margin", "PopupMenu", 6)
	t.set_constant("icon_margin", "PopupMenu", 8)
	t.set_constant("separation", "TabContainer", 4)
	t.set_constant("icon_max_width", "PopupMenu", 16)
	t.set_constant("icon_max_width", "MenuBar", 16)


static func _sb_flat(bg: Color, radius: float, border_col: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_content_margin_all(4)
	return sb


static func _sb_empty(radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	sb.set_content_margin_all(4)
	return sb