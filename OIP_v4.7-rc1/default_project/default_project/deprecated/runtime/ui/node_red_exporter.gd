class_name NodeRedExporter
extends RefCounted

## Exports the simulator's configured OPC UA tags into a Node-RED flow file.
##
## Edits the `tree` of the first `opc-ua-server` node (from the
## @vitormnm/node-red-simple-opcua package) adding one variable per tag,
## and creates/updates a reader chain (inject -> function -> opcua-server-io
## -> debug) that periodically reads every simulator tag.
##
## Existing variables (same nodeId) are preserved untouched.

const PACKAGE_NAME := "@vitormnm/node-red-simple-opcua"

## Fixed ids for the reader chain so re-exports update instead of duplicating.
const ID_INJECT := "oip-sim-inject"
const ID_FUNC := "oip-sim-func"
const ID_IO := "oip-sim-io"
const ID_DEBUG := "oip-sim-debug"
const ID_SERVER := "oip-sim-server"
const ID_TAB := "oip-sim-tab"

## OPC UA data type + initial value per comms field (from the part scripts).
const FIELD_TYPES: Dictionary = {
	"speed_tag_name": {"type": "Float", "value": 0},
	"running_tag_name": {"type": "Boolean", "value": false},
	"tag_name": {"type": "Boolean", "value": false},
	"popup_tag_name": {"type": "Boolean", "value": false},
	"pushbutton_tag_name": {"type": "Boolean", "value": false},
	"lamp_tag_name": {"type": "Boolean", "value": false},
	"command_tag": {"type": "Int16", "value": 0},
	"execute_tag": {"type": "Boolean", "value": false},
	"done_tag": {"type": "Boolean", "value": false},
	"vacuum_tag": {"type": "Boolean", "value": false},
}


## Check that node-red-simple-opcua is installed next to the selected flow file.
static func check_package_installed(flow_path: String) -> bool:
	var dir := flow_path.get_base_dir()

	# Preferred: declared in package.json dependencies.
	var pkg_path := dir.path_join("package.json")
	if FileAccess.file_exists(pkg_path):
		var file := FileAccess.open(pkg_path, FileAccess.READ)
		if file:
			var data: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if data is Dictionary:
				var deps: Variant = data.get("dependencies", {})
				if deps is Dictionary and deps.has(PACKAGE_NAME):
					return true

	# Fallback: physically present in node_modules.
	return DirAccess.dir_exists_absolute(dir.path_join("node_modules").path_join(PACKAGE_NAME))


## Collect all OPC UA tags configured on scene nodes.
## Returns Array of {node_name, field, node_id, type, value, description}.
static func collect_tags(scene_root: Node3D, tag_groups: Array[Dictionary]) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	if not scene_root:
		return tags

	# Names of groups whose protocol is OPC UA.
	var opc_groups := {}
	for g in tag_groups:
		if int(g.get("protocol", -1)) == CommsPanel.PROTO_OPC_UA:
			opc_groups[str(g.get("name", ""))] = true

	var seen_node_ids := {}
	for child in scene_root.get_children():
		if not child is Node3D:
			continue
		if child.owner != scene_root:
			continue
		var type_name := SceneRegistry.get_type_for_node(child)
		if type_name.is_empty():
			continue
		var fields: Array = CommsPanel.NODE_COMMS_FIELDS.get(type_name, [])
		for field_name in fields:
			var fn: String = str(field_name)
			var tag_val = child.get(fn)
			if tag_val == null or str(tag_val).strip_edges().is_empty():
				continue
			var group_prop: String = "tag_group_name" if fn in CommsPanel.SHARED_TAG_GROUP_FIELDS else fn.replace("_tag_name", "_tag_group_name")
			var group_val = child.get(group_prop)
			if group_val == null or not opc_groups.has(str(group_val)):
				continue
			var node_id := str(tag_val).strip_edges()
			if seen_node_ids.has(node_id):
				continue
			seen_node_ids[node_id] = true
			var info: Dictionary = FIELD_TYPES.get(fn, {"type": "Boolean", "value": false})
			tags.append({
				"node_name": str(child.name),
				"field": fn,
				"node_id": node_id,
				"type": info["type"],
				"value": info["value"],
				"description": "%s.%s (simulador OIP)" % [child.name, fn],
			})
	return tags


