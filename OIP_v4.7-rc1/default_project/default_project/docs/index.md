# Open Industry Project — Documentation

Documentation for the Open Industry Project (OIP), a free and open-source warehouse/manufacturing simulation framework built with Godot 4, open62541, and libplctag.

## Quick Links

| Start here | Read this |
|---|---|
| New to OIP | [Tutorial: Getting Started](tutorial-getting-started.md) |
| Connect to a PLC | [Tutorial: Communication Setup](tutorial-communication-setup.md) |
| All parts/properties | [Reference: Industrial Parts Catalog](reference-parts-catalog.md) |
| Architecture overview | [Explanation: Architecture](explanation-architecture.md) |

## Tutorials (learn by doing)

- [Getting Started](tutorial-getting-started.md) — From install to a running simulation with conveyor and sensor
- [Communication Setup](tutorial-communication-setup.md) — Connect to a PLC or OPC UA server and bind tags

## How-to Guides (accomplish specific tasks)

- [Import Custom 3D Models](howto-import-models.md) — Add third-party CAD models to your simulation
- [Use Conveyor Snapping](howto-conveyor-snapping.md) — Align and connect conveyors with Ctrl+Shift+C *(runtime-editor feature — DEPRECATED)*
- [Grab, Cut and Release Tiras](howto-stringer-dispenser.md) — Stringer + Dispenser workflow: extend, cut, and drop tira rope chains
- [Configure OPC UA Communication](howto-opc-ua-configuration.md) — Set up tag groups, browse nodes, bind tags
- [Use Robot & Gantry Gizmos](howto-robot-gizmos.md) — Position robots with visual handles and IK
- [Calibrate the SixAxisRobot Grid](howto-six-axis-robot-grid.md) — Pickup orientation, rectangular head alignment, grid waypoints, and verification
- [Export Node-RED Flows](howto-node-red-export.md) — Generate Node-RED flows from configured OPC UA tags
- [Stream the Simulation Live](howto-camera-streaming.md) — Broadcast a live camera view over the LAN (VLC, browsers) with the CameraStreamer part

## Reference (look up facts)

- [Industrial Parts Catalog](reference-parts-catalog.md) — All 34 parts with properties, tags, and behavior
- [Communication Protocols](reference-protocols.md) — OPC UA, EtherNet/IP, Modbus TCP, Siemens S7 tag formats
- [Scene File Format](reference-scene-format.md) — `.oip_scene.json` schema and serialization *(runtime-editor format — DEPRECATED)*
- [Editor Keyboard Shortcuts](reference-shortcuts.md) — All keyboard shortcuts and mouse interactions
- [Editor Plugins](reference-plugins.md) — 14 addons: gizmos, comms dock, OPC UA browser, pilot mode, etc.
- [Debug Server API](reference-debug-server.md) — HTTP REST endpoints for external control *(part of the DEPRECATED runtime editor)*

## Explanation (understand why)

- [Architecture Overview](explanation-architecture.md) — Dual-mode design, signal hub, autoload singletons *(documents the DEPRECATED runtime editor)*
- [Why Custom Scene Format](explanation-scene-format.md) — JSON vs .tscn tradeoffs and design rationale
- [Communications Architecture](explanation-comms-architecture.md) — Stub/proxy pattern, thread safety, GDExtension bridge, DLL write race y write-on-change

## Deprecated Docs

> [!WARNING]
> The **Runtime Editor** is deprecated and no longer the active component. Its code
> lives in `deprecated/runtime/` and `deprecated/runtime-editor-bridge/` for
> historical reference only and is not maintained.

- [Runtime Editor Architecture](RUNTIME_EDITOR.md) — Detailed internal architecture of the deprecated runtime editor
