# Node-RED flow — referencia

## Nodos del flujo (template `node-red/flows.json`)

| id | type | Config relevante |
|---|---|---|
| `oip-sim-tab` | tab | Tab del flujo |
| `oip-sim-server` | `opc-ua-server` | `port: 4840`, `serverName: "Node-RED OPC UA Server"`, `tree` (string JSON con las variables) |
| `oip-sim-inject` | inject | `repeat: "3"` (cada 3 s), `once: true` (dispara al arrancar), payload date (se ignora) |
| `oip-sim-func` | function | Arma `msg.payload` = array de `{name, path}` (regenerado desde el tree) |
| `oip-sim-io` | `opcua-server-io` | `mode: "read"`, `identifierType: "nodeId"`, `serverRef: "Node-RED OPC UA Server"` |
| `oip-sim-debug` | debug | `complete: "payload"` |
| `oip-sim-write-io` | `opcua-server-io` | `mode: "write"`; escribe tanto los botones de velocidad como las salidas del control |
| `oip-sim-inject-loop` | inject | Bucle de control: `repeat: "0.05"` (50 ms) + `once`; dispara `oip-sim-func` |
| `oip-sim-func-control` | function | Máquina de estados `RUN`/`HOLD`/`ROBOT` con feeds independientes (sensor → cinta/spawner/gantry); **generado** por `apply_control_flow.js` |
| `oip-sim-inject-speed-c1\|c2\|c3-05\|10\|20` | inject | 9 botones de velocidad (0.5 / 1.0 / 2.0 m/s por conveyor) |

> En el **desplegado** (`~/.node-red/flows.json`) el server tiene otro id
> (`1d09a28fb4f253d2`) y el tab `9752e5c455c4e742`, pero los ids `oip-sim-*`
> coinciden con el template. No tocar los nodos propios del usuario
> (`plca1`, `OPCLOCAL`, `opc1`).

## Cadena de escritura — botones de velocidad de conveyors

Los 3 belt conveyors exponen `BeltConveyor{,_2,_3}_Speed` en **dirección read**
(el simulador hace `speed = _speed_tag.read_float32()` en cada poll). Para
cambiarlas desde Node-RED se escribe en esas variables:

```
oip-sim-inject-speed-cX-YY (inject) ──► oip-sim-write-io (opcua-server-io, mode write) ──► server
```

- **9 botones `inject`** (`oip-sim-inject-speed-c1|2|3-05|10|20`): presets fijos
  0.5 / 1.0 / 2.0 m/s por conveyor. Cada uno manda
  `msg.payload = [{ "name": ..., "path": "ns=2;s=...", "value": <m/s> }]` con
  `payloadType: json`.
- **`oip-sim-write-io`**: `opcua-server-io` con `mode: "write"`,
  `identifierType: "nodeId"`, `serverRef: "Node-RED OPC UA Server"`.
  Escribe cada `value` en el NodeId `path` (mismo runtime `writeEventFromPayload`).
- Añadir un preset nuevo = duplicar un inject y cambiar `value` (o `name`/`path`
  para otro conveyor). El simulador lo aplica en el siguiente poll (`polling_rate` del
  grupo, 30 ms por defecto).
- `sync_deployed_flow.ps1` copia estos nodos del template al desplegado
  (reemplaza por id), así nunca se desfasan.

## Bucle de control (latencia)

`oip-sim-inject-loop` (inject `repeat: "0.05"`, 50 ms + `once`) dispara la lectura
(`oip-sim-func` → `oip-sim-io`) y alimenta `oip-sim-func-control`, que escribe las cintas
vía `oip-sim-write-io`. Es la cadencia con la que Node-RED "ve" los sensores. El read es
in-process (el server y el lector viven en el mismo proceso), así que el bucle puede ir a
30-50 ms sin coste; `oip-sim-func-control` usa write-on-change, no satura.

El retardo sensor→cintas = `polling_rate` del sim (write) + bucle Node-RED + `polling_rate`
del sim (read). Con poll 30 ms + bucle 50 ms → ~110 ms peor caso. Detalle y ajustes en
`references/control-flow.md` → "Latencia de control".

