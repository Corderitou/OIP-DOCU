@tool
extends Node

## Lightweight HTTP debug server for the runtime editor.
## Exposes REST endpoints so an external MCP server can inspect/control the app.

signal request_received(method: String, path: String)

const PORT: int = 9876
const MAX_CONNECTIONS: int = 8

var _server: TCPServer
var _connections: Array = []
var _output_buffer: Array = []
var _max_buffer: int = 200
var _runtime_editor: Node = null
var _screenshot_pending: bool = false
var _screenshot_data: PackedByteArray = PackedByteArray()


func _ready() -> void:
	_server = TCPServer.new()
	var err: Error = _server.listen(PORT)
	if err == OK:
		print("[DebugServer] Listening on http://127.0.0.1:", PORT)
	else:
		push_warning("[DebugServer] Failed to listen on port " + str(PORT) + ": " + error_string(err))


func set_runtime_editor(editor: Node) -> void:
	_runtime_editor = editor


# Expose autoloads as properties so Expression can use them
func get_RuntimeSimulationBus():
	return RuntimeSimulationBus if has_node("/root/RuntimeSimulationBus") else null

func get_RuntimeSelection():
	return RuntimeSelection if has_node("/root/RuntimeSelection") else null

func get_RuntimeUndoRedo():
	return RuntimeUndoRedo if has_node("/root/RuntimeUndoRedo") else null


func _process(_delta: float) -> void:
	if not _server:
		return

	if _server.is_connection_available():
		if _connections.size() < MAX_CONNECTIONS:
			var conn: StreamPeerTCP = _server.take_connection()
			_connections.append({"peer": conn, "buffer": PackedByteArray(), "state": "reading"})
		else:
			var discard: StreamPeerTCP = _server.take_connection()
			discard.disconnect_from_host()

	var to_remove: Array = []
	for i in range(_connections.size()):
		var entry: Dictionary = _connections[i]
		var peer: StreamPeerTCP = entry["peer"]

		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			to_remove.append(i)
			continue

		var available: int = peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			if chunk[0] == OK:
				entry["buffer"] = entry["buffer"] + chunk[1]
				if _is_complete_request(entry["buffer"]):
					_process_request(peer, entry["buffer"])
					to_remove.append(i)

	for i in range(to_remove.size() - 1, -1, -1):
		var entry2: Dictionary = _connections[to_remove[i]]
		entry2["peer"].disconnect_from_host()
		_connections.remove_at(to_remove[i])


func _is_complete_request(data: PackedByteArray) -> bool:
	var text: String = data.get_string_from_utf8()
	if text.find("\r\n\r\n") == -1:
		return false
	if text.begins_with("POST") or text.begins_with("PUT"):
		var header_end: int = text.find("\r\n\r\n")
		var headers: String = text.substr(0, header_end)
		if headers.to_lower().find("content-length") != -1:
			var lines: Array = headers.split("\r\n")
			for line in lines:
				if line.to_lower().begins_with("content-length:"):
					var cl: int = line.split(":")[1].strip_edges().to_int()
					var body_start: int = header_end + 4
					return data.size() >= body_start + cl
		return false
	return true


func _process_request(peer: StreamPeerTCP, data: PackedByteArray) -> void:
	var text: String = data.get_string_from_utf8()
	var lines: Array = text.split("\r\n")
	var request_line: Array = lines[0].split(" ")
	var method: String = request_line[0]
	var full_path: String = request_line[1]

	var path_parts: Array = full_path.split("?")
	var path: String = path_parts[0]
	var query: String = ""
	if path_parts.size() > 1:
		query = path_parts[1]

	var body: String = ""
	var header_end: int = text.find("\r\n\r\n")
	if header_end != -1:
		body = text.substr(header_end + 4)

	var query_params: Dictionary = {}
	if not query.is_empty():
		for param in query.split("&"):
			var kv: Array = param.split("=")
			if kv.size() == 2:
				query_params[kv[0]] = kv[1]

	request_received.emit(method, path)

	var response_body: String = ""
	var status: int = 200

	match path:
		"/status":
			response_body = _handle_status()
		"/nodes":
			response_body = _handle_nodes()
		"/node":
			response_body = _handle_node(query_params)
		"/selection":
			response_body = _handle_selection()
		"/browser":
			response_body = _handle_browser()
		"/errors":
			response_body = _handle_errors()
		"/screenshot":
			response_body = _handle_screenshot()
		"/command":
			response_body = _handle_command(body)
		"/input":
			response_body = _handle_input(body)
		"/tree":
			response_body = _handle_tree()
		"/viewport":
			response_body = _handle_viewport_info()
		_:
			response_body = JSON.stringify({"error": "Not found: " + path})
			status = 404

	_send_response(peer, status, response_body)


