# Runtime Scene Editor — Architecture & Features

> [!WARNING]
> **DEPRECATED.** The runtime editor is no longer the active component for building
> and simulating industrial scenes. This functionality is deprecated and **not
> maintained**. The code has been moved to `deprecated/runtime/` and is kept only
> as historical reference. Do not build new features on top of it; the active
> workflow is the native Godot editor with the Parts dock
> (`addons/scene-library/`) and the Simulation autoload.

The runtime editor was the main application for building and simulating industrial scenes. It ran outside the Godot editor as a standalone Control-based UI. This document is kept for historical reference.

## Layout

```
RuntimeEditor (Control, root)
├── VBox (full-screen, main editor view)
│   ├── Toolbar              — File/Edit/View/Sim menus + tool buttons
│   ├── NotificationBar      — Toast messages
│   ├── MainArea (HBox)
│   │   ├── LeftPanel        — PartsBrowser (drag parts to place)
│   │   ├── LeftResizer      — Drag handle to resize LeftPanel (160–500px)
│   │   ├── Viewport3D       — SubViewportContainer with 3D scene
│   │   ├── RightResizer     — Drag handle to resize RightPanel (200–600px)
│   │   └── RightPanel       — InspectorPanel (node properties)
│   └── StatusBar            — Mode, axis, comms status, part count
└── COMMSPanel (full-screen, hidden by default)
```

## View Switching (COMMS Panel)

The COMMS panel is a **separate full-screen view**, not a panel inside the editor. It's a direct child of `RuntimeEditor` with `anchors_preset = 15` (full-screen).

- **Toggle COMMS**: `View → Toggle COMMS` (toolbar ID 603) or signal `toggle_comms_panel`
- **Exit COMMS**: Press `Escape` or click the `← Back` button in the COMMS header
- **Mechanism**: `_on_toggle_comms_panel()` toggles `_comms_panel.visible` and `$VBox.visible` inversely

```gdscript
func _on_toggle_comms_panel() -> void:
    var is_showing_comms := _comms_panel.visible
    _comms_panel.visible = not is_showing_comms
    $VBox.visible = is_showing_comms
```

## Scene Tree Structure

All placed parts live under `_scene_root_3d` (named "SceneRoot") inside the SubViewport. Only nodes with `owner == _scene_root_3d` are persisted — ghost nodes (placement previews) are added without owner.

## Auto-Naming

When placing parts, names are generated sequentially per type:

```
BeltConveyor → BeltConveyor1 → BeltConveyor2 → ...
DiffuseSensor → DiffuseSensor1 → DiffuseSensor2 → ...
```

**Implementation** (`runtime_editor.gd`):

```gdscript
func _unique_name(type_name: String) -> String:
    var count := 0
    for child in _scene_root_3d.get_children():
        if child.name.begins_with(type_name):
            count += 1
    if count == 0:
        return type_name
    return type_name + str(count + 1)
```

Used by `_place_part()` and `ClipboardManager.paste()`.

## Transform Tools

Three modes controlled by `TransformTool` (`core/transform_tool.gd`):

| Mode | Key | Behavior |
|------|-----|----------|
| SELECT | Q | Click to select, Shift+click for multi-select, drag for rect select |
| MOVE | W | Click+drag to move. Axis lock: X/Y/Z keys toggle per-axis constraint |
| ROTATE | E | Click+drag horizontal = Y-axis rotation |

**Axis Lock**:
- **X axis**: Raycasts against a plane at the node's Z position, constrains to X
- **Y axis**: Vertical mouse movement adjusts height (0.01 units per pixel)
- **Z axis**: Raycasts against a plane at the node's X position, constrains to Z
- **No lock**: Free move on the XZ plane at the node's Y height

**Axis Indicator** (`ui/axis_indicator.gd`):
- 3D arrow gizmo (red=X, green=Y, blue=Z) + rotation ring (yellow)
- Follows the selected node via `_process` tracking
- Shows active axis and mode (e.g., "ROTATE X")
- Updated on selection change and axis toggle

**X/Y/Z keys in runtime_editor.gd**:

```gdscript
if event.keycode == KEY_X:
    _transform_tool.set_axis_lock("x")
    _update_axis_indicator("x")
elif event.keycode == KEY_Y:
    _transform_tool.toggle_move_y()
    _update_axis_indicator("y")
elif event.keycode == KEY_Z:
    _transform_tool.set_axis_lock("z")
    _update_axis_indicator("z")
```

## Hover Tooltip

Raycasts from camera on every `_process` frame to detect hovered parts:

```gdscript
func _update_hover() -> void:
    # ... raycast from camera through mouse position ...
    # Walk up to find node owned by scene root
    var check: Node3D = hit_node as Node3D
    while check:
        if check.owner == _scene_root_3d:
            part = check
            break
        check = check.get_parent()
```

Shows a floating Label with:
- Node name and type: `BeltConveyor1  [BeltConveyor]`
- Position: `Pos: (2.0, 1.0, -3.0)`

## COMMS Panel (`ui/comms_panel.gd`)

Full-screen panel for configuring industrial communication (PLC/OPC UA tags).

### Architecture

```
COMMSPanel (PanelContainer)
├── Header (HBoxContainer)
│   ├── ← Back button (emits back_pressed signal)
│   └── "COMMS" title
├── Global Settings
│   ├── Enable Comms checkbox → OIPComms.set_enable_comms()
│   ├── Enable Logging checkbox → OIPComms.set_enable_log()
│   └── Tag Groups section
├── Tag Groups
│   ├── [+] Add Group button
│   └── Per-group: Name, Protocol, Gateway, Poll Rate, [-] Remove
└── Scene Items
    ├── Save / Load buttons (user://comms_config.json)
    └── Categorized node list (Conveyors, Devices, Actuators, Robots, Other)
```

### Scene Scanning

`_rebuild_items()` scans `_scene_root.get_children()` and filters:
- Must be `Node3D`
- Must have `owner == _scene_root` (excludes ghost nodes)
- Must have a type in `SceneRegistry` with comms fields defined in `NODE_COMMS_FIELDS`

```gdscript
for child in _scene_root.get_children():
    if not child is Node3D:
        continue
    if child.owner != _scene_root:
        continue
    var type_name := SceneRegistry.get_type_for_node(child)
    if type_name.is_empty() or not NODE_COMMS_FIELDS.has(type_name):
        continue
```

### Per-Node Comms Fields

Each part type has specific tag fields defined in `NODE_COMMS_FIELDS`:

| Type | Fields |
|------|--------|
| BeltConveyorAssembly, RollerConveyor, etc. | `speed_tag_name`, `running_tag_name` |
| DiffuseSensor, LaserSensor, ColorSensor | `tag_name` |
| PushButton | `pushbutton_tag_name`, `lamp_tag_name` |
| StackLight | `tag_name` |
| ChainTransfer | `speed_tag_name`, `popup_tag_name` |
| SixAxisRobot, Gantry | `command_tag`, `execute_tag`, `done_tag`, `vacuum_tag` |
| BladeStop, Diverter | `tag_name` |

Each node item shows:
- Expand/collapse toggle with node name
- Type label
- Enable Comms checkbox (if the node has `enable_comms` property)
- Tag Group dropdown (populated from configured tag groups)
- Tag Name text input

### Tag Groups

Stored as `Array[Dictionary]` with keys: `name`, `protocol`, `gateway`, `poll_rate`.

Protocols: `ab_eip`, `modbus_tcp`, `opc_ua`, `siemens put/get`

Tag groups are registered with `OIPComms` via:
```gdscript
OIPComms.clear_tag_groups()
for g in _tag_groups:
    OIPComms.register_tag_group(g["name"], protocol_str, g["gateway"], g["poll_rate"])
```

### Save/Load

Config saved to `user://comms_config.json`:
```json
{
    "tag_groups": [...],
    "version": 1
}
```

On load, tag groups are restored and re-registered with OIPComms.

### Lambda Safety

All lambdas that capture scene nodes use `is_instance_valid(node)` guards:

```gdscript
cb.toggled.connect(func(on: bool):
    if not is_instance_valid(node): return
    node.set("enable_comms", on)
)
```