## Feeds independientes

La configuración actual separa la línea en dos feeds:

- `SensorCeldas` controla `BeltConveyor` + `BeltConveyor2` y `S1`.
- `SensorPlacers` controla `BeltConveyor3` y `S2`.

Cuando el sensor de un feed está activo, sus cintas reciben velocidad cero y su spawner queda deshabilitado. El otro feed conserva su estado. La disponibilidad se trata como nivel, por lo que un sensor que permanece ocupado puede alimentar ciclos sucesivos sin depender de un nuevo flanco descendente.

## Propiedad `tree` del `opc-ua-server`

La variable `tree` es un **string JSON** (escapado). Estructura:

```json
{
  "folders": [{
    "name": "Simulador",
    "namespaceId": 2,
    "variables": [
      {
        "name": "BeltConveyor_Speed",
        "type": "Float",
        "value": 0,
        "access": "readwrite",
        "description": "...",
        "nodeId": "ns=2;s=BeltConveyor_Speed",
        "namespaceId": 2
      }
    ]
  }]
}
```

Regla de oro: `nodeId` y `name` deben usar el mismo nombre; `namespaceId: 2` en el
folder y en cada variable; el `nodeId` debe ser idéntico al `tag_name` del simulador.

## Runtime del nodo `opcua-server-io` (child)

`opcua-server-runtime-child.js` (en `node-red/node_modules/@vitormnm/node-red-simple-opcua/server/lib/` — el paquete que aporta los nodos `opc-ua-server`/`opcua-server-io`):

- **Read** (`readFromPayload`):
  - `payload` array → `payload.map(readPayloadItem)` → cada item se lee por su campo
    **`path`** (que es el NodeId `ns=2;s=...`) → item devuelto: `{name, path, value, status}`.
  - `identifierType` se resuelve de `msg.opcuaServerIo.identifierType` (`"nodeId"` o
    `"path"`); con `nodeId` el `path` del item se usa como NodeId.
  - Fallos parciales → `status !== "Good"` → status del nodo `yellow` + evento
    `partialError`; los items OK se emiten igualmente.
- **Write** (`writeEventFromPayload`): array de `{name, path, value}` → escribe cada
  `value` en el NodeId `path`.

## Las variables actuales (server tree + func node) — 57

| name | type | dirección en sim |
|---|---|---|
| BeltConveyor_Speed | Float | read (PLC→sim) |
| BeltConveyor_Running | Boolean | write (sim→PLC) |
| BeltConveyor2_Speed | Float | read |
| BeltConveyor2_Running | Boolean | write |
| BeltConveyor3_Speed | Float | read |
| BeltConveyor3_Running | Boolean | write |
| Vastago_Extend | Boolean | read+write |
| S1_CMD | Int32 | read |
| S1_EXEC | Boolean | read |
| S1_DONE | Boolean | write |
| S1_RUNNING | Boolean | write |
| S1_READY | Boolean | write |
| S1_COUNT | Int32 | write |
| S1_AUTO_ENABLE | Boolean | read |
| S1_RATE | Float | read |
| Maquina1_Cut | Boolean | read |
| Maquina1_Release | Boolean | read |
| Maquina1_Z | Float | read |
| Maquina1_Y | Float | read |
| Maquina1_Speed | Float | read |
| Sensor1 | Boolean | **sin escritor** (legacy; ninguna parte lo registra ya) |
| SensorCeldas | Boolean | write (sensor de toma rama celdas, dispara Gantry1) |
| SensorPlacers | Boolean | write (sensor de toma rama placers, dispara Gantry2) |
| 6axisSensor1 | Boolean | write (disparo robot 6 ejes; lo comparten 6axisDiffuseSensor y TOPE) |
| S2_CMD | Int32 | read |
| S2_EXEC | Boolean | read |
| S2_DONE | Boolean | write |
| S2_RUNNING | Boolean | write |
| S2_READY | Boolean | write |
| S2_COUNT | Int32 | write |
| S2_AUTO_ENABLE | Boolean | read |
| S2_RATE | Float | read |
| Gantry1_Command | Int16 | read |
| Gantry1_Execute | Boolean | read |
| Gantry1_Done | Boolean | write |
| Gantry1_Vacuum | Boolean | read |
| Gantry2_Command | Int16 | read |
| Gantry2_Execute | Boolean | read |
| Gantry2_Done | Boolean | write |
| Gantry2_Vacuum | Boolean | read |
| Robot1_Command | Int16 | read |
| Robot1_Execute | Boolean | read |
| Robot1_Done | Boolean | write |
| Robot1_Vacuum | Boolean | read |
| IndexingBelt3_Step | Boolean | read (pulso de paso del flujo) |
| IndexingBelt3_Running | Boolean | write |
| H1_CMD | Int32 | read (dispara ciclo horno) |
| H1_EXEC | Boolean | read (pulso LOW→HIGH) |
| H1_DONE | Boolean | write |
| H1_RUNNING | Boolean | write |
| H1_READY | Boolean | write |
| H1_FAULT | Boolean | write |
| H1_IN_POS | Boolean | write (producto bajo el cabezal) |
| H1_SETPOINT | Float | read |
| H1_MV | Float | read (potencia heater 0–100 %) |
| H1_PV | Float | write (temperatura medida) |
| H1_CYCLE_TIME | Float | write |

