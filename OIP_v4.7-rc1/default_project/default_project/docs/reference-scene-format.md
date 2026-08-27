# Reference: Scene File Format

The `.oip_scene.json` format used by OIP for saving and loading simulation scenes.

## Overview

OIP uses a custom JSON-based scene format instead of Godot's native `.tscn`. This enables:
- Version control friendly diffs
- Cross-version compatibility
- Programmatic scene generation
- Easy debugging and manual editing

## Schema

```json
{
    "version": 1,
    "name": "Scene Name",
    "description": "",
    "created": "2025-01-15T10:30:00Z",
    "modified": "2025-01-15T11:45:00Z",
    "nodes": [...]
}
```

### Top-level Fields

| Field | Type | Description |
|---|---|---|
| `version` | int | Format version (currently 1) |
| `name` | string | Scene name |
| `description` | string | User-provided description |
| `created` | string | ISO 8601 creation timestamp |
| `modified` | string | ISO 8601 last modification timestamp |
| `nodes` | array | Array of node dictionaries |

### Node Schema

Each entry in the `nodes` array:

```json
{
    "id": "BeltConveyor1",
    "type": "BeltConveyor",
    "name": "BeltConveyor1",
    "transform": {
        "origin": [0, 0, 0],
        "basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    },
    "properties": {
        "speed": 2.0,
        "belt_color": [1, 1, 1, 1],
        "size": [4, 0.5, 1.524]
    },
    "children": []
}
```

### Node Fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique identifier (typically the node name) |
| `type` | string | Part type (must match a registered type in SceneRegistry) |
| `name` | string | Display name (auto-generated: `BeltConveyor`, `BeltConveyor1`, etc.) |
| `transform` | object | Position and rotation |
| `properties` | object | Script-exported property values |
| `children` | array | Nested child nodes (same schema) |

### Transform Schema

```json
{
    "origin": [x, y, z],
    "basis": [
        [xx, xy, xz],
        [yx, yy, yz],
        [zx, zy, zz]
    ]
}
```

| Field | Type | Description |
|---|---|---|
| `origin` | float[3] | Position in world space |
| `basis` | float[3][3] | 3x3 rotation/scale matrix |

### Property Types

Properties are serialized based on their Godot type:

| Godot Type | JSON Format | Example |
|---|---|---|
| bool | boolean | `true` |
| int | integer | `42` |
| float | number | `2.5` |
| string | string | `"hello"` |
| Vector2 | float[2] | `[1.0, 2.0]` |
| Vector3 | float[3] | `[1.0, 2.0, 3.0]` |
| Color | float[4] | `[1.0, 0.0, 0.0, 1.0]` |
| Transform3D | object | `{"origin":[...],"basis":[[...],[...],[...]]}` |
| Dictionary | object | `{"key": "value"}` |
| Array | array | `[1, 2, 3]` |

## Serialization Process

1. `_serialize_node()` in `scene_manager.gd` reads each child of the scene root.
2. For each node: captures name, transform, and all script-exported properties via `get_property_list()`.
3. Recursively serializes children.
4. **Special cases**:
   - `Building` node: serialized separately with width/length/height sections and brightness.
   - `FlowDirectionArrow` children: skipped (purely visual, recreated on load).
   - Comms-related properties: included if set.

## Deserialization Process

1. `_instantiate_node()` looks up `SceneRegistry.get_scene_path(type)` to find the `.tscn`.
2. Instantiates the scene, restores name via `node.name = data.get("name", type)`.
3. Applies transform (origin + basis).
4. Restores properties via `node.set()` for each key-value pair.
5. Recursively processes children.

## Clipboard Format

Copy/paste uses the same node schema but with an additional offset:
- Pasted nodes are offset by +0.5m on the X axis to avoid overlap.
- The clipboard captures the full node tree including children.

## Example Scene

A minimal scene with a conveyor and a sensor:

```json
{
    "version": 1,
    "name": "Demo Line",
    "description": "Basic conveyor with sensor",
    "created": "2025-01-15T10:00:00Z",
    "modified": "2025-01-15T10:00:00Z",
    "nodes": [
        {
            "id": "BeltConveyor1",
            "type": "BeltConveyor",
            "name": "BeltConveyor1",
            "transform": {
                "origin": [0, 0.25, 0],
                "basis": [[1,0,0],[0,1,0],[0,0,1]]
            },
            "properties": {
                "speed": 2.0,
                "size": [4, 0.5, 1.524]
            },
            "children": []
        },
        {
            "id": "DiffuseSensor1",
            "type": "DiffuseSensor",
            "name": "DiffuseSensor1",
            "transform": {
                "origin": [0, 0.75, 1.0],
                "basis": [[1,0,0],[0,1,0],[0,0,1]]
            },
            "properties": {
                "max_range": 1.524,
                "show_beam": true
            },
            "children": []
        }
    ]
}
```

## Registered Types

The following types are recognized by `SceneRegistry`:

| Category | Types |
|---|---|
| Assemblies | BeltConveyorAssembly, RollerConveyorAssembly, CurvedBeltConveyorAssembly, CurvedRollerConveyorAssembly, BeltSpurConveyorAssembly, RollerSpurConveyorAssembly |
| Conveyors | BeltConveyor, RollerConveyor, BeltSpurConveyor, RollerSpurConveyor, CurvedBeltConveyor, CurvedRollerConveyor |
| Products | Box, Pallet, Celda, Placer, Tira |
| Spawners | BoxSpawner, PalletSpawner, Despawner, Dispenser |
| Devices | DiffuseSensor, LaserSensor, ColorSensor, PushButton, StackLight, CameraStreamer |
| Robots | SixAxisRobot, Gantry, Stringer |
| Accessories | BladeStop, ChainTransfer, Diverter, GenericData |

## See also

- [Architecture Overview](explanation-architecture.md) — Why the format exists
- [Why Custom Scene Format](explanation-scene-format.md) — Design rationale
- [Runtime Editor Architecture](RUNTIME_EDITOR.md) — SceneManager implementation details *(DEPRECATED)*
