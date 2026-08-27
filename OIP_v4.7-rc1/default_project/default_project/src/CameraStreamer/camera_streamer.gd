@tool
class_name CameraStreamer
extends Node3D

## Live streaming camera. Serves the view of its internal camera over HTTP as
## an MJPEG stream so any device on the local network (VLC, a web browser on a
## phone) can watch the simulation live at http://<ip>:<port>/.

const BOUNDARY: String = "oipcamframe"
const MAX_CLIENTS: int = 8
const MAX_OUT_BUFFER: int = 4 * 1024 * 1024
const PORT_SCAN_RANGE: int = 10
const CAMERA_OFFSET: Vector3 = Vector3(0, 0.15, 0.2)

## Enable/disable the HTTP streaming server.
@export var streaming_enabled: bool = true:
	set(value):
		streaming_enabled = value
		if is_inside_tree():
			if streaming_enabled:
				_start_server()
			else:
				_stop_server()
		_update_state_visuals()

## TCP port for the HTTP server. Binds on all network interfaces, so external
## devices can connect via this machine's LAN IP. If the port is busy the next
## free port (up to +9) is used instead — check [member stream_url].
@export_range(1024, 65535) var port: int = 8090:
	set(value):
		port = value
		if is_inside_tree() and streaming_enabled:
			_stop_server()
			_start_server()

## Resolution of the streamed image.
@export var resolution: Vector2i = Vector2i(640, 360):
	set(value):
		resolution = Vector2i(clampi(value.x, 64, 1920), clampi(value.y, 64, 1080))
		if _sub_viewport:
			_sub_viewport.size = resolution

## Frames per second sent to connected stream clients.
@export_range(1, 30) var stream_fps: int = 15

## JPEG compression quality (higher = sharper image, more bandwidth).
@export_range(0.1, 1.0, 0.05) var jpeg_quality: float = 0.7

## Field of view of the internal camera in degrees.
@export_range(10.0, 120.0) var fov: float = 70.0:
	set(value):
		fov = clampf(value, 10.0, 120.0)
		if _camera:
			_camera.fov = fov

## Show a live preview of the camera image on the back of the camera body.
@export var show_preview: bool = true:
	set(value):
		show_preview = value
		if _screen:
			_screen.visible = show_preview

## Full URL of the live stream (read-only).
@export var stream_url: String = ""

## Number of currently connected clients (read-only).
@export var clients_connected: int = 0

var _server: TCPServer
var _clients: Array[Dictionary] = []
var _actual_port: int = -1
var _capture_accum: float = 0.0

@onready var _sub_viewport: SubViewport = $SubViewport
@onready var _camera: Camera3D = $SubViewport/Camera3D
@onready var _screen: MeshInstance3D = $Screen
@onready var _led: MeshInstance3D = $StatusLed


func _validate_property(property: Dictionary) -> void:
	if property.name == "stream_url" or property.name == "clients_connected":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _ready() -> void:
	_sub_viewport.size = resolution
	_sub_viewport.world_3d = get_world_3d()
	_camera.fov = fov
	_screen.visible = show_preview

	# Wire the preview screen to the internal camera's render target.
	var mat := _screen.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_screen.set_surface_override_material(0, mat)
	mat = mat.duplicate()
	mat.albedo_texture = _sub_viewport.get_texture()
	_screen.set_surface_override_material(0, mat)

	if streaming_enabled:
		_start_server()
	_update_state_visuals()


func _exit_tree() -> void:
	_stop_server()


func _process(delta: float) -> void:
	# The camera lives inside its own SubViewport, so its transform must be
	# synced manually to follow this part. Camera3D looks along -Z; parts in
	# OIP face +Z, so rotate half a turn.
	if _camera:
		_camera.global_transform = global_transform.translated_local(CAMERA_OFFSET).rotated_local(Vector3.UP, PI)

	if not _server:
		return

	_accept_connections()
	_poll_clients()
	_broadcast_frames(delta)
	_flush_clients()
	clients_connected = _clients.size()