func _send_response(peer: StreamPeerTCP, status: int, body: String) -> void:
	var status_text: String = "200 OK"
	match status:
		404: status_text = "404 Not Found"
		500: status_text = "500 Internal Server Error"

	var response: String = "HTTP/1.1 " + status_text + "\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Content-Length: " + str(body.length()) + "\r\n"
	response += "Connection: close\r\n"
	response += "\r\n"
	response += body

	peer.put_data(response.to_utf8_buffer())


func _handle_status() -> String:
	var scene_root: Node = null
	var child_count: int = 0
	if _runtime_editor:
		scene_root = _runtime_editor.get("_scene_root_3d")
		if scene_root:
			child_count = scene_root.get_child_count()

	return JSON.stringify({
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"memory": Performance.get_monitor(Performance.MEMORY_STATIC),
		"scene_children": child_count,
		"has_editor": _runtime_editor != null,
		"engine_version": Engine.get_version_info().string if Engine.has_method("get_version_info") else "unknown",
		"simulation_running": RuntimeSimulationBus.is_simulation_running() if RuntimeSimulationBus else false,
	})


func _handle_nodes() -> String:
	var result: Array = []
	if _runtime_editor:
		var scene_root: Node = _runtime_editor.get("_scene_root_3d")
		if scene_root:
			for child in scene_root.get_children():
				var info: Dictionary = {
					"name": child.name,
					"class": child.get_class(),
					"type": _get_type_name(child),
					"position": _vec3_to_array(child.position) if child is Node3D else null,
					"child_count": child.get_child_count(),
				}
				result.append(info)
	return JSON.stringify({"nodes": result, "count": result.size()})


func _get_type_name(node: Node) -> String:
	var script: Script = node.get_script()
	if script:
		var gn: String = script.get_global_name()
		if not gn.is_empty():
			return gn
	return node.get_class()


func _handle_node(query_params: Dictionary) -> String:
	if not query_params.has("path"):
		return JSON.stringify({"error": "Missing 'path' parameter"})

	var path: String = query_params["path"].uri_decode()
	if _runtime_editor == null:
		return JSON.stringify({"error": "No runtime editor"})

	var scene_root: Node = _runtime_editor.get("_scene_root_3d")
	if not scene_root:
		return JSON.stringify({"error": "No scene root"})

	var node: Node = scene_root.get_node_or_null(path)
	if not node:
		return JSON.stringify({"error": "Node not found: " + path})

	var info: Dictionary = {
		"name": node.name,
		"path": node.get_path(),
		"class": node.get_class(),
		"type": _get_type_name(node),
		"owner": node.owner.name if node.owner else "none",
	}

	if node is Node3D:
		info["transform"] = {
			"position": _vec3_to_array(node.position),
			"rotation": _vec3_to_array(node.rotation_degrees),
			"scale": _vec3_to_array(node.scale),
		}
		if node is MeshInstance3D and node.mesh:
			info["mesh"] = node.mesh.get_path() if node.mesh.resource_path else "built-in"

	var props: Array = []
	if node is Node3D:
		for prop in ["position", "rotation_degrees", "scale", "visible", "name"]:
			props.append({"name": prop, "value": node.get(prop), "type": typeof(node.get(prop))})
	info["properties"] = props

	return JSON.stringify(info)


