# Reference: Editor Keyboard Shortcuts

> [!WARNING]
> **DEPRECATED.** The sections below that describe the **OIP Runtime Editor** —
> Tool Shortcuts, Viewport Navigation, View Presets, Axis Locking, Edit
> Operations, File Operations, Simulation, and Conveyor Snapping — belong to the
> deprecated runtime editor (`deprecated/runtime/`), which is no longer
> maintained. They are kept for historical reference only.
>
> The **Conveyor Gizmo Toggles**, **Editor Pilot Mode**, **Robot Interactions**,
> **Mouse Interactions**, **Context Menu Options**, and **Resize Handles** sections
> describe native Godot-editor plugins and remain valid.

All keyboard shortcuts and mouse interactions in the OIP Runtime Editor.

## Tool Shortcuts

| Key | Action |
|---|---|
| `Q` | Select mode |
| `W` | Move mode |
| `E` | Rotate mode |
| `R` | Rotate mode (alternative) |

## Viewport Navigation

| Key / Mouse | Action |
|---|---|
| Right-click + drag | Orbit camera |
| `WASD` | Move camera (Walk/Fly mode, hold right-click) |
| `Space` | Move up (Fly mode) |
| `Ctrl` (held) | Move down (Fly mode) |
| `Shift` (held) | Boost speed (4x) |
| `Mouse wheel` | Zoom (adjusts FOV 15-120 degrees) |
| `Shift + Mouse wheel` | Adjust fly speed |
| `B` | Toggle Walk/Fly camera mode |
| `F` | Focus camera on selected nodes |

## View Presets

| Key | View |
|---|---|
| `1` | Front |
| `2` | Back |
| `3` | Left |
| `4` | Right |
| `5` | Top |

## Axis Locking (Move/Rotate)

| Key | Action |
|---|---|
| `X` | Lock to X axis |
| `Y` | Toggle Y-axis move (vertical) |
| `Z` | Lock to Z axis |
| `V` | Toggle Y-axis lock (Move/Rotate) |

## Edit Operations

| Shortcut | Action |
|---|---|
| `Ctrl+Z` | Undo |
| `Ctrl+Y` | Redo |
| `Ctrl+C` | Copy selected nodes |
| `Ctrl+V` | Paste |
| `Ctrl+D` | Duplicate |
| `Delete` | Delete selected nodes |
| `Ctrl+G` | Group selected nodes |
| `Ctrl+Shift+G` | Ungroup |

## File Operations

| Shortcut | Action |
|---|---|
| `Ctrl+S` | Save scene |
| `Ctrl+Shift+S` | Conveyor snap |
| `Ctrl+O` | Open scene |
| `Ctrl+N` | New scene |

## Simulation

| Key | Action |
|---|---|
| `F5` | Toggle simulation (Play/Stop) |
| `Escape` | Cancel placement / Exit COMMS panel |

## Conveyor Snapping

> **DEPRECATED** (runtime-editor feature).

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` | Snap selected conveyors to active conveyor |

## Conveyor Gizmo Toggles

| Key | Action |
|---|---|
| `G` | Toggle sideguard gizmo mode |
| `.` | Toggle flow direction arrows |

## Editor Pilot Mode

| Key | Action |
|---|---|
| `Shift+R` | Toggle pilot mode (first-person walkthrough) |
| `E` (in pilot mode) | Interact with objects (pick up boxes, push pallets) |
| `Space` (in pilot mode) | Jump |
| `Shift` (in pilot mode) | Sprint |

## Robot Interactions

| Action | How |
|---|---|
| Rotate joint | Click + drag joint arc gizmo |
| Move end effector | Click + drag crosshair gizmo |
| Train waypoint | Click "Train Waypoint" in Inspector |
| Go to waypoint | Select waypoint, click "Go To Waypoint" |

## Mouse Interactions

| Action | How |
|---|---|
| Select node | Left-click on node |
| Multi-select | Shift + left-click |
| Rectangle select | Left-click drag (when nothing selected) |
| Context menu | Right-click on selected node |
| Place part | Left-click after dragging from Parts browser |
| Cancel placement | `Escape` |

## Context Menu Options

| Option | Action |
|---|---|
| Delete | Remove selected nodes |
| Copy | Copy to clipboard |
| Paste | Paste from clipboard |
| Duplicate | Copy + paste in place |
| Group | Create parent Node3D |
| Ungroup | Remove parent, keep children |

## Resize Handles (Conveyors)

| Handle | Axis | Behavior |
|---|---|---|
| Red (+X) | Length (head end) | Extends/shortens from head |
| Red (-X) | Length (tail end) | Extends/shortens from tail |
| Green (+Y) | Height (up) | Raises conveyor |
| Green (-Y) | Height (down) | Lowers conveyor |
| Blue (+Z) | Width (right) | Widens right side |
| Blue (-Z) | Width (left) | Widens left side |

## See also

- [Runtime Editor Architecture](RUNTIME_EDITOR.md) — Detailed input handling implementation
- [Editor Plugins](reference-plugins.md) — Plugin-specific interactions
