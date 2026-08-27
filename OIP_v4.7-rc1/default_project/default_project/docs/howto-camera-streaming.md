# How-to: Stream the Simulation Live Over the Network

Use the **CameraStreamer** part to broadcast a live camera view of your simulation to any device on the local network — VLC on a PC, a web browser on a phone, or any MJPEG-compatible client.

## How It Works

The CameraStreamer is a regular part with an internal `Camera3D` rendering to a `SubViewport`. An embedded HTTP server (a `TCPServer`, same pattern as the [Debug Server](reference-debug-server.md)) captures the viewport at a configurable frame rate, encodes each frame as JPEG, and serves them as a standard **MJPEG stream** (`multipart/x-mixed-replace`). No external dependencies, plugins, or GDExtensions are required — MJPEG over HTTP is natively playable by browsers and VLC.

```
Camera3D ──► SubViewport ──► Image ──► JPEG ──► HTTP (MJPEG) ──► LAN clients
   (in scene)   (offscreen)  (per frame)          port 8090
```

## Steps

### 1. Place the camera

1. Open the Parts browser and select the **Devices** category.
2. Click **CameraStreamer** and place it in the scene.
3. Aim it: the camera looks along the part's **+Z axis** (the lens side). Rotate/position it like any other part. The small screen on the back shows a live preview of what it sees.

The red LED on top is lit while the server is running.

### 2. Find the stream URL

When streaming is enabled (default), the part prints its URL to the console and shows a toast:

```
[CameraStreamer] 'CameraStreamer1' streaming live at http://192.168.1.42:8090/
```

You can also read the **Stream Url** property in the Inspector. The server binds on **all interfaces**, so the URL uses your machine's LAN IP.

### 3. Watch from another device

**Web browser (phone, tablet, PC):**
Open `http://<ip>:8090/` — a built-in viewer page shows the live stream.

**VLC:**
*Media → Open Network Stream* and enter:

```
http://<ip>:8090/stream
```

**Single snapshot (curl, scripts, dashboards):**

```bash
curl http://<ip>:8090/snapshot -o frame.jpg
```

### 4. Firewall

The first time you run it, Windows may ask to allow Godot through the firewall — accept for **private networks**, or external devices will not be able to connect.

## Endpoints

| Path | Content | Use with |
|---|---|---|
| `/` | HTML viewer page | Web browsers |
| `/stream` | MJPEG stream (`multipart/x-mixed-replace`) | VLC, browsers, OpenCV |
| `/snapshot` | Single JPEG frame | curl, scripts |

## Properties

| Property | Default | Description |
|---|---|---|
| `streaming_enabled` | true | Start/stop the HTTP server |
| `port` | 8090 | TCP port. If busy, the next free port (up to +9) is used |
| `resolution` | 640×360 | Stream resolution (64–1920 × 64–1080) |
| `stream_fps` | 15 | Frames per second sent to clients (1–30) |
| `jpeg_quality` | 0.7 | JPEG compression quality (0.1–1.0) |
| `fov` | 70° | Camera field of view (10–120°) |
| `show_preview` | true | Live preview screen on the camera body |
| `stream_url` | — | Read-only: full URL of the stream |
| `clients_connected` | — | Read-only: number of connected clients |

## Multiple Cameras

Place several CameraStreamer parts and give each a different `port` (e.g. 8090, 8091, 8092). If two cameras share a port, the second automatically takes the next free one — check each part's `stream_url`.

## Performance Tips

- Frames are only captured **while at least one client is watching** `/stream` — an idle camera costs almost nothing.
- Lower `resolution` and `stream_fps` are the biggest levers for CPU and bandwidth. 640×360 @ 15 fps is a good default; use 320×180 @ 10 fps for many simultaneous cameras.
- JPEG encoding happens on the main thread; very high settings (1080p @ 30 fps) can reduce editor FPS.
- Slow clients that can't keep up are dropped automatically instead of buffering unbounded memory.
- Up to **8 clients** per camera.

## Interacting

Clicking the camera during simulation (the `use()` action) toggles streaming on/off.

## Security Note

The stream has **no authentication** and binds on all network interfaces. It is intended for trusted local networks (lab, plant floor, home LAN). Do not expose the port to the internet.

## See also

- [Debug Server API](reference-debug-server.md) — the `/screenshot` endpoint for one-off captures of the editor viewport
- [Industrial Parts Catalog](reference-parts-catalog.md) — all parts and properties