func _handle_selection() -> String:
	if _runtime_editor == null:
		return JSON.stringify({"selected": []})

	var sel_mgr: Node = _runtime_editor.get("_selection_manager")
	if not sel_mgr:
		return JSON.stringify({"selected": []})

	var selected: Array = sel_mgr.get("selected") if sel_mgr.has_method("get") or "selected" in sel_mgr else []
	if selected == null:
		selected = []

	var result: Array = []
	for node in selected:
		if node is Node:
			result.append({
				"name": node.name,
				"path": node.get_path(),
				"type": _get_type_name(node),
			})
	return JSON.stringify({"selected": result, "count": result.size()})


func _handle_browser() -> String:
	if _runtime_editor == null:
		return JSON.stringify({"error": "No runtime editor"})

	var browser: Node = _runtime_editor.get("_parts_browser")
	if not browser:
		return JSON.stringify({"error": "No parts browser"})

	var all_items: Array = browser.get("_all_items") if "_all_items" in browser else []
	var current_cat: String = browser.get("_current_category") if "_current_category" in browser else ""
	var item_count: int = 0

	if browser.has_node("ItemList"):
		item_count = browser.get_node("ItemList").get_item_count()

	return JSON.stringify({
		"total_items": all_items.size() if all_items else 0,
		"current_category": current_cat,
		"visible_items": item_count,
		"pending_place": _runtime_editor.get("_pending_place_type") if "_pending_place_type" in _runtime_editor else "",
	})


func _handle_errors() -> String:
	return JSON.stringify({"errors": _output_buffer, "count": _output_buffer.size()})


func _handle_screenshot() -> String:
	if _runtime_editor == null:
		return JSON.stringify({"error": "No runtime editor"})

	var viewport_container: Node = _runtime_editor.get("_viewport_3d")
	if not viewport_container:
		return JSON.stringify({"error": "No viewport container"})

	var viewport: SubViewport = null
	if viewport_container.has_node("SubViewport"):
		viewport = viewport_container.get_node("SubViewport")
	elif viewport_container is SubViewport:
		viewport = viewport_container

	if not viewport:
		return JSON.stringify({"error": "No SubViewport found"})

	var image: Image = viewport.get_texture().get_image()
	if not image:
		return JSON.stringify({"error": "Failed to get viewport image"})

	var png_data: PackedByteArray = image.save_png_to_buffer()
	var b64: String = Marshalls.raw_to_base64(png_data)

	return JSON.stringify({
		"width": image.get_width(),
		"height": image.get_height(),
		"image_base64": b64,
	})


func _handle_command(body: String) -> String:
	if body.is_empty():
		return JSON.stringify({"error": "Empty body"})

	var parsed: Variant = JSON.parse_string(body)
	if parsed == null or not parsed is Dictionary:
		return JSON.stringify({"error": "Invalid JSON body"})

	var expr_str: String = parsed.get("expression", "")
	if expr_str.is_empty():
		return JSON.stringify({"error": "Missing 'expression' field"})

	var expr := Expression.new()
	var err: Error = expr.parse(expr_str)
	if err != OK:
		return JSON.stringify({"error": "Parse error: " + expr.get_error_text()})

	# Pass autoloads as local instance so expressions can call methods
	var result: Variant = expr.execute([], self, true)
	if expr.has_execute_failed():
		return JSON.stringify({"error": "Execute error: " + expr.get_error_text()})

	return JSON.stringify({"result": _variant_to_json_value(result), "type": typeof(result)})