This prevents crashes when nodes are deleted while the COMMS panel is open.

## Keyboard Shortcuts (InputManager)

| Key | Action |
|-----|--------|
| Q | Select mode |
| W | Move mode |
| E | Rotate mode |
| G | Toggle grid |
| V | Toggle Y-axis lock (Move/Rotate) |
| X / Y / Z | Axis lock for Move/Rotate |
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Ctrl+S | Save |
| Ctrl+Shift+S | Conveyor snap |
| Ctrl+O | Open |
| Ctrl+N | New scene |
| Ctrl+C | Copy |
| Ctrl+V | Paste |
| Ctrl+D | Duplicate |
| Ctrl+G | Group |
| Ctrl+Shift+G | Ungroup |
| Delete | Delete selected |
| Escape | Cancel placement / Exit COMMS panel |
| F5 | Toggle simulation |

## Resizable Panels (`ui/panel_resizer.gd`)

Drag handles between panels:
- **LeftResizer**: Resizes LeftPanel (160–500px), `side = 0`
- **RightResizer**: Resizes RightPanel (200–600px), `side = 1`

Uses `mouse_default_cursor_shape = CURSOR_HSIZE` on hover.

## Scene Persistence (`core/scene_manager.gd`)

Scenes are saved as `.oip_scene.json` with structure:
```json
{
    "version": 1,
    "name": "Scene Name",
    "description": "",
    "created": "...",
    "modified": "...",
    "nodes": [
        {
            "id": "...",
            "type": "BeltConveyor",
            "name": "BeltConveyor1",
            "transform": { "origin": [...], "basis": [...] },
            "properties": { ... },
            "children": [...]
        }
    ]
}
```

- **Save**: `_serialize_node()` reads `node.name`, transform, and script properties
- **Load**: `_instantiate_node()` restores name via `node.name = data.get("name", type)`
- **Clipboard**: `_serialize_node_recursive()` captures type, name, transform, and properties

## OIPComms Stub (`src/comms/oip_comms_stub.gd`)

The COMMS system depends on the `OIPComms` autoload. In development, a stub provides no-op methods:

- `get_enable_comms()` / `set_enable_comms()`
- `clear_tag_groups()` / `register_tag_group()`
- `read_bit()`, `write_bit()`, `read_float32()`, `write_float32()`, etc.
- `enable_comms_changed` signal

The real implementation is in the [oip-comms](https://github.com/Open-Industry-Project/oip-comms) GDExtension.

## File Structure

```
deprecated/runtime/
├── runtime_editor.gd          — Main controller (1080 lines)
├── runtime_editor.tscn        — Scene definition
├── core/
│   ├── transform_tool.gd      — Move/Rotate with axis lock
│   ├── input_manager.gd       — Keyboard shortcuts
│   ├── scene_manager.gd       — Save/Load JSON scenes
│   ├── scene_registry.gd      — Type→scene path mapping
│   ├── selection_manager.gd   — Node selection + raycasting
│   ├── clipboard_manager.gd   — Copy/Paste/Duplicate
│   ├── grid_system.gd         — Grid snapping
│   ├── simulation_controller.gd — Play/Pause/Stop
│   ├── viewport_camera.gd     — Walk/Orbit/Front/Back/Left/Right/Top camera
│   ├── debug_server.gd        — TCP debug interface
│   └── RuntimeEditorToaster.gd — Toast notification system
├── ui/
│   ├── toolbar.gd             — Menus and action buttons
│   ├── parts_browser.gd       — Draggable parts catalog
│   ├── inspector_panel.gd     — Node property editor
│   ├── comms_panel.gd         — COMMS full-screen panel (1160 lines)
│   ├── status_bar.gd          — Mode, axis, comms status
│   ├── notification_bar.gd    — Toast display
│   ├── axis_indicator.gd      — 3D axis gizmo + rotation ring
│   ├── panel_resizer.gd       — Draggable panel resize handles
│   ├── file_dialogs.gd        — Open/Save file dialogs
│   └── editor_theme.gd        — Dark theme generator
```