## Merge the collected tags into the Node-RED flow file.
## Returns {ok: bool, added: int, skipped: int, error: String}.
static func export_to_flow(flow_path: String, tags: Array[Dictionary]) -> Dictionary:
	var result := {"ok": false, "added": 0, "skipped": 0, "error": ""}

	# ── Read & parse flow ───────────────────────────────────
	if not FileAccess.file_exists(flow_path):
		result["error"] = "File not found: %s" % flow_path
		return result
	var file := FileAccess.open(flow_path, FileAccess.READ)
	if not file:
		result["error"] = "Could not open %s" % flow_path
		return result
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		result["error"] = "Invalid JSON: %s" % json.get_error_message()
		return result
	var flow: Variant = json.data
	if not flow is Array:
		result["error"] = "Flow file is not a JSON array"
		return result

	# ── Locate (or create) tab and opc-ua-server node ───────
	var tab_id := ""
	var server: Dictionary = {}
	for entry in flow:
		if not entry is Dictionary:
			continue
		if tab_id.is_empty() and entry.get("type") == "tab":
			tab_id = str(entry.get("id", ""))
		if server.is_empty() and entry.get("type") == "opc-ua-server":
			server = entry

	if tab_id.is_empty():
		var tab := {
			"id": ID_TAB, "type": "tab", "label": "Simulador OIP",
			"disabled": false, "info": "", "env": [],
		}
		flow.append(tab)
		tab_id = ID_TAB

	if server.is_empty():
		server = _make_server_node(tab_id)
		flow.append(server)
	elif str(server.get("z", "")).is_empty():
		server["z"] = tab_id

	# ── Merge variables into the server tree ────────────────
	var tree: Dictionary = {}
	var tree_raw: Variant = JSON.parse_string(str(server.get("tree", "")))
	if tree_raw is Dictionary:
		tree = tree_raw
	if not tree.get("folders") is Array:
		tree["folders"] = []
	if not tree.get("objects") is Array:
		tree["objects"] = []
	if not tree.get("objectsTypes") is Array:
		tree["objectsTypes"] = []
	if not tree.get("nameSpaces") is Array or (tree["nameSpaces"] as Array).is_empty():
		tree["nameSpaces"] = [{"id": 2, "name": str(server.get("namespaceUri", "Node-RED OPC UA Server"))}]

	var folders: Array = tree["folders"]
	if folders.is_empty():
		folders.append({
			"name": "Simulador", "displayName": "", "description": "",
			"nodeId": "", "namespaceId": 2, "objectsType": "",
			"folders": [], "objects": [], "variables": [],
			"alarms": [], "methods": [], "objectsTypes": [],
		})
	var folder: Dictionary = folders[0]
	if not folder.get("variables") is Array:
		folder["variables"] = []
	var variables: Array = folder["variables"]

	# Existing nodeIds anywhere in the tree (any folder) are preserved.
	var existing := {}
	_collect_existing_node_ids(folders, existing)

	for tag in tags:
		if existing.has(tag["node_id"]):
			result["skipped"] = int(result["skipped"]) + 1
			continue
		variables.append({
			"name": _tag_display_name(str(tag["node_id"])),
			"type": tag["type"],
			"value": tag["value"],
			"access": "readwrite",
			"description": tag["description"],
			"displayName": "",
			"nodeId": tag["node_id"],
			"namespaceId": 2,
		})
		existing[tag["node_id"]] = true
		result["added"] = int(result["added"]) + 1

	server["tree"] = JSON.stringify(tree, "  ")

	# ── Create / update the reader chain ────────────────────
	_upsert_reader_chain(flow, tab_id, str(server.get("serverName", "Node-RED OPC UA Server")), tags)

	# ── Backup + write ──────────────────────────────────────
	var backup := FileAccess.open(flow_path + ".bak", FileAccess.WRITE)
	if backup:
		backup.store_string(text)
		backup.close()

	var out := FileAccess.open(flow_path, FileAccess.WRITE)
	if not out:
		result["error"] = "Could not write %s" % flow_path
		return result
	out.store_string(JSON.stringify(flow, "    "))
	out.close()

	result["ok"] = true
	return result


