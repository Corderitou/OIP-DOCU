# Explanation: Communications Architecture

How OIP bridges GDScript simulation code with native industrial protocol libraries.

## The Problem

Industrial communication (OPC UA, Modbus TCP, EtherNet/IP, Siemens S7) requires:
- High-performance native I/O (C/C++ libraries)
- Thread-safe data exchange with the game loop
- Editor-time configuration without a running PLC connection
- Runtime behavior identical to editor behavior

The challenge: GDScript is too slow for real-time protocol handling, but the native libraries (open62541, libplctag) can't be called directly from GDScript without a bridge.

## The Approach: Three-Layer Architecture

```
┌─────────────────────────────────────────────────┐
│  Layer 3: Scene Nodes                           │
│  BeltConveyor, DiffuseSensor, SixAxisRobot...   │
│  Uses: OIPCommsTag (per-tag wrapper)            │
├─────────────────────────────────────────────────┤
│  Layer 2: GDScript Facade (CommsHub)            │
│  oip_comms_stub.gd (238 lines)                 │
│  Null-safe delegation to native singleton       │
├─────────────────────────────────────────────────┤
│  Layer 1: Native GDExtension                    │
│  OIPComms (C++ shared library)                  │
│  open62541 (OPC UA) + libplctag (Modbus/EIP)   │
└─────────────────────────────────────────────────┘
```

### Layer 1: Native GDExtension

The `OIPComms` singleton is a C++ shared library compiled for each platform (Windows, Linux, macOS, Android, iOS). It handles:

- **Connection management**: TCP sockets, OPC UA sessions, Modbus/EIP connections
- **Tag group registration**: Groups of tags that share a connection and polling rate
- **Polling**: Background thread reads all tags at the configured rate
- **Read/Write**: Thread-safe typed operations (bit, float32, int16, int32, uint8)
- **OPC UA browsing**: Address space exploration for the browser dock

The native library is loaded as a Godot singleton via `Engine.get_singleton("OIPComms")`.

### Layer 2: GDScript Facade (CommsHub)

`oip_comms_stub.gd` is loaded as the `CommsHub` autoload. Every method follows a **null-safe delegation pattern**:

```gdscript
func read_float32(group: String, tag: String) -> float:
    if _backend == null:
        return 0.0
    if not _backend.has_method("read_float32"):
        return 0.0
    return _backend.call("read_float32", group, tag) as float
```

This means:
- **Without the native library**: All methods return safe defaults (0, false, empty). The editor works for layout and configuration.
- **With the native library**: Methods delegate to the real implementation. The simulation communicates with actual PLCs.

The facade also:
- Manages internal `_tag_groups` tracking
- Emits signals for read/write events, errors, and connection status
- Provides `test_opc_ua()` for connectivity validation
- Handles simulation state awareness (`set_sim_running()`)

### Layer 3: Per-Tag Wrapper (OIPCommsTag)

Scene components don't call `CommsHub` directly for every read/write. Instead, they instantiate `OIPCommsTag` objects:

```gdscript
var _tag: OIPCommsTag

func _on_simulation_started():
    _tag = OIPCommsTag.new()
    _tag.register(speed_tag_group_name, speed_tag_name, 1)

func _physics_process(delta):
    if _tag.is_ready():
        speed = _tag.read_float32()
```

The tag wrapper handles:
- Registration with the CommsHub
- Group initialization tracking (`on_group_initialized()`)
- Readiness state (`is_ready()` = registered + initialized)
- Type-safe read/write pass-through

