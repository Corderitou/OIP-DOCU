# Reference: Debug Server API

> [!WARNING]
> **DEPRECATED.** The debug server is part of the deprecated **runtime editor**
> (code in `deprecated/runtime/core/debug_server.gd`), which is no longer the
> active component and is not maintained. This document is kept for historical
> reference only.

HTTP REST API endpoints for external control and monitoring of the OIP Runtime Editor.

## Overview

The debug server runs an embedded HTTP server on **port 9876** using a `TCPServer`. It allows external tools (scripts, dashboards, test harnesses) to inspect and control the running simulation.

## Base URL

```
http://localhost:9876
```

## Endpoints

### GET /status

Returns system status and simulation state.

**Response:**
```json
{
    "fps": 60,
    "memory": 134217728,
    "scene_children": 15,
    "simulation_running": false,
    "simulation_paused": false
}
```

---

### GET /nodes

Lists all direct children of the SceneRoot with position and type.

**Response:**
```json
{
    "nodes": [
        {
            "name": "BeltConveyor1",
            "type": "BeltConveyor",
            "position": [0, 0.25, 0]
        },
        {
            "name": "DiffuseSensor1",
            "type": "DiffuseSensor",
            "position": [0, 0.75, 1.0]
        }
    ]
}
```

---

### GET /node?path=NodeName

Returns detailed info for a specific node.

**Parameters:**
| Param | Type | Description |
|---|---|---|
| `path` | string | Node name or path under SceneRoot |

**Response:**
```json
{
    "name": "BeltConveyor1",
    "type": "BeltConveyor",
    "transform": {
        "origin": [0, 0.25, 0],
        "basis": [[1,0,0],[0,1,0],[0,0,1]]
    },
    "properties": {
        "speed": 2.0,
        "belt_color": [1, 1, 1, 1],
        "size": [4, 0.5, 1.524]
    }
}
```

---

### GET /selection

Returns the currently selected nodes.

**Response:**
```json
{
    "selected": ["BeltConveyor1"],
    "primary": "BeltConveyor1"
}
```

---

### GET /browser

Returns the Parts browser state.

**Response:**
```json
{
    "categories": ["Assemblies", "Conveyors", "Products", "Devices", "Robots", "Accessories"],
    "selected_part": "BeltConveyor"
}
```

---

### GET /tree

Returns the full scene hierarchy (max depth 4).

**Response:**
```json
{
    "tree": {
        "name": "SceneRoot",
        "type": "Node3D",
        "children": [
            {
                "name": "BeltConveyor1",
                "type": "BeltConveyor",
                "children": []
            }
        ]
    }
}
```

---

### GET /viewport

Returns viewport dimensions.

**Response:**
```json
{
    "width": 1920,
    "height": 1080
}
```

---

### GET /errors

Returns captured stdout/stderr from the current session.

**Response:**
```json
{
    "errors": [
        "ERROR: Physics body removed while simulation running"
    ]
}
```

---

### GET /screenshot

Returns a base64-encoded PNG of the SubViewport.

**Response:**
```json
{
    "image": "iVBORw0KGgoAAAANSUhEUgAA..."
}
```

---

### POST /command

Execute arbitrary GDScript via the `Expression` class.

**Request:**
```json
{
    "expression": "RuntimeSimulationBus.is_simulation_running()"
}
```

**Response:**
```json
{
    "result": false,
    "error": ""
}
```

**Available autoloads in expression context:**
- `RuntimeSimulationBus`
- `RuntimeSelection`
- `RuntimeUndoRedo`
- `RuntimeEditorToaster`
- `CommsHub`

**Example — start simulation:**
```json
{
    "expression": "RuntimeSimulationBus.start_simulation()"
}
```

---

### POST /input

Inject input events into the viewport.

**Request:**
```json
{
    "type": "click",
    "position": [960, 540],
    "button": 1
}
```

**Supported input types:**

| Type | Fields | Description |
|---|---|---|
| `click` | position, button | Mouse click at screen coordinates |
| `motion` | position, relative | Mouse movement |
| `key` | keycode, pressed | Keyboard event |

## Usage Examples

### Check if simulation is running

```bash
curl http://localhost:9876/status
```

### List all nodes

```bash
curl http://localhost:9876/nodes
```

### Start simulation via API

```bash
curl -X POST http://localhost:9876/command \
  -H "Content-Type: application/json" \
  -d '{"expression": "RuntimeSimulationBus.start_simulation()"}'
```

### Take a screenshot

```bash
curl http://localhost:9876/screenshot | jq -r '.image' | base64 -d > screenshot.png
```

## Implementation Details

- **Server:** `TCPServer` on port 9876 (`deprecated/runtime/core/debug_server.gd`)
- **Lines:** 488 lines of GDScript
- **Thread:** Runs in the main thread via `_process()` polling
- **Buffer:** Request/response are newline-delimited JSON
- **Security:** Localhost only (no authentication). Not intended for network exposure.

## See also

- [Architecture Overview](explanation-architecture.md) — Where the debug server fits
- [Runtime Editor Architecture](RUNTIME_EDITOR.md) — DebugServer implementation details
