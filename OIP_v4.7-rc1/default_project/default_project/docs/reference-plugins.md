# Reference: Editor Plugins

All 14 editor addons included with the Open Industry Project.

## Plugin Overview

| Plugin | Dock/Feature | Purpose |
|---|---|---|
| [oip_comms](#oip_comms) | Bottom dock: "Comms" | Industrial communication configuration |
| [oip_ui](#oip_ui) | "New Simulation" button | Bootstrap simulation scene + conveyor snapping |
| [opc_ua_browser](#opc_ua_browser) | Left-bottom dock: "OPC UA Browser" | Browse OPC UA server address spaces |
| [tag_groups](#tag_groups) | Inspector dropdown | Tag group selection in Inspector |
| [scene-library](#scene-library) | Bottom dock: "Parts" | Asset browser with thumbnails |
| [conveyor_gizmo](#conveyor_gizmo) | 3D viewport gizmos | Conveyor resize + side guard handles |
| [robot_gizmo](#robot_gizmo) | 3D viewport gizmos | Robot joint rotation + IK end effector |
| [gantry_gizmo](#gantry_gizmo) | 3D viewport gizmos | Gantry end effector positioning |
| [agv_gizmo](#agv_gizmo) | 3D viewport gizmos | AGV path & waypoint visualization |
| [dock_door_tool](#dock_door_tool) | 3D viewport key handler | Toggle dock door leaves with C |
| [scene_interop](#scene_interop) | Tool menu | Import/export web scene JSON |
| [st_editor](#st_editor) | Bottom dock: "ST" | Structured Text program editing & hot-swap |
| [runtime-editor-bridge](#runtime-editor-bridge) | Invisible (autoload bridge) *(DEPRECATED)* | Connects EditorInterface to runtime stubs |
| [editor-pilot-mode](#editor-pilot-mode) | Toolbar button + Shift+R | First-person scene walkthrough |

---

## oip_comms

**File:** `addons/oip_comms/`
**Purpose:** Adds a bottom dock for configuring OPC UA, Modbus TCP, EtherNet/IP, and Siemens S7 communication.

### Key Files

| File | Purpose |
|---|---|
| `oip_comms.gd` | EditorPlugin entry, creates "Comms" dock |
| `controls/oip_comms_dock.gd` | Main dock UI (181 lines) |
| `controls/tag_group.gd` | Tag group UI row (169 lines) |
| `bin/oip_comms.gdextension` | Native GDExtension (C++ comms backend) |

### Features

- Add/remove/configure tag groups with protocol selection
- Per-node tag binding with live activity dots
- OPC UA test connectivity
- Console with timestamped read/write logs
- Save/load configuration
- Node-RED flow export
- Native binaries for Windows, Linux, macOS, Android, iOS

---

## oip_ui

**File:** `addons/oip_ui/`
**Purpose:** Core UI plugin providing the "New Simulation" bootstrap and conveyor snapping.

### Key Files

| File | Purpose |
|---|---|
| `Plugin.gd` | Adds "New Simulation" button, routes Use key |
| `Autoload/ConveyorSnapping.gd` | 1132-line snapping engine |
| `roof_fade.gdshader` | Fades roof when looking down |

### Features

- One-click simulation scene creation (Node3D + Building)
- `Ctrl+Shift+C` conveyor snapping for all conveyor types
- Automatic side guard openings at T-junctions
- Frame rail trimming at junctions
- Full undo/redo for snap operations

---

## opc_ua_browser

**File:** `addons/opc_ua_browser/`
**Purpose:** Browse OPC UA server address spaces directly in the editor.

### Key Files

| File | Purpose |
|---|---|
| `opc_ua_browser.gd` | Plugin entry, creates left-bottom dock |
| `browser_dock.gd` | Tree browsing logic (217 lines) |
| `browser_dock.tscn` | UI layout |

### Features

- Connects to OPC UA endpoint via `OIPComms.browse_connect()`
- Lazy-loads children on tree item expand
- Shows node details: NodeId, Type, Value, Access, Description
- Copy Node ID to clipboard
- Color-codes Variable nodes in green
- Refresh button to reload tree

---

## tag_groups

**File:** `addons/tag_groups/`
**Purpose:** Custom Inspector dropdown for selecting tag groups on node properties.

### Key Files

| File | Purpose |
|---|---|
| `tag_groups.gd` | EditorInspectorPlugin + EditorProperty |

### Features

- Intercepts properties with `hint_string == "tag_group_enum"`
- Populates dropdown from `OIPComms.get_tag_groups()`
- Auto-refreshes when tag groups change
- Shows stale/unavailable groups with warning emoji

---

## scene-library

**File:** `addons/scene-library/`
**Purpose:** Full-featured asset browser for organizing and finding parts.

### Key Files

| File | Purpose |
|---|---|
| `plugin.gd` | Plugin entry, creates "Parts" bottom dock |
| `scripts/scene_library.gd` | Main UI (1092 lines) |
| `scripts/asset.gd` | Asset data model |
| `scripts/asset_collection.gd` | Collection CRUD |
| `scripts/collection_library.gd` | Library of collections |

### Features

- Tab-based collections (Equipment, Devices, Products, Misc)
- Thumbnail grid or list view with Ctrl+scroll resizing
- Alphabetical sorting with toggle
- Filter/search
- Multithreaded thumbnail generation via SubViewport
- Drag-and-drop for adding scenes
- Context menus: Open, Inherit, Copy Path, Delete, Show in FileSystem
- Auto-save every 10 seconds

---

## conveyor_gizmo

**File:** `addons/conveyor_gizmo/`
**Purpose:** 3D resize handles for conveyors and side guard manipulation.

### Key Files

| File | Purpose |
|---|---|
| `plugin.gd` | Registers gizmo + toggle buttons |
| `conveyor_gizmo_plugin.gd` | Core gizmo logic (539 lines) |

### Features

- **Normal mode:** 6 resize handles (X+, X-, Y+, Y-, Z+, Z-)
- **Sideguard mode:** Handles at guard front/back edges
  - Drag to resize
  - Ctrl+Click to split guard
  - Shift+Click to merge guards
- Toggle between modes with `G` key
- Flow direction arrow toggle with `.` key
- Full undo/redo integration

---

## robot_gizmo

**File:** `addons/robot_gizmo/`
**Purpose:** Interactive joint rotation handles and IK end effector for SixAxisRobot.

### Key Files

| File | Purpose |
|---|---|
| `robot_gizmo_plugin.gd` | Full gizmo logic (378 lines) |

### Features

- 6 color-coded joint arcs (red, orange, yellow, green, blue, purple)
- Drag interaction tracks mouse angle relative to projected pivot
- End effector subgizmo with IK solving
- Crosshair at tool tip in cyan
- Undo/redo for all operations
- Unshaded, no depth test, always-visible overlays

---

## gantry_gizmo

**File:** `addons/gantry_gizmo/`
**Purpose:** End effector positioning for Gantry (Cartesian robot).

### Key Files

| File | Purpose |
|---|---|
| `gantry_gizmo_plugin.gd` | Gantry gizmo (101 lines) |

### Features

- 3D crosshair at tool tip (cyan)
- Click within 20px of tool tip to drag
- Applies delta movement to X, Y, Z positions
- Axis mapping: local X → x_position, local Z → y_position, local -Y → z_position
- Undo/redo for movement

---

## agv_gizmo

**File:** `addons/agv_gizmo/`
**Purpose:** Visualizes the AGV path (home position + waypoints) directly in the 3D viewport.

### Key Files

| File | Purpose |
|---|---|
| `plugin.gd` | Plugin entry, registers the gizmo |
| `agv_gizmo_plugin.gd` | Gizmo drawing logic (105 lines) |

### Features

- Draws a green path line from `home_position` through each waypoint with arrowheads
- Yellow cross markers at each path point (lifted 0.05 m above the surface)
- Active only for AGV nodes with `show_gizmos` enabled and selected
- Unshaded, no depth test, always-visible overlays

---

## dock_door_tool

**File:** `addons/dock_door_tool/`
**Purpose:** Toggles dock door leaves from the 3D viewport.

### Key Files

| File | Purpose |
|---|---|
| `plugin.gd` | EditorPlugin key handler (39 lines) |

### Features

- Press `C` with a `DockDoor`/`DockDoorLeaf` selected to toggle the door leaf
- Resolves the leaf from any selected descendant node of a dock door
- No dock or menu UI — purely a viewport shortcut

---

## scene_interop

**File:** `addons/scene_interop/`
**Purpose:** Imports and exports the open scene to/from the web scene JSON format (`scene.json`).

### Key Files

| File | Purpose |
|---|---|
| `plugin.gd` | Tool menu items + import/export logic (131 lines) |
| `src/interop/scene_io.gd` | `OipSceneIO` — shared import/export engine |

### Features

- Tool menu: `Import Web Scene (scene.json)...` and `Export Web Scene (scene.json)...`
- Import replaces the open scene's contents with the recognized parts from the JSON
- Export serializes the current scene root to a `scene.json` file
- Full undo/redo integration for import

---

## st_editor

**File:** `addons/st_editor/`
**Purpose:** Bottom "ST" dock for writing and hot-swapping Structured Text programs into the running simulation.

### Key Files

| File | Purpose |
|---|---|
| `plugin.gd` | Plugin entry, creates the "ST" bottom dock |
| `st_editor_dock.gd` | Code editor UI (163 lines) |
| `st_monitor_overlay.gd` | In-viewport monitor overlay |

### Features

- `CodeEdit` editor with line numbers and current-line highlight
- **Check** button: compile-check the program against the embedded ST engine
- **Apply** button: hot-swap the program into the running simulation
- Status label showing program/engine state

---

## runtime-editor-bridge

> [!WARNING]
> **DEPRECATED.** This plugin belongs to the deprecated runtime editor. Its code
> has been moved to `deprecated/runtime-editor-bridge/` and is kept only for
> historical reference; it is not maintained.

**File:** `deprecated/runtime-editor-bridge/`
**Purpose:** Bridges EditorInterface signals to runtime autoload stubs.

### Key Files

| File | Purpose |
|---|---|
| `RuntimeEditorBridge.gd` | Bridge logic (87 lines) |

### Connections

| EditorInterface | → Runtime Stub |
|---|---|
| `simulation_started/stopped/pause_toggled` | `RuntimeSimulationBus` |
| `get_editor_undo_redo()` | `RuntimeUndoRedo.use_editor_undo_redo()` |
| `get_editor_toaster()` | `RuntimeEditorToaster` |
| `get_selection().selection_changed` | `RuntimeSelection.select_nodes()` |
| `transform_requested/transform_commited` | `RuntimeEditorStub` |

### Purpose

Without this bridge, part scripts using `RuntimeSimulationBus`, `RuntimeSelection`, etc. would have no data in the editor. This makes the same codebase work as both an editor plugin and a standalone exported application.

---

## editor-pilot-mode

**File:** `addons/editor-pilot-mode/`
**Purpose:** First-person character walkthrough in the editor.

### Key Files

| File | Purpose |
|---|---|
| `editor_pilot_mode.gd` | Plugin core (357 lines) |
| `default_character.gd` | WASD character with interaction (203 lines) |
| `default_character.tscn` | Capsule mesh + camera scene |

### Features

- `Shift+R` toggles pilot mode
- Spawns configurable character at editor camera position
- WASD movement, mouse look, sprint, jump
- Physics ray-based interaction (3m range)
- Box pickup and carry (E key to release)
- Pallet pushing with physics steering
- Crosshair and interaction prompt labels
- Forwards simulation shortcuts while in pilot mode
- Configurable character scene via project setting

---

## See also

- [Keyboard Shortcuts](reference-shortcuts.md) — All shortcuts including plugin-specific ones
- [Parts Catalog](reference-parts-catalog.md) — What each part does
- [Architecture Overview](explanation-architecture.md) — How plugins fit into the system