func use() -> void:
	streaming_enabled = not streaming_enabled


# --- Server lifecycle ---------------------------------------------------


func _start_server() -> void:
	if _server:
		return
	_server = TCPServer.new()
	_actual_port = -1
	for candidate in range(port, port + PORT_SCAN_RANGE):
		if _server.listen(candidate, "*") == OK:
			_actual_port = candidate
			break
	if _actual_port == -1:
		push_warning("[CameraStreamer] No free port in range " + str(port) + "-" + str(port + PORT_SCAN_RANGE - 1))
		_server = null
		stream_url = ""
		return

	stream_url = "http://" + _get_lan_address() + ":" + str(_actual_port) + "/"
	print("[CameraStreamer] '", name, "' streaming live at ", stream_url)
	_toast("Camera streaming at " + stream_url)
	_update_state_visuals()


func _stop_server() -> void:
	for client in _clients:
		client["peer"].disconnect_from_host()
	_clients.clear()
	clients_connected = 0
	if _server:
		_server.stop()
		_server = null
	stream_url = ""
	_update_state_visuals()


func _get_lan_address() -> String:
	for address in IP.get_local_addresses():
		var ip := String(address)
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"


func _toast(message: String) -> void:
	if has_node("/root/RuntimeEditorToaster"):
		get_node("/root/RuntimeEditorToaster").push_toast(message, 0)


# --- Connection handling ------------------------------------------------


func _accept_connections() -> void:
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		_clients.append({
			"peer": peer,
			"request": PackedByteArray(),
			"out": PackedByteArray(),
			"mode": "reading",
		})


func _poll_clients() -> void:
	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			client["mode"] = "drop"
			continue
		if client["mode"] != "reading":
			continue
		var available: int = peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			if chunk[0] != OK:
				client["mode"] = "drop"
				continue
			client["request"] = client["request"] + chunk[1]
			var text: String = client["request"].get_string_from_utf8()
			if text.find("\r\n\r\n") != -1:
				_route_request(client, text)


func _route_request(client: Dictionary, text: String) -> void:
	var request_line: Array = text.split("\r\n")[0].split(" ")
	if request_line.size() < 2:
		client["mode"] = "drop"
		return
	var path: String = String(request_line[1]).split("?")[0]

	match path:
		"/", "/index.html":
			_queue_response(client, "200 OK", "text/html; charset=utf-8", _index_page().to_utf8_buffer())
			client["mode"] = "close"
		"/stream":
			var headers: String = "HTTP/1.1 200 OK\r\n"
			headers += "Content-Type: multipart/x-mixed-replace; boundary=" + BOUNDARY + "\r\n"
			headers += "Access-Control-Allow-Origin: *\r\n"
			headers += "Cache-Control: no-cache, no-store\r\n"
			headers += "Connection: close\r\n"
			headers += "\r\n"
			client["out"] = client["out"] + headers.to_utf8_buffer()
			client["mode"] = "stream"
			# Send a first frame immediately so viewers don't wait a tick.
			var jpeg := _capture_jpeg()
			if not jpeg.is_empty():
				client["out"] = client["out"] + _frame_part(jpeg)
		"/snapshot":
			var jpeg2 := _capture_jpeg()
			if jpeg2.is_empty():
				_queue_response(client, "500 Internal Server Error", "text/plain", "capture failed".to_utf8_buffer())
			else:
				_queue_response(client, "200 OK", "image/jpeg", jpeg2)
			client["mode"] = "close"
		_:
			_queue_response(client, "404 Not Found", "text/plain", ("Not found: " + path).to_utf8_buffer())
			client["mode"] = "close"


