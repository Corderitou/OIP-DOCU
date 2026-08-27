# How to Export Node-RED Flows

> [!WARNING]
> **DEPRECATED.** The Node-RED export runs from the **COMMS panel**, which is part
> of the deprecated **runtime editor** (`deprecated/runtime/ui/node_red_exporter.gd`).
> The runtime editor is no longer the active component and is not maintained.
> This guide is kept for historical reference only.

Generate a Node-RED flow from configured OPC UA tags for visual PLC logic programming.

## Prerequisites

- OPC UA tag groups configured in the COMMS panel
- Tags bound to scene parts
- Node-RED installed (https://nodered.org/)

## Steps

### 1. Configure your tags

Set up tag groups and bind tags to parts via the COMMS panel. See [Configure OPC UA Communication](howto-opc-ua-configuration.md) for details.

### 2. Export the flow

The export is triggered from the COMMS panel's Node-RED export feature. The `NodeRedExporter` reads all configured OPC UA tag bindings and generates a Node-RED flow file.

The generated flow includes:
- **OPC UAItem nodes** for each configured tag
- **Inject/Debug nodes** for testing
- Connection to the configured OPC UA endpoint

### 3. Import into Node-RED

1. Open Node-RED in your browser (typically `http://localhost:1880`).
2. Click the hamburger menu > **Import**.
3. Paste or upload the generated flow JSON.
4. Click **Deploy**.

### 4. Test the flow

The exported flow provides ready-to-use OPC UA connections for:
- Reading sensor outputs
- Writing conveyor commands
- Monitoring robot states

## What gets exported

Each tag binding in the COMMS panel becomes an OPC UA item node in the flow. The export captures:
- Endpoint URL
- NodeId (tag name)
- Data type
- Read/write direction

## See also

- [OPC UA Configuration](howto-opc-ua-configuration.md) — Setting up tag groups
- [Communication Protocols](reference-protocols.md) — Tag formats
