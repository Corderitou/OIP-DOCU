# Explanation: Architecture Overview

> [!WARNING]
> **DEPRECATED.** This document describes the **runtime editor** architecture
> (`runtime_editor.gd` + dual-mode autoloads), which is **no longer the active
> component** for building and simulating industrial scenes. The code has been
> moved to `deprecated/runtime/` and is kept only as historical reference; it is
> not maintained. The active workflow is the native Godot editor with the Parts
> dock (`addons/scene-library/`) and the `Simulation` autoload.

How the (deprecated) OIP Runtime Editor was structured, why it used the patterns it did, and how the pieces connected.

## The Problem

Building an industrial simulation editor requires solving two conflicting needs:

1. **Editor mode**: Full access to Godot's editor APIs (undo/redo, selection, simulation controls, inspector). Parts must behave identically whether running in the Godot editor or as a standalone app.
2. **Runtime/Export mode**: No editor APIs available. The same part scripts must work in an exported build without `EditorInterface`.

Traditional approaches either duplicate code for each mode or require complex conditional compilation. OIP solves this with a **dual-mode autoload architecture**.

## The Architecture

### Core Design: Signal Hub + Autoload Singletons

```
                    ┌─────────────────────────────────┐
                    │       runtime_editor.gd          │
                    │     (Central Signal Router)      │
                    └────────┬────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼─────┐      ┌──────▼──────┐      ┌─────▼──────┐
   │ Toolbar  │      │ PartsBrowser│      │SelectionMgr │
   │ (signals)│      │  (signals)  │      │  (signals)  │
   └──────────┘      └─────────────┘      └─────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                    ┌────────▼────────────────┐
                    │   Autoload Singletons    │
                    │  ┌────────────────────┐ │
                    │  │ RuntimeSimulationBus│ │
                    │  │ RuntimeSelection    │ │
                    │  │ RuntimeUndoRedo     │ │
                    │  │ RuntimeEditorToaster│ │
                    │  │ CommsHub            │ │
                    │  └────────────────────┘ │
                    └─────────────────────────┘
```

**Runtime_editor.gd** is the central orchestrator. It creates all managers in `_ready()`, connects ~40+ signals, and routes events to the appropriate handler. Components emit signals without knowing their consumers — loose coupling through the signal hub.

### Dual-Mode Autoloads

Every autoload has a **stub** (GDScript) and a **real implementation** (either editor integration or GDExtension):

| Autoload | Editor Mode | Runtime/Export Mode |
|---|---|---|
| RuntimeSimulationBus | Forwards to `EditorInterface.simulation_*` | Standalone state machine |
| RuntimeUndoRedo | Wraps `EditorInterface.get_editor_undo_redo()` | Wraps Godot's `UndoRedo` |
| RuntimeSelection | Forwards `EditorInterface.get_selection()` | Standalone selection array |
| RuntimeEditorToaster | Forwards `EditorInterface.get_editor_toaster()` | Standalone toast system |
| CommsHub (oip_comms_stub) | No-op stub | Delegates to native OIPComms GDExtension |

The **runtime-editor-bridge** plugin (moved to `deprecated/runtime-editor-bridge/`) connects `EditorInterface` signals to these stubs in editor mode. In exported builds, the stubs function independently.

This means a `BeltConveyor` script calling `RuntimeSimulationBus.is_simulation_running()` works identically in the editor, in the runtime standalone, and in an exported build. Zero conditional code.

### Deferred Physics Processing

Click events in `TransformTool` are buffered (`_pending_click`) and processed in `_physics_process()` rather than `_input()`. This ensures raycasts for selection and transform snapping operate on valid, up-to-date physics state. Without this, selecting a moving box during simulation would use stale physics data.

### Script-Driven UI

All UI components (Toolbar, PartsBrowser, InspectorPanel, CommsPanel, StatusBar) build their entire widget tree programmatically in `_ready()` rather than using `.tscn` files. This makes them fully dynamic — the Parts browser reads categories from `SceneRegistry`, the Inspector generates widgets by property type, and the COMMS panel rebuilds its item list from the scene tree.

### Custom Scene Format

OIP uses `.oip_scene.json` instead of Godot's `.tscn` format. See [Why Custom Scene Format](explanation-scene-format.md) for the rationale.

## Data Flow

```
User Input (keyboard/mouse)
    │
    ▼
InputManager ──signals──► runtime_editor.gd
    │                          │
    │                          ├──► SceneManager (save/load JSON)
    │                          ├──► SimulationController ──► RuntimeSimulationBus
    │                          ├──► ClipboardManager (copy/paste/delete)
    │                          ├──► TransformTool (move/rotate + grid snap)
    │                          ├──► SelectionManager (raycast + highlight)
    │                          ├──► ViewportCamera (orbit, WASD, zoom)
    │                          ├──► DebugServer (HTTP REST API)
    │                          ├──► StatusBar / NotificationBar
    │                          └──► CommsPanel ──► CommsHub ──► OIPComms GDExtension
    │
    ▼
SceneRoot (Node3D)
    ├── BeltConveyor1 (physics, animation, comms)
    ├── DiffuseSensor1 (raycast, detection, comms)
    ├── BoxSpawner1 (spawn timer, comms)
    └── ...
```

## Physics Layers

| Layer | Name | Used By |
|---|---|---|
| 1 | Static | Building walls, floor, ContainerTrailer |
| 2 | Dynamic | Diverter, SafetyGate |
| 3 | Belt | Belt conveyor surfaces, sensors |
| 4 | Box | Box collision detection |
| 5 | SimpleConveyorShape | Roller conveyor surfaces |
| 6 | — | Dispenser, Stringer bodies |
| 8 | — | Pallet, cargo (Despawner detection) |
| 10 | — | Box, Celda, Placer, Tira (RigidBody3D items) |
| 15 | — | Collision mask for physics items |
| 18 | — | ChainTransfer |

Sensors raycast against layer 4 (Box) to detect products (`collision_mask = 8`). Boxes, Celdas, Placers and Tira segments sit on layer 10 with mask 15 (Static, Dynamic, Belt, Box). AGV uses layer 0 with mask 10 (only detects physics items). Side guards use layer 4 for collision with zero friction.

## Key Design Decisions

1. **Composition over inheritance**: The main controller instantiates all managers rather than inheriting from them. Each manager is a focused, testable unit.

2. **Signal-based decoupling**: Components communicate through signals, not direct references. The toolbar doesn't know about the simulation controller — it emits `play_pressed`, and the main controller connects it to `SimulationController.start()`.

3. **Procedural geometry**: Conveyors, robots, and gantries build their meshes in code. This enables dynamic resizing, skew angles, and frame configurations without pre-authored meshes.

4. **Jolt Physics engine**: OIP uses Jolt Physics (not Godot's default) for more stable conveyor/box interactions. Configured with 120 physics ticks/second, 15 velocity steps, and 20 position steps.

5. **Physics on separate thread**: `run_on_separate_thread = true` keeps the UI responsive during heavy simulation loads.

## See also

- [Why Custom Scene Format](explanation-scene-format.md) — JSON vs .tscn tradeoffs
- [Communications Architecture](explanation-comms-architecture.md) — Stub/GDExtension bridge details
- [Runtime Editor Architecture](RUNTIME_EDITOR.md) — Detailed file-by-file breakdown *(DEPRECATED)*