func _queue_response(client: Dictionary, status: String, content_type: String, body: PackedByteArray) -> void:
	var headers: String = "HTTP/1.1 " + status + "\r\n"
	headers += "Content-Type: " + content_type + "\r\n"
	headers += "Content-Length: " + str(body.size()) + "\r\n"
	headers += "Access-Control-Allow-Origin: *\r\n"
	headers += "Connection: close\r\n"
	headers += "\r\n"
	client["out"] = client["out"] + headers.to_utf8_buffer() + body


# --- Frame capture & broadcast -------------------------------------------


func _broadcast_frames(delta: float) -> void:
	var has_stream_clients := false
	for client in _clients:
		if client["mode"] == "stream":
			has_stream_clients = true
			break
	if not has_stream_clients:
		_capture_accum = 0.0
		return

	_capture_accum += delta
	var interval: float = 1.0 / float(stream_fps)
	if _capture_accum < interval:
		return
	_capture_accum = fmod(_capture_accum, interval)

	var jpeg := _capture_jpeg()
	if jpeg.is_empty():
		return
	var part := _frame_part(jpeg)
	for client in _clients:
		if client["mode"] != "stream":
			continue
		if client["out"].size() > MAX_OUT_BUFFER:
			# Client can't keep up — drop it instead of hoarding memory.
			client["mode"] = "drop"
			continue
		client["out"] = client["out"] + part


func _frame_part(jpeg: PackedByteArray) -> PackedByteArray:
	var header: String = "--" + BOUNDARY + "\r\n"
	header += "Content-Type: image/jpeg\r\n"
	header += "Content-Length: " + str(jpeg.size()) + "\r\n"
	header += "\r\n"
	return header.to_utf8_buffer() + jpeg + "\r\n".to_utf8_buffer()


func _capture_jpeg() -> PackedByteArray:
	if not _sub_viewport:
		return PackedByteArray()
	var image: Image = _sub_viewport.get_texture().get_image()
	if image == null:
		return PackedByteArray()
	image.convert(Image.FORMAT_RGB8)
	return image.save_jpg_to_buffer(jpeg_quality)


# --- Output flushing ------------------------------------------------------


func _flush_clients() -> void:
	var to_remove: Array = []
	for i in range(_clients.size()):
		var client: Dictionary = _clients[i]
		if client["mode"] == "drop":
			to_remove.append(i)
			continue
		var out: PackedByteArray = client["out"]
		if out.size() > 0:
			var peer: StreamPeerTCP = client["peer"]
			var result: Array = peer.put_partial_data(out)
			if result[0] != OK:
				to_remove.append(i)
				continue
			var sent: int = result[1]
			if sent > 0:
				client["out"] = out.slice(sent)
		if client["out"].size() == 0 and client["mode"] == "close":
			to_remove.append(i)

	for i in range(to_remove.size() - 1, -1, -1):
		var entry: Dictionary = _clients[to_remove[i]]
		entry["peer"].disconnect_from_host()
		_clients.remove_at(to_remove[i])


# --- Visual state ----------------------------------------------------------


func _update_state_visuals() -> void:
	if _led:
		_led.visible = streaming_enabled and _server != null


func _index_page() -> String:
	return """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OIP Live Camera — """ + String(name) + """</title>
<style>
body { margin: 0; background: #0d1117; color: #e6edf3; font-family: system-ui, sans-serif;
       display: flex; flex-direction: column; align-items: center; min-height: 100vh; }
h1 { font-size: 18px; font-weight: 600; margin: 16px 0 8px; }
img { max-width: 100%; border: 1px solid #30363d; border-radius: 6px; background: #000; }
p { color: #8b949e; font-size: 13px; }
a { color: #58a6ff; }
</style>
</head>
<body>
<h1>&#128249; OIP Live Camera &mdash; """ + String(name) + """</h1>
<img src="/stream" alt="Live stream">
<p><a href="/snapshot" download="snapshot.jpg">Download snapshot</a> &middot; MJPEG stream: <code>/stream</code></p>
</body>
</html>"""
