class_name SceneManager
extends RefCounted

const SCENE_VERSION: int = 1
const DEFAULT_SCENE_NAME: String = "Untitled Scene"
const JSON_EXTENSION: String = ".oip_scene.json"

signal scene_loaded(path: String)
signal scene_saved(path: String)
signal scene_modified
signal scene_new

var _current_path: String = ""
var _is_modified: bool = false
var _scene_name: String = DEFAULT_SCENE_NAME
var _scene_description: String = ""

var scene_root: Node3D = null

var current_path: String:
	get:
		return _current_path

var is_modified: bool:
	get:
		return _is_modified

var scene_name: String:
	get:
		return _scene_name


func new_scene(root: Node3D) -> void:
	scene_root = root
	_current_path = ""
	_is_modified = false
	_scene_name = DEFAULT_SCENE_NAME
	_scene_description = ""

	for child in root.get_children():
		if child.name == "Building":
			continue
		child.queue_free()

	scene_new.emit()


func save_scene(path: String = "") -> bool:
	if path.is_empty():
		path = _current_path
	if path.is_empty():
		return false

	var data := _serialize_scene()
	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		RuntimeEditorToaster.push_toast("Failed to save: " + path, RuntimeEditorToaster.SEVERITY_ERROR)
		return false
	file.store_string(json_string)
	file.close()

	_current_path = path
	_is_modified = false
	_scene_name = path.get_file().rstrip(JSON_EXTENSION)
	scene_saved.emit(path)
	RuntimeEditorToaster.push_toast("Scene saved: " + path.get_file(), RuntimeEditorToaster.SEVERITY_INFO)
	return true


func load_scene(path: String, root: Node3D) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		RuntimeEditorToaster.push_toast("Failed to open: " + path, RuntimeEditorToaster.SEVERITY_ERROR)
		return false

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		RuntimeEditorToaster.push_toast("Invalid JSON: " + path, RuntimeEditorToaster.SEVERITY_ERROR)
		return false

	var data: Dictionary = json.data
	scene_root = root

	for child in root.get_children():
		child.queue_free()

	_deserialize_scene(root, data)

	_current_path = path
	_is_modified = false
	_scene_name = data.get("name", path.get_file().rstrip(JSON_EXTENSION))
	_scene_description = data.get("description", "")
	scene_loaded.emit(path)
	RuntimeEditorToaster.push_toast("Scene loaded: " + _scene_name, RuntimeEditorToaster.SEVERITY_INFO)
	return true


func mark_modified() -> void:
	if not _is_modified:
		_is_modified = true
		scene_modified.emit()


func _serialize_scene() -> Dictionary:
	var now := Time.get_datetime_string_from_system()
	var nodes: Array[Dictionary] = []

	if scene_root:
		for child in scene_root.get_children():
			var node_data := _serialize_node(child)
			if not node_data.is_empty():
				nodes.append(node_data)

	return {
		"version": SCENE_VERSION,
		"name": _scene_name,
		"description": _scene_description,
		"created": now,
		"modified": now,
		"nodes": nodes,
	}


func _serialize_node(node: Node) -> Dictionary:
	var type := SceneRegistry.get_type_for_node(node)
	if type.is_empty():
		if node.name == "Building":
			return _serialize_building(node)
		return {}

	var data: Dictionary = {
		"id": _node_id(node),
		"type": type,
		"name": node.name,
	}

	if node is Node3D:
		data["transform"] = _serialize_transform(node as Node3D)

	data["properties"] = _serialize_properties(node)

	var children: Array[Dictionary] = []
	for child in node.get_children():
		var child_script: Script = child.get_script()
		if child_script and child_script.get_global_name() == "FlowDirectionArrow":
			continue
		var child_data := _serialize_node(child)
		if not child_data.is_empty():
			children.append(child_data)
	if not children.is_empty():
		data["children"] = children

	return data


func _serialize_building(node: Node) -> Dictionary:
	var data: Dictionary = {
		"id": "building",
		"type": "Building",
		"name": "Building",
	}
	var props: Dictionary = {}
	if "width_sections" in node:
		props["width_sections"] = node.width_sections
	if "length_sections" in node:
		props["length_sections"] = node.length_sections
	if "height_sections" in node:
		props["height_sections"] = node.height_sections
	if "brightness" in node:
		props["brightness"] = node.brightness
	if not props.is_empty():
		data["properties"] = props
	return data


func _serialize_transform(node: Node3D) -> Dictionary:
	var t := node.transform
	var basis: Array[float] = []
	for i in range(3):
		for j in range(3):
			basis.append(t.basis[i][j])
	return {
		"origin": [t.origin.x, t.origin.y, t.origin.z],
		"basis": basis,
	}


