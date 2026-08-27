# Comms del simulador — referencia

## Cómo registran tags las partes

Cada parte usa el wrapper `OIPCommsTag` (autoload `CommsHub` = facade null-safe,
`src/comms/oip_comms_stub.gd`):

```gdscript
var _tag := OIPCommsTag.new()

func _on_simulation_started() -> void:
    if enable_comms:
        _tag.register(tag_group_name, tag_name, OIPComms.TAG_TYPE_BOOL)

func _tag_group_polled(group: String) -> void:
    if not enable_comms or not _tag.matches_group(group):
        return
    var valor := _tag.read_bit()   # o read_float32()/read_int16()/read_int32()/read_uint8()
    # escribir: _tag.write_bit(v) / _tag.write_float32(v) / ...
```

- `enable_comms` es una prop exportada de cada parte; si es false, los tags no se registran
  y las props de tag quedan ocultas en el Inspector (`OIPCommsSetup.validate_tag_property`).
- `tag_group_name` por defecto lo asigna `OIPCommsSetup.default_tag_group(...)` → `PLCSIM`.
- La parte no toca el PLC directamente: lee/escribe el buffer del grupo en `_tag_group_polled`.
- En el entorno actual el grupo `PLCSIM` (protocol `2` = `opc_ua`) apunta a
  `opc.tcp://localhost:4840` → el simulador es **cliente** del server OPC UA de Node-RED.

## Write-on-change (carrera del DLL)

`OIPCommsTag.write_*` descarta automáticamente writes con el MISMO valor que el último
write (caché por tag; se resetea en `register()` y `on_group_initialized()` para forzar
un write tras cada init de grupo).

**Por qué:** el DLL `libOIP-COMMS` (GDExtension, binario en `addons/oip_comms/bin/`) tiene
una carrera real entre los writes del main thread y su thread de polling: escribir a 60Hz
aunque el valor no cambie puede corromper su registro interno → `OIPComms: Failed to write
tag: ` (tag vacío) + `POLL ''` a 12Hz + `comms_error` → `Simulation.stop()`. Es
estocástico (1-9s) y crece con el nº de tags escritos por frame. **Regla: nunca escribir
tags desde `_physics_process`** — escribir solo en flancos/cambios de estado. Las **lecturas**
a cualquier ritmo son seguras. `PlantComms.write_bit(tag, value, only_if_changed)` añade el
mismo guard a nivel de helper multi-tag (CeldaSpawner/Maquina).

## Tag group (oip_data/tag_groups.cfg)

```
[group_0]
name="PLCSIM"
polling_rate="30"
protocol="2"               # 2 = opc_ua
gateway="opc.tcp://localhost:4840"
path="1,0"
cpu="ControlLogix"
```

## Latencia: el poll del simulador

El `polling_rate` del grupo **es la cadencia del bucle OPC UA del simulador** (DLL
`libOIP-COMMS`, thread de polling): cada ciclo el simulador lee los tags de los que es
cliente (velocidades, comandos) y descarga los writes pendientes (sensores, running, done).
Reglas:

- **Los reads son seguros a cualquier ritmo** (la carrera del DLL es solo de writes); bajar
  el poll solo aumenta tráfico de lectura local, que es barato.
- Los **writes siguen siendo on-change** (`OIPCommsTag`), así que bajar el poll no aumenta
  la frecuencia efectiva de escritura → no dispara la carrera del DLL.
- **Ajuste de latencia**: el retardo sensor→cintas es
  `poll(sim→server) + bucle Node-RED + poll(server→sim)`. Con `polling_rate=30` y bucle de
  control a 50 ms el peor caso queda ~110 ms. Ver `references/control-flow.md` →
  "Latencia de control".

## Tipos de datos

| Simulador | OPC UA | Constante OIPComms |
|---|---|---|
| Bool | Boolean | `TAG_TYPE_BOOL` |
| Float32 | Float (REAL) | `TAG_TYPE_FLOAT32` |
| Int16 | Int16 (INT) | `TAG_TYPE_INT16` |
| Int32 | Int32 (DINT) | `TAG_TYPE_INT32` |
| UInt8 | UInt8 (BYTE) | `TAG_TYPE_UINT8` |