## Thread Safety Model

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  Poll Thread │     │  Thread-Safe     │     │  Game Thread  │
│  (native C++)│────►│  Data Buffer     │◄────│  (GDScript)  │
│              │     │                  │     │              │
│  Reads from  │     │  Last-poll values│     │  Reads buffer │
│  PLC at poll │     │  for each tag    │     │  Writes queue │
│  rate        │     │                  │     │  (immediate)  │
└──────────────┘     └──────────────────┘     └──────────────┘
```

**Read path**: The native poll thread reads all tags in a group at the configured rate. Results are stored in a thread-safe buffer. The game thread reads from this buffer — it never touches the PLC directly.

**Write path**: Writes from the game thread are queued and executed as soon as possible. They are also thread-safe.

**Poll-write conflict**: If a write is queued while a poll is in progress (e.g., 100 out of 200 tags have been read), the write waits until the poll completes. This prevents partial reads from seeing inconsistent state.

### Known bug: DLL write race (high-frequency writes)

> **Applies to the `OIPComms` binary (v4.7).** The GDExtension source is not in this repo — only prebuilt binaries in `addons/oip_comms/bin/`.

Despite the thread-safe design above, the native DLL has a real race between the **main-thread write API** and its **poll thread**: writing tags at high frequency (60Hz) — even when the value never changes — can corrupt the internal tag registry, creating an empty-named tag/group. Observed symptoms, in order:

1. `OIPComms: Failed to write tag: ` (empty tag name)
2. Three thread errors from the `CommsHub` stub (`Node::emit_signalp()` from the wrong thread)
3. `OIPComms: Failed to create tag: ` (empty) + `POLL ''` forever at ~12Hz
4. `comms_error` → `Simulation.stop()`

The corruption is stochastic: it reproduces in 1–9s depending on write rate and number of tags. It is triggered by the "write the same status bits every `_physics_process` frame" pattern (e.g., CeldaSpawner writing 3 bits × 60Hz). Single-tag 60Hz writes were clean in 15s tests; the risk scales with total write pressure.

**Mitigation (write-on-change, already in the base):**

- `OIPCommsTag.write_*()` skips writes whose value is identical to the last write (covers all parts: sensors, robots, gantry, AGV, conveyors). The cache is reset in `register()` and `on_group_initialized()` so a write is always emitted after each group init.
- `PlantComms.write_bit(tag, value, only_if_changed)` adds the same guard for multi-tag helpers.
- **Rule for new parts:** never write tags from `_physics_process` — write only on state changes (edges). Reads at any rate are safe (only the poll thread writes).
- Validate with `test_repro8.gd` (full demo scene, 8s): a clean run has zero `Failed to write`, `POLL ''`, or `comms_error` lines, with normal 1Hz `POLL 'PLCSIM'`.

**Related operational note:** a headless run can leave a zombie `OIP_v4.7-rc1` process behind (the DLL worker thread is not a daemon). The zombie locks the DLL, so the next `--headless --import` fails with `Can't open GDExtension dynamic library` plus a cascade `Invalid access to property 'tag_group_initialized'` (soft_plc_bridge). Kill lingering processes before importing. Also, the editor auto-runs the simulation during `--import` (EditorSimulationRunBar), so any write errors in the import log are the same DLL race, not an import problem.

## Editor vs. Runtime Behavior

### Editor Mode (Godot Editor)

1. `CommsHub` is loaded as autoload
2. `_ready()` tries `Engine.get_singleton("OIPComms")` — may succeed (GDExtension loaded) or fail (stub only)
3. If stub: all methods return defaults. Users configure tags but don't see live data.
4. The `oip_comms` editor plugin provides the Comms dock for tag group configuration.
5. The `tag_groups` plugin provides Inspector dropdowns for tag selection.
6. The `opc_ua_browser` plugin provides server browsing (requires native library).

### Runtime/Export Mode

1. `CommsHub` is loaded as autoload
2. `_ready()` acquires the native `OIPComms` singleton
3. All methods delegate to the real implementation
4. Polling starts when `set_enable_comms(true)` is called
5. Scene parts read/write tags via `OIPCommsTag` wrappers

### The Same Code

A `BeltConveyor` script calling `_tag.read_float32()` works identically in both modes. The facade handles the difference. This is the key insight: **the dual-mode design is in the autoloads, not in the part scripts**.

## Property Visibility

The `OIPCommsSetup` class provides static helpers that dynamically toggle property visibility in the Inspector:

```gdscript
OIPCommsSetup.validate_tag_property(property, node, "enable_comms", ...)
```

When `enable_comms` is false, tag-related properties (group name, tag name) are hidden from the Inspector. When true, they appear. This keeps the Inspector clean while making all configuration accessible.

## OPC UA Browsing

The OPC UA Browser uses the native library's browse API:

1. `OIPComms.browse_connect(endpoint)` — establishes a session
2. `OIPComms.browse_children(node_id)` — lazy-loads children
3. `OIPComms.browse_disconnect()` — closes the session

The browser dock in the editor calls these methods via `CommsHub`, which delegates to the native singleton. Node IDs can be copied to the clipboard for use as tag names.

## Data Persistence

| Data | Location | Format |
|---|---|---|
| Tag group definitions | `oip_data/tag_groups.cfg` | Godot ConfigFile |
| Enable comms/logging | `oip_data/comms_settings.cfg` | Godot ConfigFile |
| Per-node tag bindings | `user://comms_config.json` | JSON |

The editor's Comms dock manages `tag_groups.cfg`. The runtime COMMS panel manages `comms_config.json`. Both are restored on load.

## See also

- [Architecture Overview](explanation-architecture.md) — Where comms fits in the system
- [Communication Protocols Reference](reference-protocols.md) — Tag formats per protocol
- [OPC UA Configuration Guide](howto-opc-ua-configuration.md) — Step-by-step setup
- [Parts Catalog](reference-parts-catalog.md) — Tag fields per part type