func _handle_input(body: String) -> String:
	if body.is_empty():
		return JSON.stringify({"error": "Empty body"})

	var parsed: Variant = JSON.parse_string(body)
	if parsed == null or not parsed is Dictionary:
		return JSON.stringify({"error": "Invalid JSON body"})

	var action: String = parsed.get("action", "")
	match action:
		"click":
			var x: float = parsed.get("x", 0.0)
			var y: float = parsed.get("y", 0.0)
			var btn: int = parsed.get("button", 1)
			var pressed: bool = parsed.get("pressed", true)
			var event := InputEventMouseButton.new()
			event.position = Vector2(x, y)
			event.global_position = Vector2(x, y)
			event.button_index = btn as MouseButton
			event.pressed = pressed
			get_viewport().push_input(event)
			return JSON.stringify({"ok": true, "action": "click", "x": x, "y": y})
		"motion":
			var x2: float = parsed.get("x", 0.0)
			var y2: float = parsed.get("y", 0.0)
			var rel_x: float = parsed.get("relative_x", 0.0)
			var rel_y: float = parsed.get("relative_y", 0.0)
			var event2 := InputEventMouseMotion.new()
			event2.position = Vector2(x2, y2)
			event2.global_position = Vector2(x2, y2)
			event2.relative = Vector2(rel_x, rel_y)
			get_viewport().push_input(event2)
			return JSON.stringify({"ok": true, "action": "motion", "x": x2, "y": y2})
		"key":
			var key_code: int = parsed.get("key", 0)
			var key_pressed: bool = parsed.get("pressed", true)
			var event3 := InputEventKey.new()
			event3.keycode = key_code as Key
			event3.pressed = key_pressed
			get_viewport().push_input(event3)
			return JSON.stringify({"ok": true, "action": "key", "key": key_code})
		_:
			return JSON.stringify({"error": "Unknown action: " + action})


func _handle_tree() -> String:
	if _runtime_editor == null:
		return JSON.stringify({"error": "No runtime editor"})

	var scene_root: Node = _runtime_editor.get("_scene_root_3d")
	if not scene_root:
		return JSON.stringify({"error": "No scene root"})

	var tree: Dictionary = _build_tree(scene_root, 0, 4)
	return JSON.stringify(tree)


func _build_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	var result: Dictionary = {
		"name": node.name,
		"class": node.get_class(),
		"type": _get_type_name(node),
	}
	if node is Node3D:
		result["position"] = _vec3_to_array(node.position)

	if depth < max_depth and node.get_child_count() > 0:
		var children: Array = []
		for child in node.get_children():
			children.append(_build_tree(child, depth + 1, max_depth))
		result["children"] = children
		result["child_count"] = node.get_child_count()
	else:
		result["child_count"] = node.get_child_count()

	return result


func _handle_viewport_info() -> String:
	if _runtime_editor == null:
		return JSON.stringify({"error": "No runtime editor"})

	var viewport_container: Node = _runtime_editor.get("_viewport_3d")
	if not viewport_container:
		return JSON.stringify({"error": "No viewport container"})

	return JSON.stringify({
		"size": _vec2_to_array(viewport_container.size),
		"visible": viewport_container.visible,
		"stretch": viewport_container.stretch if viewport_container.has_method("get") or "stretch" in viewport_container else false,
	})


func _variant_to_json_value(val: Variant) -> Variant:
	if val is Vector2:
		return {"x": val.x, "y": val.y}
	elif val is Vector3:
		return {"x": val.x, "y": val.y, "z": val.z}
	elif val is Color:
		return {"r": val.r, "g": val.g, "b": val.b, "a": val.a}
	elif val is Transform2D:
		return {"x": _vec2_to_array(val.x), "y": _vec2_to_array(val.y), "origin": _vec2_to_array(val.origin)}
	elif val is Transform3D:
		return {"basis": _vec3_to_array(val.basis.x), "origin": _vec3_to_array(val.origin)}
	elif val is NodePath:
		return String(val)
	return val


func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _vec2_to_array(v: Vector2) -> Array:
	return [v.x, v.y]


func capture_output(line: String, type: int) -> void:
	_output_buffer.append({"text": line, "type": type, "time": Time.get_ticks_msec()})
	if _output_buffer.size() > _max_buffer:
		_output_buffer.pop_front()
