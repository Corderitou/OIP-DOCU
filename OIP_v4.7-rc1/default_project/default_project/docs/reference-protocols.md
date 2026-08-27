# Reference: Communication Protocols

Tag name formats and configuration for all four supported industrial protocols.

## Protocol Overview

| Protocol | Library | Tag Format | Use Case |
|---|---|---|---|
| EtherNet/IP | libplctag | CIP tag name | Allen-Bradley / Rockwell PLCs |
| Modbus TCP | libplctag | Register prefix + number | Modbus-compatible devices |
| OPC UA | open62541 | NodeId | OPC UA servers (Ignition, Kepware, etc.) |
| Siemens S7 PUT/GET | Custom | Register identifier | Siemens S7 1200/1500 |

---

## EtherNet/IP (`ab_eip`)

### Configuration

| Field | Description | Example |
|---|---|---|
| Gateway | PLC IP address | `192.168.1.10` |
| Path | Rack/slot location | `1,0` |
| CPU Type | PLC family | ControlLogix |

### CPU Types

- ControlLogix
- PLC5
- SLC500
- LogixPccc
- Micro800
- MicroLogix
- Omron

### Tag Name Format

The CIP tag name as defined in the PLC program:

| Example | Description |
|---|---|
| `MyTag` | Simple tag |
| `Program:MainProgram.MyTag` | Program-scoped tag |
| `myUDT.field` | UDT member |
| `myArray[0]` | Array element |

### Data Types

| OIP Data Type | CIP Type | Size |
|---|---|---|
| BOOL | BOOL | 1 bit |
| REAL | REAL | 4 bytes |
| INT | INT | 2 bytes |
| DINT | DINT | 4 bytes |
| BYTE | BYTE | 1 byte |

---

## Modbus TCP (`modbus_tcp`)

### Configuration

| Field | Description | Example |
|---|---|---|
| Gateway | Device IP address | `192.168.1.20` |
| Unit ID | Modbus slave address | `1` |

### Tag Name Format

Register type prefix followed by the register number:

| Prefix | Register Type | Address Range |
|---|---|---|
| `co` | Coil | 0-65535 |
| `di` | Discrete Input | 0-65535 |
| `hr` | Holding Register | 0-65535 |
| `ir` | Input Register | 0-65535 |

| Example | Description |
|---|---|
| `hr0` | Holding register 0 |
| `co21` | Coil 21 |
| `ir64000` | Input register 64000 |

### Data Types

| OIP Data Type | Modbus Mapping |
|---|---|
| BOOL | Coil (co) or Discrete Input (di) |
| REAL | Two consecutive holding registers (hr) |
| INT | Single holding register (hr) |

---

## OPC UA (`opc_ua`)

### Configuration

| Field | Description | Example |
|---|---|---|
| Endpoint | Full OPC UA URL | `opc.tcp://192.168.1.30:4840` |

The Gateway, Path, and CPU fields are hidden when OPC UA is selected.

### Tag Name Format

The full OPC UA NodeId:

| Example | Description |
|---|---|
| `ns=2;s=MyVariable` | String NodeId in namespace 2 |
| `ns=2;i=12345` | Numeric NodeId in namespace 2 |
| `ns=0;i=2259` | Server status (namespace 0) |

### Browsing

Use the built-in OPC UA Browser to explore the server's address space:
1. Select an OPC UA tag group in the COMMS panel.
2. Click **Browse**.
3. Expand the tree to find variables.
4. Click **Copy Node ID** to copy the NodeId for use as a tag name.

### Data Types

OPC UA auto-detects data types from the server's node metadata. The system supports:
- Boolean
- Float (32-bit)
- Integer (16-bit, 32-bit)
- Unsigned integer (8-bit)

---

## Siemens S7 PUT/GET (`s7`)

### Configuration

| Field | Description | Example |
|---|---|---|
| Gateway | PLC IP address | `192.168.1.40` |

### Tag Name Format

Register identifier using S7 memory area notation:

| Area | Syntax | Example |
|---|---|---|
| Input (digital) | `Ix.y` | `I0.0` |
| Output (digital) | `Qx.y` | `Q0.1` |
| Memory bit | `Mx.y` | `M0.5` |
| Input byte | `IBx` | `IB0` |
| Output byte | `QBx` | `QB0` |
| Memory byte | `MBx` | `MB0` |
| Input word | `IWx` | `IW0` |
| Output word | `QWx` | `QW0` |
| Memory word | `MDx` | `MD0` |
| Output double word | `QLx` | `QL0` |

### Notes

- Input memory space can be written if it does not overlap the rack and Profinet inputs.
- Output space can also be written under the same condition.
- The L notation (e.g., `QLx`) is a non-standard quad word notation specific to this implementation.

---

## Thread Safety Model

The OIPComms system uses a thread-safe data buffer:

1. **Read path**: A background thread polls all tags in a group at the configured rate. Results are stored in a thread-safe buffer. The simulation reads from this buffer (never directly from the PLC).

2. **Write path**: Writes from the simulation are queued and executed as soon as possible. They are also thread-safe.

3. **Poll-write conflict**: If a write is queued while a poll is in progress (e.g., 100 out of 200 tags have been read), the write waits until the poll completes before executing.

---

## See also

- [OPC UA Configuration Guide](howto-opc-ua-configuration.md) — Step-by-step setup
- [Parts Catalog](reference-parts-catalog.md) — Tag fields per part type
- [Communications Architecture](explanation-comms-architecture.md) — How the stub/GDExtension bridge works
