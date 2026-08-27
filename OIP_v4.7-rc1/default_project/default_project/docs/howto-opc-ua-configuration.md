# How to Configure OPC UA Communication

> [!WARNING]
> **DEPRECATED.** The **COMMS panel** used throughout this guide is part of the
> deprecated **runtime editor** (code in `deprecated/runtime/`), which is no
> longer the active component and is not maintained. Communication configuration
> now lives in the Godot editor's **Comms dock** (addon `oip_comms`). This guide
> is kept for historical reference only.

Set up OPC UA tag groups, browse server nodes, and bind tags to simulation parts.

## Prerequisites

- An OPC UA server running (Ignition, Kepware, Unified Automation, etc.)
- The server's endpoint URL (e.g., `opc.tcp://192.168.1.100:4840`)

## Steps

### 1. Create an OPC UA tag group

1. Open the COMMS panel: **View > Toggle COMMS**.
2. Click **Add Tag Group**.
3. Name it (e.g., "OPCServer").
4. Set **Protocol** to `opc_ua`.
5. Enter the **Endpoint** URL (e.g., `opc.tcp://192.168.1.100:4840`).
6. Set the **Polling Rate** (default: 100ms).

When using OPC UA, the Gateway/Path/CPU fields are hidden — only the endpoint matters.

### 2. Browse the server

1. Click **Browse** next to your OPC UA tag group.
2. The OPC UA Browser dock opens and connects to your endpoint.
3. The server's address space displays as a tree starting from the "Objects" node.
4. Expand nodes to browse children (loaded on demand).
5. Select a node to see its details: NodeId, data type, current value, access level, description.
6. Click **Copy Node ID** to copy the NodeId to your clipboard (e.g., `ns=2;s=MyVariable`).

### 3. Bind tags to parts

1. Scroll to **Scene Items** in the COMMS panel.
2. Expand a part to see its tag fields.
3. Select your OPC UA tag group from the dropdown.
4. Paste the copied NodeId into the tag name field.

**Tag name format for OPC UA**: The full NodeId, e.g., `ns=2;s=MyVariable` or `ns=2;i=12345`.

### 4. Verify connectivity

Click **Test** on the tag group to verify the OPC UA connection. The test:
1. Validates the endpoint URL has an `opc.tcp://` prefix.
2. Connects via `browse_connect()`.
3. Disconnects via `browse_disconnect()`.
4. Returns success or an error message.

### 5. Monitor activity

- Start the simulation (`F5`).
- Watch the console in the COMMS panel for timestamped read/write events.
- Activity dots on each tag show live data exchange:
  - **Blue**: data read from server
  - **Green**: data written to server

### 6. Export to Node-RED

See [How to Export Node-RED Flows](howto-node-red-export.md) for generating a Node-RED flow from your configured OPC UA tags.

## Tag Data Types

| Part | Tag | Data Type | Direction |
|---|---|---|---|
| BeltConveyor | speed_tag_name | REAL (float32) | Read from PLC |
| BeltConveyor | running_tag_name | BOOL | Read from PLC |
| DiffuseSensor | tag_name | BOOL | Write to PLC |
| LaserSensor | tag_name | REAL (float32) | Write to PLC |
| ColorSensor | tag_name | DINT (int32) | Write to PLC |
| SixAxisRobot | command_tag | INT (int16) | Read from PLC |
| SixAxisRobot | execute_tag | BOOL | Read from PLC |
| SixAxisRobot | done_tag | BOOL | Write to PLC |
| SixAxisRobot | vacuum_tag | BOOL | Read from PLC |
| StackLight | tag_name | BYTE (uint8) | Read from PLC |
| BladeStop | tag_name | BOOL | Read/Write |
| PushButton | pushbutton_tag_name | BOOL | Write to PLC |
| PushButton | lamp_tag_name | BOOL | Read from PLC |

## See also

- [Communication Protocols Reference](reference-protocols.md) — All protocol tag formats
- [Communications Architecture](explanation-comms-architecture.md) — How the stub/GDExtension bridge works
- [Parts Catalog](reference-parts-catalog.md) — Complete tag fields per part
