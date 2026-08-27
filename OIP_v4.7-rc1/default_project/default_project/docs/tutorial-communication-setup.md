# Tutorial: Communication Setup

> [!NOTE]
> **DEPRECATED.** The full-screen **COMMS panel** described in this tutorial is part
> of the deprecated **runtime editor** (code in `deprecated/runtime/`), no longer
> the active component and not maintained. Communication configuration now lives
> in the Godot editor's **Comms dock** (addon `oip_comms`). This tutorial is kept
> for historical reference.

Connect your simulation to a real PLC or OPC UA server. You'll configure a tag group, bind tags to conveyor and sensor parts, and watch live data flow between the simulation and an external controller.

## What you'll need

- A running simulation scene with at least one conveyor and one sensor
- Access to a PLC or OPC UA server (Ignition, TIA Portal, Logix, etc.)
- The server's IP address and port

## Step 1: Open the COMMS panel

**View > Toggle COMMS** from the toolbar, or use the menu. The COMMS panel takes over the full screen.

Press **Escape** or click the **Back** button to return to the editor.

## Step 2: Create a tag group

A tag group represents one connection to one PLC or OPC UA endpoint.

1. Click **Add Tag Group**.
2. Enter a name (e.g., "MyPLC").
3. Select a **Protocol**:
   - `ab_eip` — Allen-Bradley / Rockwell EtherNet/IP
   - `modbus_tcp` — Modbus TCP
   - `opc_ua` — OPC UA
   - `siemens put/get` — Siemens S7
4. Enter the **Gateway** (IP address) and any protocol-specific fields:
   - For EtherNet/IP: Gateway IP + Path (e.g., "1,0") + CPU type
   - For Modbus TCP: Gateway IP + Unit ID
   - For OPC UA: Endpoint URL (e.g., `opc.tcp://192.168.1.100:4840`)
   - For Siemens S7: PLC IP address
5. Set the **Polling Rate** (default: 100ms). This controls how often OIPComms reads all tags in this group.

## Step 3: Enable comms

Check the **Enable Comms** checkbox at the top of the COMMS panel. The simulation will not communicate with any device until this is checked.

Optionally check **Enable Logging** to see read/write activity in the console.

## Step 4: Bind tags to parts

1. Scroll down to **Scene Items** in the COMMS panel.
2. Find your conveyor (under Conveyors) or sensor (under Devices).
3. Expand the item to see its tag fields.
4. For a BeltConveyor:
   - Select the tag group ("MyPLC") from the dropdown
   - Enter `MyConveyorSpeed` in the Speed tag name field
   - Enter `MyConveyorRunning` in the Running tag name field
5. For a DiffuseSensor:
   - Select the tag group
   - Enter `MySensorOutput` in the Tag name field

Each tag field shows a colored activity dot:
- **Blue dot**: Tag is being read from the PLC
- **Green dot**: Tag is being written to the PLC

## Step 5: Test OPC UA connectivity

If using OPC UA:

1. Select your OPC UA tag group.
2. Click **Browse** in the COMMS panel. The OPC UA Browser dock opens.
3. It connects to your endpoint and displays the server's node tree.
4. Expand nodes to find variables. Select one and click **Copy Node ID**.
5. Paste the NodeId (e.g., `ns=2;s=MyVariable`) into a tag name field.

## Step 6: Run with comms

1. Start the simulation (`F5`).
2. The COMMS panel console shows real-time read/write events.
3. Write values from your PLC to control the conveyor speed or read sensor outputs.

The simulation reads from a thread-safe data buffer that holds the last polled value. Writing from the simulation occurs immediately. If a write is queued while a poll is in progress, the write waits until the poll completes.

## Step 7: Save your comms config

Click **Save** in the COMMS panel. The configuration is saved to `user://comms_config.json` and restored automatically on next load.

You can also save tag group definitions to `oip_data/tag_groups.cfg` via the editor's Comms dock (in Godot editor mode).

## What you learned

- Tag groups organize connections to individual PLCs or OPC UA endpoints
- Each part type has specific tag fields (speed, running, output, etc.)
- The polling rate controls read frequency; writes happen immediately
- OPC UA nodes can be browsed and copied directly from the editor
- Configurations persist across sessions

## Next steps

- [Protocol reference](reference-protocols.md) — Tag name formats for each protocol
- [Parts catalog](reference-parts-catalog.md) — Complete list of tag fields per part type
- [Node-RED export](howto-node-red-export.md) — Generate Node-RED flows from configured tags
