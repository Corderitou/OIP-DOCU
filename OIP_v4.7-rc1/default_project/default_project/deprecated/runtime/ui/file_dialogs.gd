class_name FileDialogs
extends Node

signal scene_loaded(path: String)
signal scene_saved(path: String)

var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _save_scene_manager: SceneManager
var _load_scene_manager: SceneManager
var _scene_root: Node3D

const RECENT_MAX: int = 10
const RECENT_CONFIG: String = "user://recent_files.cfg"

var _recent_files: Array[String] = []


func setup(save_mgr: SceneManager, load_mgr: SceneManager, root: Node3D) -> void:
	_save_scene_manager = save_mgr
	_load_scene_manager = load_mgr
	_scene_root = root
	_load_recent()


func open_file_dialog() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.oip_scene.json;OIP Scene"])
	_open_dialog.title = "Open Scene"
	_open_dialog.file_selected.connect(_on_file_opened)

	if not _open_dialog.is_inside_tree():
		get_tree().root.add_child(_open_dialog)
	_open_dialog.popup_centered(Vector2i(800, 500))


func save_file_dialog() -> void:
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.oip_scene.json;OIP Scene"])
	_save_dialog.title = "Save Scene"
	_save_dialog.file_selected.connect(_on_file_saved)

	if not _save_dialog.is_inside_tree():
		get_tree().root.add_child(_save_dialog)
	_save_dialog.popup_centered(Vector2i(800, 500))


func save_scene_direct() -> void:
	if _save_scene_manager.current_path.is_empty():
		save_file_dialog()
		return
	_perform_save(_save_scene_manager.current_path)


func _on_file_opened(path: String) -> void:
	var success := _load_scene_manager.load_scene(path, _scene_root)
	if success:
		_add_recent(path)
		scene_loaded.emit(path)
		_open_dialog.queue_free()


func _on_file_saved(path: String) -> void:
	if not path.ends_with(SceneManager.JSON_EXTENSION):
		path += SceneManager.JSON_EXTENSION
	_perform_save(path)
	_save_dialog.queue_free()


func _perform_save(path: String) -> void:
	var success := _save_scene_manager.save_scene(path)
	if success:
		_add_recent(path)
		scene_saved.emit(path)


func _add_recent(path: String) -> void:
	_recent_files.erase(path)
	_recent_files.push_front(path)
	if _recent_files.size() > RECENT_MAX:
		_recent_files.resize(RECENT_MAX)
	_save_recent()


func _save_recent() -> void:
	var config := ConfigFile.new()
	for i in range(_recent_files.size()):
		config.set_value("recent", "file_%d" % i, _recent_files[i])
	config.set_value("recent", "count", _recent_files.size())
	config.save(RECENT_CONFIG)


func _load_recent() -> void:
	var config := ConfigFile.new()
	if config.load(RECENT_CONFIG) != OK:
		return
	var count: int = config.get_value("recent", "count", 0)
	_recent_files.clear()
	for i in range(min(count, RECENT_MAX)):
		var path: String = config.get_value("recent", "file_%d" % i, "")
		if path and FileAccess.file_exists(path):
			_recent_files.append(path)


func get_recent_files() -> Array[String]:
	return _recent_files