## Human-friendly name from a NodeId: "ns=2;s=Sensor1" -> "Sensor1".
static func _tag_display_name(node_id: String) -> String:
	var idx := node_id.rfind("=")
	if idx >= 0 and idx < node_id.length() - 1:
		return node_id.substr(idx + 1)
	return node_id


static func _collect_existing_node_ids(folders: Array, out: Dictionary) -> void:
	for f in folders:
		if not f is Dictionary:
			continue
		var vars: Variant = f.get("variables", [])
		if vars is Array:
			for v in vars:
				if v is Dictionary and v.has("nodeId"):
					out[str(v["nodeId"])] = true
		var sub: Variant = f.get("folders", [])
		if sub is Array:
			_collect_existing_node_ids(sub, out)


static func _make_server_node(tab_id: String) -> Dictionary:
	return {
		"id": ID_SERVER,
		"type": "opc-ua-server",
		"z": tab_id,
		"name": "",
		"resourcePath": "/",
		"serverName": "Node-RED OPC UA Server",
		"allowAnonymous": true,
		"port": 4840,
		"maxConnections": 10,
		"securityPolicy": "None",
		"securityMode": "None",
		"namespaceUri": "Node-RED OPC UA Server",
		"tree": "",
		"x": 700, "y": 80,
		"wires": [],
	}


static func _upsert_reader_chain(flow: Array, tab_id: String, server_name: String, tags: Array[Dictionary]) -> void:
	# Build the function body listing every simulator tag.
	var lines: Array[String] = []
	for tag in tags:
		lines.append('  { "name": %s, "path": %s }' % [
			JSON.stringify(_tag_display_name(str(tag["node_id"]))),
			JSON.stringify(str(tag["node_id"])),
		])
	var func_body := "msg.payload = [\n%s\n];\nreturn msg;" % ",\n".join(lines)

	var existing := {}
	for entry in flow:
		if entry is Dictionary and str(entry.get("id", "")) in [ID_INJECT, ID_FUNC, ID_IO, ID_DEBUG]:
			existing[str(entry["id"])] = entry

	if existing.has(ID_FUNC):
		# Chain already exists: only refresh the tag list.
		existing[ID_FUNC]["func"] = func_body
		return

	flow.append({
		"id": ID_INJECT, "type": "inject", "z": tab_id,
		"name": "Leer tags simulador",
		"props": [{"p": "payload"}],
		"repeat": "3", "crontab": "", "once": true, "onceDelay": 0.1,
		"topic": "", "payload": "", "payloadType": "date",
		"x": 160, "y": 240,
		"wires": [[ID_FUNC]],
	})
	flow.append({
		"id": ID_FUNC, "type": "function", "z": tab_id,
		"name": "Tags del simulador OIP",
		"func": func_body,
		"outputs": 1, "timeout": 0, "noerr": 0,
		"initialize": "", "finalize": "", "libs": [],
		"x": 380, "y": 240,
		"wires": [[ID_IO]],
	})
	flow.append({
		"id": ID_IO, "type": "opcua-server-io", "z": tab_id,
		"name": "Leer del OPC UA",
		"serverRef": server_name,
		"mode": "read", "identifierType": "nodeId",
		"tagPath": "", "tagNodeId": "", "methodName": "", "intervalMs": "",
		"inputs": 1, "outputs": 1,
		"x": 600, "y": 240,
		"wires": [[ID_DEBUG]],
	})
	flow.append({
		"id": ID_DEBUG, "type": "debug", "z": tab_id,
		"name": "Tags simulador",
		"active": true, "tosidebar": true, "console": false, "tostatus": false,
		"complete": "payload", "targetType": "msg", "statusVal": "", "statusType": "auto",
		"x": 810, "y": 240,
		"wires": [],
	})