Formato del array en `oip-sim-func`:

```js
msg.payload = [
  { "name": "BeltConveyor_Speed", "path": "ns=2;s=BeltConveyor_Speed" },
  // ...
];
return msg;
```

## Func node regenerado por el sync script

`sync_deployed_flow.ps1` genera el array automáticamente a partir de `tree.folders[0].variables`
(usa `name` y `nodeId` de cada variable), así el func nunca se desfasa del server tree.

## Gotcha: tags de estación de spawners (BadNodeIdUnknown)

Cada spawner (CeldaSpawner `S1`, PlacerSpawner `S2`) registra **8 tags** en OIPComms:
`<P>_CMD/_EXEC/_DONE/_RUNNING/_READY/_COUNT/_AUTO_ENABLE/_RATE`. Todos deben existir en el
`tree` del server (NodeId idéntico al de la escena). Si falta alguno, OIPComms aborta la
simulación al registrar el grupo:

```
OIPComms: Stopping simulation: OPC UA tag 'ns=2;s=S2_CMD' in group 'PLCSIM' is invalid
(BadNodeIdUnknown). The tag may not exist on the PLC, or may have been renamed or deleted.
```

El abort corre en el hilo de polling → además salen 3 errores de hilo del stub:
`The caller thread can't call the function Node::emit_signalp()...`.

**Causa típica:** se añadió el spawner a la escena (o se renombró su prefijo de estación)
pero el tree no se regeneró. `apply_control_flow.js` genera los 6 tags de estación por cada
spawner del config (tipos: `CMD` Int32, `COUNT` Int32, `EXEC/DONE/RUNNING/READY` Boolean)
además de `autoEnable` (Boolean) y `rateTag` (Float).

**Fix:** re-ejecutar el generador + sync + reiniciar Node-RED:

```bash
node .claude/skills/oip-nodered-comms/scripts/apply_control_flow.js --config node-red/control_config.json
powershell -File .claude/skills/oip-nodered-comms/scripts/sync_deployed_flow.ps1
```

> Regla de oro: **todo tag que la escena registra debe existir en el tree**. Verificar con
> el inventory de `Simulation.tscn` frente a las 57 variables de la tabla anterior.

## Fallo conocido (arranque del proyecto)

La cadena original solo leía 4 tags (A2, A5, A3, A4) con un server de 5 variables (A2,
Start, A3, A4, A5) → quedó desincronizada respecto al template de 26. La solución fue
sincronizar el desplegado desde el template con el script (backup previo en
`flows.json.bak-opencode`). Revisar siempre que `tree` y `oip-sim-func` vayan a la par.
