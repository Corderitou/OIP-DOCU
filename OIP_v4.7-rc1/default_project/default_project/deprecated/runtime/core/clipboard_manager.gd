class_name ClipboardManager
extends RefCounted

var _clipboard: Dictionary = {}
var _has_clipboard: bool = false

var has_data: bool:
	get:
		return _has_clipboard


func copy(node: Node3D) -> void:
	if not node:
		return
	_clipboard = _serialize_node_recursive(node)
	_has_clipboard = true
	RuntimeEditorToaster.push_toast("Copied: " + node.name, RuntimeEditorToaster.SEVERITY_INFO)


func paste(parent: Node3D) -> Node3D:
	if not _has_clipboard or not parent:
		return null

	var type: String = _clipboard.get("type", "")
	var scene_path: String = SceneRegistry.get_scene_path(type)
	if scene_path.is_empty():
		return null

	var scene: PackedScene = load(scene_path)
	if not scene:
		return null

	var node: Node3D = scene.instantiate()
	var base_name: String = _clipboard.get("name", type)
	node.name = _unique_name(parent, base_name)

	# Undo: record the node creation
	RuntimeUndoRedo.create_action("Paste Part")
	RuntimeUndoRedo.add_do_reference(node)
	RuntimeUndoRedo.add_undo_method(node, "queue_free")

	parent.add_child(node)
	node.owner = parent.owner if parent.owner else parent

	if _clipboard.has("transform"):
		var t_data: Dictionary = _clipboard["transform"]
		var origin: Array = t_data.get("origin", [0, 0, 0])
		var offset := Vector3(0.5, 0, 0)
		node.position = Vector3(origin[0], origin[1], origin[2]) + offset

	if _clipboard.has("properties"):
		var props: Dictionary = _clipboard["properties"]
		for prop_name in props:
			var value: Variant = _json_to_variant(props[prop_name])
			if value != null and prop_name in node:
				node.set(prop_name, value)

	RuntimeUndoRedo.commit_action()
	RuntimeEditorToaster.push_toast("Pasted: " + node.name, RuntimeEditorToaster.SEVERITY_INFO)
	return node


func duplicate(node: Node3D) -> Node3D:
	if not node:
		return null
	copy(node)
	return paste(node.get_parent())


func delete(node: Node3D) -> void:
	if not node:
		return
	var parent := node.get_parent()
	if parent:
		RuntimeUndoRedo.create_action("Delete Part")
		RuntimeUndoRedo.add_do_method(node, "queue_free")
		RuntimeUndoRedo.add_undo_method(parent, "add_child", [node])
		RuntimeUndoRedo.commit_action()


func _serialize_node_recursive(node: Node) -> Dictionary:
	var type := SceneRegistry.get_type_for_node(node)
	if type.is_empty():
		return {}

	var data: Dictionary = {
		"type": type,
		"name": node.name,
	}

	if node is Node3D:
		var t := (node as Node3D).transform
		var basis_arr: Array[float] = []
		for i in range(3):
			for j in range(3):
				basis_arr.append(t.basis[i][j])
		data["transform"] = {
			"origin": [t.origin.x, t.origin.y, t.origin.z],
			"basis": basis_arr,
		}

	var props: Dictionary = {}
	var script: Script = node.get_script()
	if script:
		for prop in script.get_script_property_list():
			var prop_name: String = prop["name"]
			var usage: int = prop["usage"]
			if usage & PROPERTY_USAGE_STORAGE == 0:
				continue
			if prop_name.begins_with("_") or prop_name in ["size", "original_size"]:
				continue
			var value: Variant = node.get(prop_name)
			if value != null:
				var serialized = _variant_to_json(value)
				if serialized != null:
					props[prop_name] = serialized
	if not props.is_empty():
		data["properties"] = props

	return data


func _variant_to_json(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	elif value is Vector2:
		return [value.x, value.y]
	elif value is Color:
		return [value.r, value.g, value.b, value.a]
	elif value is bool or value is int or value is float or value is String:
		return value
	return null


func _json_to_variant(value: Variant) -> Variant:
	if value is Array:
		if value.size() == 3 and value[0] is float:
			return Vector3(value[0], value[1], value[2])
		elif value.size() == 2 and value[0] is float:
			return Vector2(value[0], value[1])
		elif value.size() == 4 and value[0] is float:
			return Color(value[0], value[1], value[2], value[3])
	return value


func _unique_name(parent: Node3D, type_name: String) -> String:
	var count := 0
	for child in parent.get_children():
		if child.name.begins_with(type_name):
			count += 1
	if count == 0:
		return type_name
	return type_name + str(count + 1)