func _serialize_properties(node: Node) -> Dictionary:
	var props: Dictionary = {}
	var script: Script = node.get_script()
	if not script:
		return props

	var prop_list := script.get_script_property_list()
	for prop in prop_list:
		var prop_name: String = prop["name"]
		var usage: int = prop["usage"]

		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if prop_name in ["size", "original_size", "transform_in_progress", "size_min", "size_default", "_resize_handle", "_resize_old_size", "_resize_context_active", "_scale_notification_cooldown"]:
			continue
		if prop_name.begins_with("_"):
			continue

		var value: Variant = node.get(prop_name)
		if value == null:
			continue

		var serialized = _variant_to_json(value)
		if serialized != null:
			props[prop_name] = serialized

	if node is ResizableNode3D and "size" in node:
		props["size"] = _variant_to_json(node.size)

	return props


func _variant_to_json(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	elif value is Vector2:
		return [value.x, value.y]
	elif value is Color:
		return [value.r, value.g, value.b, value.a]
	elif value is Transform3D:
		var basis: Array[float] = []
		for i in range(3):
			for j in range(3):
				basis.append(value.basis[i][j])
		return {"origin": [value.origin.x, value.origin.y, value.origin.z], "basis": basis}
	elif value is NodePath:
		return str(value)
	elif value is PackedScene:
		if value and value.resource_path:
			return value.resource_path
		return null
	elif value is Resource:
		return null
	elif value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _variant_to_json(value[key])
		return result
	elif value is Array:
		var result: Array = []
		for item in value:
			result.append(_variant_to_json(item))
		return result
	elif value is bool or value is int or value is float or value is String:
		return value
	return null


func _deserialize_scene(root: Node3D, data: Dictionary) -> void:
	var nodes: Array = data.get("nodes", [])

	for node_data in nodes:
		var type: String = node_data.get("type", "")
		if type == "Building":
			_apply_building_data(root, node_data)
			continue
		_instantiate_node(root, node_data)


func _instantiate_node(parent: Node3D, data: Dictionary) -> Node3D:
	var type: String = data.get("type", "")
	var scene_path: String = SceneRegistry.get_scene_path(type)
	if scene_path.is_empty():
		return null

	var scene: PackedScene = load(scene_path)
	if not scene:
		return null

	var node: Node3D = scene.instantiate()
	node.name = data.get("name", type)

	parent.add_child(node)
	node.owner = parent.owner if parent.owner else parent

	if data.has("transform"):
		_apply_transform(node, data["transform"])

	if data.has("properties"):
		_apply_properties(node, data["properties"])

	var children: Array = data.get("children", [])
	for child_data in children:
		_instantiate_node(node, child_data)

	return node


func _apply_transform(node: Node3D, transform_data: Dictionary) -> void:
	var origin_data: Array = transform_data.get("origin", [0, 0, 0])
	var basis_data: Array = transform_data.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])

	var origin := Vector3(origin_data[0], origin_data[1], origin_data[2])
	var basis := Basis()
	basis[0] = Vector3(basis_data[0], basis_data[1], basis_data[2])
	basis[1] = Vector3(basis_data[3], basis_data[4], basis_data[5])
	basis[2] = Vector3(basis_data[6], basis_data[7], basis_data[8])

	node.transform = Transform3D(basis, origin)


func _apply_properties(node: Node, properties: Dictionary) -> void:
	for prop_name in properties:
		var value: Variant = _json_to_variant(properties[prop_name])
		if value != null and prop_name in node:
			node.set(prop_name, value)


func _json_to_variant(value: Variant) -> Variant:
	if value is Array:
		if value.size() == 3 and value[0] is float:
			return Vector3(value[0], value[1], value[2])
		elif value.size() == 2 and value[0] is float:
			return Vector2(value[0], value[1])
		elif value.size() == 4 and value[0] is float:
			return Color(value[0], value[1], value[2], value[3])
		return value
	elif value is Dictionary:
		if value.has("origin") and value.has("basis"):
			var origin_data: Array = value["origin"]
			var basis_data: Array = value["basis"]
			var origin := Vector3(origin_data[0], origin_data[1], origin_data[2])
			var basis := Basis()
			basis[0] = Vector3(basis_data[0], basis_data[1], basis_data[2])
			basis[1] = Vector3(basis_data[3], basis_data[4], basis_data[5])
			basis[2] = Vector3(basis_data[6], basis_data[7], basis_data[8])
			return Transform3D(basis, origin)
		var result: Dictionary = {}
		for key in value:
			result[key] = _json_to_variant(value[key])
		return result
	return value


func _apply_building_data(root: Node3D, data: Dictionary) -> void:
	var props: Dictionary = data.get("properties", {})
	var building := root.get_node_or_null("Building")
	if not building:
		return
	for key in props:
		if key in building:
			building.set(key, props[key])


func _node_id(node: Node) -> String:
	return str(node.get_instance_id())
