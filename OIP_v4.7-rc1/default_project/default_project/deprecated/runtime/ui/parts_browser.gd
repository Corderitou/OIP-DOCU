class_name PartsBrowser
extends PanelContainer

signal part_selected(type_name: String)
signal part_drag_started(type_name: String)

var _category_option: OptionButton
var _item_list: ItemList
var _search: LineEdit
var _thumbnails: Dictionary = {}
var _all_items: Array = []
var _current_category: String = ""

var _sub_viewport: SubViewport
var _thumb_camera: Camera3D
var _thumb_light: DirectionalLight3D


func _ready() -> void:
	_setup_ui()
	_populate_parts()
	_setup_thumbnail_generator()


func _setup_ui() -> void:
	# Apply dark stylebox to this PanelContainer with proper margins
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#161b22")
	sb.border_color = Color("#30363d")
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.set_content_margin_all(8)
	sb.set_content_margin(SIDE_LEFT, 12)
	sb.set_content_margin(SIDE_RIGHT, 12)
	sb.set_content_margin(SIDE_TOP, 8)
	sb.set_content_margin(SIDE_BOTTOM, 8)
	add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Header label
	var header := Label.new()
	header.text = "Parts Library"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color("#e6edf3"))
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	vbox.add_child(_hsep())

	# Search bar
	_search = LineEdit.new()
	_search.placeholder_text = "Search parts..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	vbox.add_child(_search)

	# Category dropdown
	_category_option = OptionButton.new()
	_category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_option.item_selected.connect(_on_category_selected)
	vbox.add_child(_category_option)

	# Separator
	vbox.add_child(_hsep())

	# Item list
	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.custom_minimum_size = Vector2(0, 100)
	_item_list.max_columns = 2
	_item_list.icon_mode = ItemList.ICON_MODE_TOP
	_item_list.item_clicked.connect(_on_item_clicked)
	vbox.add_child(_item_list)


func _hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _populate_parts() -> void:
	_category_option.clear()
	_category_option.add_item("All Parts", 0)

	var cats: Array = SceneRegistry.get_categories()
	for i in range(cats.size()):
		_category_option.add_item(String(cats[i]), i + 1)
		var types: Array = SceneRegistry.get_category_types(String(cats[i]))
		for t in types:
			_all_items.append({"name": String(t), "category": String(cats[i])})

	_refresh_item_list("")


func _refresh_item_list(filter: String) -> void:
	_item_list.clear()
	for item in _all_items:
		if not _current_category.is_empty() and item["category"] != _current_category:
			continue
		if not filter.is_empty() and not filter.to_lower() in item["name"].to_lower():
			continue
		_item_list.add_item(item["name"])


func _on_search_changed(text: String) -> void:
	_refresh_item_list(text)


func _on_category_selected(index: int) -> void:
	if index == 0:
		_current_category = ""
	else:
		_current_category = String(_category_option.get_item_text(index))
	_refresh_item_list(_search.text)


func _on_item_clicked(index: int, at_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		var type_name: String = _item_list.get_item_text(index)
		part_selected.emit(type_name)


func _setup_thumbnail_generator() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(128, 128)
	_sub_viewport.transparent_bg = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub_viewport)

	_thumb_camera = Camera3D.new()
	_thumb_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_thumb_camera.size = 5.0
	_sub_viewport.add_child(_thumb_camera)
	_thumb_camera.look_at_from_position(Vector3(3, 3, 3), Vector3.ZERO, Vector3.UP)

	_thumb_light = DirectionalLight3D.new()
	_thumb_light.rotation_degrees = Vector3(-45, 45, 0)
	_sub_viewport.add_child(_thumb_light)


func generate_thumbnail(type_name: String) -> Texture2D:
	var scene_path: String = SceneRegistry.get_scene_path(type_name)
	if scene_path.is_empty():
		return null

	var scene: PackedScene = load(scene_path)
	if not scene:
		return null

	var node: Node3D = scene.instantiate()
	_sub_viewport.add_child(node)

	_center_camera_on_node(node)

	await RenderingServer.frame_post_draw

	var image := _sub_viewport.get_texture().get_image()
	var tex := ImageTexture.create_from_image(image)

	node.queue_free()

	_thumbnails[type_name] = tex
	return tex


func _center_camera_on_node(node: Node3D) -> void:
	var aabb := AABB(node.position, Vector3.ONE)
	if node is MeshInstance3D and node.mesh:
		aabb = node.get_aabb()

	var center := aabb.get_center()
	var size := aabb.size.length()
	_thumb_camera.position = center + Vector3(2, 2, 2) * max(size, 1.0)
	_thumb_camera.size = max(size * 1.5, 2.0)
	_thumb_camera.look_at(center, Vector3.UP)