## Propiedades de tag por tipo de parte

| Parte | Props de tag | Tipos | Dirección |
|---|---|---|---|
| BeltConveyor / BeltSpur / CurvedBelt / Roller / CurvedRoller | `speed_tag_name`, `running_tag_name` | Float32, Bool | speed = **read**, running = **write** |
| TurntableConveyor | `speed_tag_name`, `target_angle_tag_name` | Float32 | read |
| ChainTransfer | `speed_tag_name`, `popup_tag_name` | — | read |
| DiffuseSensor | `tag_name` | Bool | **write** (sim→PLC) |
| LaserSensor | `tag_name` | Float32 | **write** |
| ColorSensor | `tag_name` | Int32 (DINT) | **write** |
| PushButton | `pushbutton_tag_name`, `lamp_tag_name` | Bool, Bool | pushbutton = **write**, lamp = **read** |
| StackLight | `tag_name` | UInt8 (BYTE, bitmask) | **read** |
| SixAxisRobot / Gantry | `command_tag`, `execute_tag`, `done_tag`, `vacuum_tag` | Int16, Bool, Bool, Bool | command/execute/vacuum = **read**, done = **write** |
| VastagoNeumatico | `tag_name` | Bool | **read + write** (extend) |
| CeldaSpawner (tipo Maquina) | `cmd_tag`, `exec_tag`, `done_tag`, `running_tag`, `ready_tag`, `count_tag`, `auto_enable_tag`, `rate_tag` | Int32, Bool, Bool, Bool, Bool, Int32, Bool, Float | cmd/exec/auto_enable/rate = **read**; done/running/ready/count = **write** |
| Maquina1 | `cut_tag`, `release_tag`, `z_tag`, `y_tag`, `speed_tag` | Bool, Bool, Float, Float, Float | **read** (PLC comanda la máquina) |
| AGV | `command_tag`, `execute_tag`, `done_tag`, `lift_tag` | — | command/execute/lift = read, done = write |
| BladeStop / Diverter | `tag_name` | Bool | read (blade read/write) |

> "read" = el simulador **lee** del PLC (Node-RED) → para controlar una parte desde
> Node-RED se escribe en esa variable. "write" = el simulador **escribe** hacia el PLC
> → para conocer el estado hay que leerla desde Node-RED.

## Tag_name = NodeId completo

En `Simulation.tscn` los `tag_name` ya vienen como NodeId completo, p. ej.:

```
speed_tag_name = "ns=2;s=BeltConveyor_Speed"
running_tag_name = "ns=2;s=BeltConveyor_Running"
```

Los tags tipo Maquina (CeldaSpawner) usan sufijos `_CMD`, `_EXEC`, ... que en modo
**OPC UA deben ser NodeIds completos también**:

```
cmd_tag = "ns=2;s=S1_CMD"
auto_enable_tag = "ns=2;s=S1_AUTO_ENABLE"
```

> **Gotcha conocido (bug real):** `CeldaSpawner._tag()` (celda_spawner.gd, ~línea 175) hace
> `STATION_PREFIX + suffix` si el sufijo no contiene `=`. Con `cmd_tag = "_CMD"` el
> resultado es `S1_CMD` **sin** `ns=2;s=`, y el parser OPC UA falla
> (`Failed to parse OPC UA node ID ... BadDecodingError`) → OIPComms aborta la simulación
> (y provoca errores de hilo en cascada: `emit_signalp`, `set_process_mode`,
> `queue_redraw` desde el hilo de polling). Los sufijos legacy `_CMD` solo valen para
> S7/EIP; en OPC UA hay que escribir el NodeId completo.

El nombre resuelto debe coincidir con `name`/`nodeId` del server tree de Node-RED.

## Tabla de tipos de tag para máquinas (Maquina)

Los tags `cmd`/`exec`/`done`/`running`/`ready`/`fault`/`in_pos` son el patrón de la clase
`Maquina` (`src/Maquina/maquina.gd`). CeldaSpawner usa el subconjunto CMD/EXEC/DONE/
RUNNING/READY/COUNT/AUTO_ENABLE/RATE.
